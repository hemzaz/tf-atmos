"""plan-sweep's varfile builder: turn one instance's describe JSON into a varfile.

Called by scripts/plan-sweep.sh once per stack/component pair, as

    python3 plan_sweep_varfile.py VARFILE STACK STACKS_DIR COMPONENTS_DIR < describe.json

and once at startup as `--self-test COMPONENTS_DIR`. Kept in its own file
rather than a heredoc because it grew an HCL reader and a self-test; the
contract with the shell is the four lines printed at the end, nothing else.

--process-functions=false leaves Atmos's YAML functions as literal strings:
'!terraform.state vpc/main .vpc_id' needs another component's state, and
'!env PROD_ELASTICACHE_AUTH_TOKEN' needs an environment variable. Neither is
available here. Rather than drop them all and report INCONCLUSIVE, substitute
a SYNTHETIC value, so the component's own validations are actually exercised.

For !terraform.state / !terraform.output the value is built the way Atmos
builds the real one: Atmos reads the target instance's outputs as a map and
evaluates the reference's yq expression over it (https://atmos.tools/functions/yaml/terraform.state).
So this script infers the SHAPE of the referenced output from the target
component's *.tf, builds a synthetic {output: value} document of that shape,
and runs the reference's ACTUAL expression over it with mikefarah yq v4 -- the
library Atmos itself uses. A map output fed through `[.x // {} | .[]]` comes
out a list; the same map passed as-is stays a map, and a list(string) variable
rejects it, exactly as it would with real state. Picking a value by the
CONSUMING variable's name could never see that: that is how #166 (acm's
certificate_arns map wired into monitoring's list(string)) passed this sweep.

Only when the output's shape cannot be inferred (a module output, say) does it
fall back to guessing by the variable's name, as it always did.
"""
import json
import os
import re
import subprocess
import sys

# ---------------------------------------------------------------------------
# Synthetic leaves.
#
# The values are deliberately WELL-FORMED -- vpc-0123456789abcdef0 is real hex,
# so rds's ^vpc-[a-f0-9]+$ still tests something.
#
# Looked up by the referenced OUTPUT's name first, then its singular, and only
# then by the consuming variable's name. Anything unmatched is dropped and the
# pair stays INCONCLUSIVE: a wrong guess is worse than an honest 'not checked'.
# ---------------------------------------------------------------------------
SYNTH = [
    (r'(^|_)vpc_id$',                 'vpc-0123456789abcdef0'),
    # Two subnets, not one: rds's subnet group and eks both require subnets in
    # two AZs, and a one-element list would fail those checks on our account.
    (r'subnet_ids$',                  ['subnet-0123456789abcdef0', 'subnet-0123456789abcdef1']),
    (r'(kms_key_id|kms_key_arn)$',    'arn:aws:kms:eu-west-2:123456789012:key/12345678-1234-1234-1234-123456789012'),
    (r'^zone_id$',                    'Z1234567890ABCDEFGHIJ'),
    (r'^certificate_arn$',            'arn:aws:acm:eu-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012'),
    (r'^certificate_arns$',           ['arn:aws:acm:eu-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012']),
    (r'^certificate_names$',          ['main_wildcard']),
    (r'^certificate_domains$',        ['example.com']),
    (r'^host$',                       'https://' + os.environ['PLAN_SWEEP_EKS_HOST']),
    (r'^cluster_name$',               'example-cluster'),
    (r'^oidc_provider_url$',          'oidc.eks.eu-west-2.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E'),
    (r'^oidc_provider_arn$',          'arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-west-2.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E'),
    (r'^ci_state_bucket_name$',       'example-terraform-state'),
    (r'(^|_)auth_token$',             'SyntheticAuthToken0123456789abcd'),
    (r'route_table_ids$',             ['rtb-0123456789abcdef0']),
    # apigateway's api_integrations[] carries the Lambda wiring. Without these
    # two the whole integration object was dropped, which tripped the
    # component's own "AWS_PROXY requires uri" validation and reported six
    # pairs as UNATTRIBUTABLE -- a script artefact, not a stack defect.
    (r'^uri$',                        'arn:aws:apigateway:eu-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-west-2:123456789012:function:example-function/invocations'),
    (r'^lambda_function_name$',       'example-function'),
    (r'^cognito_user_pool_arns$',     ['arn:aws:cognito-idp:eu-west-2:123456789012:userpool/eu-west-2_EXAMPLE1']),
    # Singular: ec2's instances[].subnet_id. The plural pattern above is
    # anchored, so it never matched this one.
    (r'^subnet_id$',                  'subnet-0123456789abcdef0'),
    (r'^key_name$',                   'example-keypair'),
    # ec2's allowed_ingress_rules[].security_groups -- source SG ids, not the
    # instance's own attachments.
    (r'^security_groups$',            ['sg-0123456789abcdef0']),
    (r'^vpc_associations$',           ['vpc-0123456789abcdef0']),
    # dns records[].records: a CNAME target, so it must be a hostname rather
    # than one of the id shapes above.
    (r'^records$',                    ['synthetic.example.com']),
]

# Only offered when the caller actually managed to generate one. An empty entry
# here would substitute '' and trip the kubernetes provider's PEM decode, which
# is exactly the self-inflicted failure the real certificate exists to avoid.
CA_CERT = os.environ.get('PLAN_SWEEP_CA_CERT') or ''
if CA_CERT:
    SYNTH.append((r'^cluster_ca_certificate$', CA_CERT))


def synth(name):
    for pat, val in SYNTH:
        if re.search(pat, name):
            return val
    return None


def singular(name):
    # certificate_arns -> certificate_arn, subnet_ids -> subnet_id,
    # table_names -> table_name, policies -> policy. Good enough for output
    # names; a wrong singular only means no leaf, which falls back.
    if name.endswith('ies'):
        return name[:-3] + 'y'
    if name.endswith('s') and not name.endswith('ss'):
        return name[:-1]
    return name


# Match an ACTUAL Atmos function, not merely a leading '!'. secretsmanager sets
# random_password_override_special to the literal '!#$%&*()-_=+[]{}<>:?', and
# treating that as an unresolved function suppressed a REAL defect: the guard
# in the caller downgraded its genuine precondition failure to INCONCLUSIVE.
ATMOS_FN = re.compile(r'^!(terraform\.state|terraform\.output|env|exec|include|template|store)\b')
TF_REF = re.compile(r'^!terraform\.(state|output)\s+(.*)$', re.S)

UNKNOWN, SCALAR, LIST, MAP = 'unknown', 'scalar', 'list', 'map'


# ---------------------------------------------------------------------------
# A small HCL reader. The CI image has python3 and nothing else -- no HCL
# library -- so this is text scanning, but with strings, interpolations,
# heredocs and comments skipped properly: a '{' inside "${...}" or a '#' in a
# string must not move the brace depth, or an output's value runs on into the
# next block and gets the wrong shape.
# ---------------------------------------------------------------------------
OPEN = {'{': '}', '[': ']', '(': ')'}
HEREDOC = re.compile(r'<<-?([A-Za-z_][A-Za-z0-9_]*)[ \t]*\n')


def skip_string(s, i):
    """s[i] is the opening quote; return the index just past the closing one."""
    i += 1
    while i < len(s):
        c = s[i]
        if c == '\\':
            i += 2
            continue
        if c == '"':
            return i + 1
        if s.startswith(('$${', '%%{'), i):   # escaped: a literal '${', no interpolation
            i += 3
            continue
        if c in '$%' and s.startswith('{', i + 1):
            i = skip_balanced(s, i + 1)
            continue
        i += 1
    return i


def skip_trivia(s, i):
    """Skip a comment, string or heredoc starting at i; return i unchanged if none."""
    if s.startswith('#', i) or s.startswith('//', i):
        j = s.find('\n', i)
        return len(s) if j < 0 else j
    if s.startswith('/*', i):
        j = s.find('*/', i + 2)
        return len(s) if j < 0 else j + 2
    if s[i] == '"':
        return skip_string(s, i)
    m = HEREDOC.match(s, i)
    if m:
        end = re.compile(r'^[ \t]*' + re.escape(m.group(1)) + r'[ \t]*$', re.M).search(s, m.end())
        return len(s) if end is None else end.end()
    return i


def skip_balanced(s, i):
    """s[i] opens a bracket; return the index just past its matching close."""
    stack = [OPEN[s[i]]]
    i += 1
    while i < len(s) and stack:
        j = skip_trivia(s, i)
        if j != i:
            i = j
            continue
        c = s[i]
        if c in OPEN:
            stack.append(OPEN[c])
        elif stack and c == stack[-1]:
            stack.pop()
        i += 1
    return i


def read_expr(s, i):
    """(expression, end) for the expression starting at i, up to the newline
    that ends it at depth 0."""
    start = i
    while i < len(s):
        j = skip_trivia(s, i)
        if j != i:
            if s.startswith('#', i) or s.startswith('//', i):
                break
            i = j
            continue
        c = s[i]
        if c in OPEN:
            i = skip_balanced(s, i)
            continue
        if c == '\n' or c == '}':
            break
        i += 1
    return s[start:i].strip(), i


def blocks(s, kind):
    """Yield (label, body) for every top-level `kind "label" {` (or `locals {`) block."""
    i = 0
    while i < len(s):
        j = skip_trivia(s, i)
        if j != i:
            i = j
            continue
        if s[i] == '{':
            i = skip_balanced(s, i)
            continue
        if (i == 0 or s[i - 1] == '\n') and s.startswith(kind, i):
            m = re.compile(re.escape(kind) + r'(?:[ \t]+"([^"]*)")?[ \t]*\{').match(s, i)
            if m:
                end = skip_balanced(s, m.end() - 1)
                yield m.group(1), s[m.end():end - 1]
                i = end
                continue
        i += 1


def attributes(body):
    """name -> expression for each top-level `name = expr` in a block body."""
    out = {}
    i = 0
    while i < len(body):
        j = skip_trivia(body, i)
        if j != i:
            i = j
            continue
        c = body[i]
        if c in OPEN:
            i = skip_balanced(body, i)
            continue
        m = re.compile(r'([A-Za-z_][A-Za-z0-9_-]*)[ \t]*=(?![=>])').match(body, i)
        if m and (i == 0 or body[i - 1] in ' \t\n'):
            expr, i = read_expr(body, m.end())
            out.setdefault(m.group(1), expr)
            continue
        i += 1
    return out


class Component:
    """Outputs, variable types and locals of one terraform component directory."""

    def __init__(self, path):
        self.outputs, self.var_types, self.locals = {}, {}, {}
        self.readable = False
        try:
            names = sorted(f for f in os.listdir(path) if f.endswith('.tf'))
        except OSError:
            return
        for name in names:
            with open(os.path.join(path, name), encoding='utf-8') as fh:
                s = fh.read()
            self.readable = True
            for label, body in blocks(s, 'output'):
                self.outputs.setdefault(label, attributes(body).get('value', ''))
            for label, body in blocks(s, 'variable'):
                self.var_types.setdefault(label, attributes(body).get('type', ''))
            for _, body in blocks(s, 'locals'):
                for k, v in attributes(body).items():
                    self.locals.setdefault(k, v)


def top_level(expr, chars):
    """Indices of any of chars in expr at bracket depth 0, outside strings."""
    hits, i = [], 0
    while i < len(expr):
        j = skip_trivia(expr, i)
        if j != i:
            i = j
            continue
        c = expr[i]
        if c in OPEN:
            i = skip_balanced(expr, i)
            continue
        if c in chars:
            hits.append(i)
        i += 1
    return hits


def whole(expr, i):
    """True when the bracket opening at i closes at the very end of expr."""
    return skip_balanced(expr, i) == len(expr)


LIST_FNS = {'values', 'keys', 'concat', 'compact', 'distinct', 'flatten', 'tolist',
            'toset', 'sort', 'slice', 'split', 'reverse', 'setunion', 'setintersection',
            'setsubtract', 'range', 'chunklist'}
MAP_FNS = {'merge', 'tomap', 'zipmap'}
# Obviously scalar: one() collapses a zero-or-one list; the rest build strings
# or numbers. Nothing here is a guess about an attribute's type.
SCALAR_FNS = {'one', 'format', 'join', 'jsonencode', 'tostring', 'tonumber', 'tobool',
              'lower', 'upper', 'replace', 'trimprefix', 'trimsuffix', 'trimspace',
              'substr', 'length', 'base64encode', 'md5', 'sha256'}
FIRST_ARG_FNS = {'try', 'coalesce'}
FN_CALL = re.compile(r'^([a-z][a-z0-9_]*)\(')
# A resource or data source attribute: aws_vpc.main.id, aws_x.y[0].arn,
# data.aws_caller_identity.current.account_id. A plural attribute name is left
# UNKNOWN rather than called scalar -- tags, subnet_ids and friends are
# collections, and calling one a scalar would manufacture a type error.
RESOURCE_ATTR = re.compile(
    r'^(data\.)?[a-z][a-z0-9_]*\.[A-Za-z0-9_-]+(\[0\])?\.([A-Za-z_][A-Za-z0-9_]*)$')
PLURAL_ATTR = re.compile(r'(^tags(_all)?|[^s]s)$')


def split_args(inner):
    cuts = top_level(inner, ',')
    parts, prev = [], 0
    for c in cuts + [len(inner)]:
        parts.append(inner[prev:c].strip())
        prev = c + 1
    return [p for p in parts if p]


def type_shape(t):
    t = t.strip()
    if re.match(r'^(list|set|tuple)\s*\(', t):
        return LIST
    if re.match(r'^(map|object)\s*\(', t):
        return MAP
    if t in ('string', 'number', 'bool'):
        return SCALAR
    return UNKNOWN


def shape_of(expr, comp, depth=0):
    """map / list / scalar / unknown for an output's value expression."""
    e = expr.strip()
    if not e or depth > 3:
        return UNKNOWN
    while e.startswith('(') and whole(e, 0):
        e = e[1:-1].strip()
    q = top_level(e, '?')
    if q:
        colons = top_level(e[q[0] + 1:], ':')
        if colons:
            a = e[q[0] + 1:q[0] + 1 + colons[0]]
            b = e[q[0] + 2 + colons[0]:]
            got = shape_of(a, comp, depth + 1)
            return got if got != UNKNOWN else shape_of(b, comp, depth + 1)
        return UNKNOWN
    if e[0] == '{' and whole(e, 0):
        return MAP
    if e[0] == '[' and whole(e, 0):
        return LIST
    if e[0] == '"' and skip_string(e, 0) == len(e):
        return SCALAR
    if re.match(r'^(-?[0-9][0-9.]*|true|false)$', e):
        return SCALAR
    m = FN_CALL.match(e)
    if m and whole(e, m.end() - 1):
        fn, args = m.group(1), split_args(e[m.end():-1])
        if fn in LIST_FNS:
            return LIST
        if fn in MAP_FNS:
            return MAP
        if fn in SCALAR_FNS:
            return SCALAR
        if fn in FIRST_ARG_FNS and args:
            return shape_of(args[0], comp, depth + 1)
        return UNKNOWN
    if e.startswith('module.'):
        return UNKNOWN
    if '[*]' in e or '.*.' in e:
        return LIST
    m = re.match(r'^var\.([A-Za-z_][A-Za-z0-9_-]*)$', e)
    if m:
        return type_shape(comp.var_types.get(m.group(1), ''))
    m = re.match(r'^local\.([A-Za-z_][A-Za-z0-9_-]*)$', e)
    if m:
        return shape_of(comp.locals.get(m.group(1), ''), comp, depth + 1) if depth < 2 else UNKNOWN
    m = RESOURCE_ATTR.match(e)
    if m and not e.startswith(('var.', 'local.', 'each.', 'count.', 'path.', 'terraform.')):
        return UNKNOWN if PLURAL_ATTR.search(m.group(3)) else SCALAR
    return UNKNOWN


# ---------------------------------------------------------------------------
# References.
# ---------------------------------------------------------------------------
def parse_ref(s):
    """(kind, instance, stack-or-None, yq expression) for a !terraform.* string.

    `<instance> <yq>` or `<instance> <stack> <yq>`. The yq expression is the
    REST of the string and may hold spaces and pipes ('.bucket_name | "s3://"
    + . + "/data/"'), so a stack is recognised by not starting with '.' or '['
    -- a yq path always does. A bare output name (`vpc vpc_id`, Atmos's short
    form) is the path `.vpc_id`.
    """
    m = TF_REF.match(s.strip())
    if not m:
        return None
    parts = m.group(2).strip().split(None, 2)
    if len(parts) < 2:
        return None
    instance, stack = parts[0], None
    rest = m.group(2).strip()[len(instance):].strip()
    if len(parts) == 3 and not parts[1].startswith(('.', '[')):
        stack, rest = parts[1], parts[2].strip()
    if re.match(r'^[A-Za-z_][A-Za-z0-9_-]*$', rest):
        rest = '.' + rest
    return m.group(1), instance, stack, rest


def first_output(expr):
    """The output an expression reads: the first `.name` path segment, outside strings."""
    i = 0
    while i < len(expr):
        j = skip_trivia(expr, i)
        if j != i:
            i = j
            continue
        m = re.compile(r'\.([A-Za-z_][A-Za-z0-9_-]*)').match(expr, i)
        if m and (i == 0 or not re.match(r'[A-Za-z0-9_\]\)]', expr[i - 1])):
            return m.group(1)
        i += 1
    return None


def accessed_keys(expr, output):
    """Keys an expression reads directly off a map output: `.certificate_arns.main_wildcard`."""
    pat = re.compile(r'\.' + re.escape(output) + r'(?:\.([A-Za-z_][A-Za-z0-9_-]*)|\["([^"]+)"\])')
    return {a or b for a, b in pat.findall(expr)}


def yq_eval(expr, doc):
    """(value, error). Exactly one result document, or it is an error."""
    try:
        p = subprocess.run(['yq', '-p=json', '-o=json', '-I=0', expr], input=json.dumps(doc),
                           capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, str(exc)
    if p.returncode != 0:
        return None, (p.stderr.strip().splitlines() or ['yq exited %d' % p.returncode])[-1]
    lines = [ln for ln in p.stdout.splitlines() if ln.strip()]
    if len(lines) != 1:
        return None, 'yielded %d results, not one' % len(lines)
    return json.loads(lines[0]), None


class Resolver:
    """Everything needed to build a reference's value within one stack."""

    def __init__(self, stack, stacks_dir, components_dir):
        self.stack, self.stacks_dir, self.components_dir = stack, stacks_dir, components_dir
        self._stacks, self._components, self._keys = {}, {}, {}

    def instances(self, stack):
        # One `atmos describe stacks` per stack, written by the shell before the
        # loop. A stack named explicitly in a reference is described here, once.
        if stack not in self._stacks:
            path = os.path.join(self.stacks_dir, stack + '.json')
            if not os.path.exists(path):
                with open(path + '.err', 'w') as err:
                    p = subprocess.run(['atmos', 'describe', 'stacks', '--process-functions=false',
                                        '--format', 'json', '-s', stack],
                                       stdout=subprocess.PIPE, stderr=err, text=True)
                if p.returncode != 0:
                    self._stacks[stack] = None
                    return None
                with open(path, 'w') as fh:
                    fh.write(p.stdout)
            with open(path) as fh:
                d = json.load(fh)
            self._stacks[stack] = ((d.get(stack) or {}).get('components') or {}).get('terraform') or {}
        return self._stacks[stack]

    def component(self, name):
        if name not in self._components:
            self._components[name] = Component(os.path.join(self.components_dir, name))
        return self._components[name]

    def keys(self, stack, instance, output):
        # Every key ANY reference in the stack reads off this map output, so
        # `.certificate_arns.main_wildcard` finds main_wildcard in the synthetic
        # map instead of null.
        k = (stack, instance, output)
        if k not in self._keys:
            found = set()
            for c in (self.instances(stack) or {}).values():
                for ref in refs_in(c.get('vars') or {}):
                    r = parse_ref(ref)
                    if r and r[1] == instance and (r[2] or stack) == stack:
                        found |= accessed_keys(r[3], output)
            self._keys[k] = sorted(found)
        return self._keys[k]


def refs_in(node):
    if isinstance(node, str):
        if TF_REF.match(node):
            yield node
    elif isinstance(node, dict):
        for x in node.values():
            yield from refs_in(x)
    elif isinstance(node, list):
        for x in node:
            yield from refs_in(x)


def leaf_for(output, var):
    for name in (output, singular(output), var):
        got = synth(name)
        if isinstance(got, list):
            got = got[0] if got else None
        if got is not None:
            return got
    return None


def synthetic_output(shape, output, var, keys):
    """The synthetic value of an output of this shape, or None."""
    if shape == LIST:
        # A list output named like a synthetic list keeps all of it: two
        # subnets, not one, for the reasons given at SYNTH.
        whole_list = synth(output)
        if isinstance(whole_list, list) and whole_list:
            return list(whole_list)
    leaf = leaf_for(output, var)
    if leaf is None:
        return None
    if shape == SCALAR:
        return leaf
    if shape == LIST:
        return [leaf]
    if shape == MAP:
        return {k: leaf for k in (keys or ['synthetic'])}
    return None


def resolve_ref(s, var, resolver):
    """('shaped', value) | ('fallback', None) | ('defect', message)."""
    r = parse_ref(s)
    if r is None:
        return 'fallback', None
    _, instance, stack, expr = r
    stack = stack or resolver.stack
    instances = resolver.instances(stack)
    if instances is None:
        return 'fallback', None
    target = instances.get(instance)
    # An abstract instance is never deployed, so it has no state to read either.
    if target is None:
        return 'defect', '%s: instance %s does not exist in stack %s' % (var, instance, stack)
    if (target.get('metadata') or {}).get('type') == 'abstract':
        return 'defect', '%s: instance %s is abstract in stack %s, so it has no state' % (
            var, instance, stack)
    comp_name = target.get('component') or (target.get('metadata') or {}).get('component') \
        or instance.split('/')[0]
    comp = resolver.component(comp_name)
    output = first_output(expr)
    if output is None or not comp.readable or not comp.outputs:
        return 'fallback', None
    if output not in comp.outputs:
        return 'defect', '%s: %s (component %s) declares no output "%s" (%s)' % (
            var, instance, comp_name, output, s)
    shape = shape_of(comp.outputs[output], comp)
    if shape == UNKNOWN:
        return 'fallback', None
    value = synthetic_output(shape, output, var, resolver.keys(stack, instance, output))
    if value is None:
        return 'fallback', None
    got, err = yq_eval(expr, {output: value})
    if err is not None:
        return 'defect', '%s: yq cannot evaluate %r: %s' % (var, expr, err)
    if got is None:
        return 'fallback', None
    return 'shaped', got


SENTINEL = object()


class Builder:
    def __init__(self, resolver):
        self.resolver = resolver
        self.dropped, self.defects = [], []
        self.counts = {'shaped': 0, 'fallback': 0, 'dropped': 0}

    def function(self, key, node):
        """(value, from_fallback) for an Atmos function string, or (SENTINEL, _)."""
        if TF_REF.match(node) and self.resolver is not None:
            kind, got = resolve_ref(node, key, self.resolver)
            if kind == 'shaped':
                self.counts['shaped'] += 1
                return got, False
            if kind == 'defect':
                self.defects.append(got)
                return SENTINEL, False
        got = synth(key)
        if got is None:
            self.counts['dropped'] += 1
            self.dropped.append(key)
            return SENTINEL, False
        self.counts['fallback'] += 1
        return got, True

    def walk(self, key, node):
        # Atmos functions are not only top-level: network/vpc-peering hides one in
        # route_table_ids INSIDE a list of route objects. Missing those leaves the
        # literal '!terraform.state ...' string in a typed structure, which fails as
        # a type error and looks like a component defect. Recurse.
        if isinstance(node, str) and ATMOS_FN.match(node):
            return self.function(key, node)[0]
        if isinstance(node, dict):
            out = {}
            for k, x in node.items():
                r = self.walk(k, x)
                if r is not SENTINEL:
                    out[k] = r
            return out
        if isinstance(node, list):
            out = []
            for x in node:
                if isinstance(x, str) and ATMOS_FN.match(x):
                    r, guessed = self.function(key, x)   # keep the owning key: list items are unnamed
                else:
                    r, guessed = self.walk(key, x), False
                if r is SENTINEL:
                    continue
                if guessed and isinstance(r, list):
                    # A NAME-GUESSED list for one item: the guess cannot know the
                    # item is a single element, and nesting it would be a type
                    # error of this script's making. Splice it. Only guesses:
                    # Atmos never splices, so an output-shaped list in a list IS
                    # the nested list the component will receive -- a defect.
                    for item in r:
                        if item not in out:
                            out.append(item)
                else:
                    out.append(r)
            return out
        return node


def build(describe, stack, stacks_dir, components_dir):
    resolver = Resolver(stack, stacks_dir, components_dir) if stack else None
    b = Builder(resolver)
    top = {}
    for k, x in (describe.get('vars') or {}).items():
        r = b.walk(k, x)
        if r is not SENTINEL:
            top[k] = r
    return top, b


# ---------------------------------------------------------------------------
# Self-test, run by the shell before any pair. Built against the REAL acm and
# vpc components, so a change there that this reader cannot follow fails here
# rather than silently falling back.
# ---------------------------------------------------------------------------
def self_test(components_dir, tmp):
    failures = []

    def check(what, got, want):
        if got != want:
            failures.append('%s: got %r, want %r' % (what, got, want))

    stack = 'selftest'
    stacks = {stack: {'components': {'terraform': {
        'acm/main': {'component': 'acm', 'vars': {
            'x': '!terraform.state acm/main .certificate_arns.main_wildcard'}},
        'vpc/main': {'component': 'vpc', 'vars': {}},
    }}}}
    os.makedirs(tmp, exist_ok=True)
    with open(os.path.join(tmp, stack + '.json'), 'w') as fh:
        json.dump(stacks, fh)
    res = Resolver(stack, tmp, components_dir)
    acm, vpc = res.component('acm'), res.component('vpc')
    check('acm certificate_arns shape', shape_of(acm.outputs.get('certificate_arns', ''), acm), MAP)
    check('vpc vpc_id shape', shape_of(vpc.outputs.get('vpc_id', ''), vpc), SCALAR)
    check('vpc private_subnet_ids shape', shape_of(vpc.outputs.get('private_subnet_ids', ''), vpc), LIST)
    for expr, want in [
        ('{ for k, v in x : k => "${v}}" }', MAP), ('[for c in var.a : c]', LIST),
        ('aws_x.y[*].arn', LIST), ('one(aws_x.y[*].arn)', SCALAR), ('merge(a, {})', MAP),
        ('var.enabled ? aws_x.y[0].id : null', SCALAR), ('try(values(a), [])', LIST),
        ('module.kms.key_arn', UNKNOWN), ('aws_x.y.tags', UNKNOWN), ('aws_x.y.id', SCALAR),
    ]:
        check('shape of %s' % expr, shape_of(expr, acm), want)

    # #166: the map, passed as-is, must stay a map -- so monitoring's
    # list(string) rejects it -- and the fixed expression must yield a list.
    kind, bug = resolve_ref('!terraform.state acm/main .certificate_arns // {}', 'certificate_arns', res)
    check('#166 bug form kind', kind, 'shaped')
    check('#166 bug form is an object', isinstance(bug, dict), True)
    kind, fixed = resolve_ref('!terraform.state acm/main [.certificate_arns // {} | .[]]',
                              'certificate_arns', res)
    check('#166 fixed form is a list of strings',
          (kind, isinstance(fixed, list) and all(isinstance(x, str) for x in fixed)), ('shaped', True))
    _, key = resolve_ref('!terraform.state acm/main .certificate_arns.main_wildcard', 'certificate_arn', res)
    check('map key accessor', isinstance(key, str) and key.startswith('arn:aws:acm:'), True)
    check('s3:// concatenation', resolve_ref('!terraform.state vpc/main .vpc_id | "s3://" + . + "/data/"',
                                             'x', res), ('shaped', 's3://vpc-0123456789abcdef0/data/'))
    check('[0] index', resolve_ref('!terraform.state vpc/main .private_subnet_ids[0]', 'subnet_id', res),
          ('shaped', 'subnet-0123456789abcdef0'))
    check('missing instance', resolve_ref('!terraform.state nope/main .x', 'v', res)[0], 'defect')
    check('missing output', resolve_ref('!terraform.state vpc/main .no_such_output', 'v', res)[0], 'defect')
    check('yq error', resolve_ref('!terraform.state vpc/main .vpc_id | ][', 'v', res)[0], 'defect')
    check('3-arg form', parse_ref('!terraform.state vpc other-stack .a | "x" + .'),
          ('state', 'vpc', 'other-stack', '.a | "x" + .'))
    check('short form', parse_ref('!terraform.state vpc vpc_id'), ('state', 'vpc', None, '.vpc_id'))

    # Only a name-guessed list is spliced into its parent list; an
    # output-shaped one is inserted as-is, as Atmos would.
    top, _ = build({'vars': {
        'subnet_ids': ['!terraform.state vpc/main .private_subnet_ids'],
    }}, stack, tmp, components_dir)
    check('shaped list is not spliced', top['subnet_ids'],
          [['subnet-0123456789abcdef0', 'subnet-0123456789abcdef1']])
    top, _ = build({'vars': {'subnet_ids': ['!env X']}}, None, None, None)
    check('guessed list is spliced', top['subnet_ids'],
          ['subnet-0123456789abcdef0', 'subnet-0123456789abcdef1'])
    return failures


def main(argv):
    if len(argv) == 4 and argv[1] == '--self-test':
        failures = self_test(argv[2], argv[3])
        for f in failures:
            print(f, file=sys.stderr)
        return 1 if failures else 0

    varfile, stack, stacks_dir, components_dir = argv[1:5]
    d = json.load(sys.stdin)
    top, b = build(d, stack, stacks_dir, components_dir)
    with open(varfile, 'w') as fh:
        json.dump(top, fh)

    # Line 1: the TERRAFORM component, which is not the instance name. network/main
    # and network/services both set metadata.component: dns, and deriving the
    # directory from the instance name instead planned components/terraform/network
    # with dns's variables while never sweeping dns at all.
    #
    # Line 2: WHICH functions had no synthetic, not merely how many. Dropping one
    # can invalidate the structure AROUND it -- apigateway's AWS_PROXY integration
    # needs its uri, and removing it trips the component's own 'must set uri' rule.
    # A failure this script may have manufactured must not be reported as the
    # component's, and the names are what let a reader decide which one it was.
    #
    # Line 3: reference defects -- a missing instance, a missing output, an
    # expression yq rejects -- joined by TAB. Each fails with real state too.
    #
    # Line 4: how many references were output-shaped, name-guessed, dropped.
    print(d.get('component') or (d.get('metadata') or {}).get('component') or '')
    print(','.join(sorted(set(b.dropped))))
    print('\t'.join(m.replace('\t', ' ').replace('\n', ' ') for m in b.defects))
    print('%d %d %d' % (b.counts['shaped'], b.counts['fallback'], b.counts['dropped']))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
