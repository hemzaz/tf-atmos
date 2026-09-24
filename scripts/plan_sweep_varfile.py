"""plan-sweep's varfile builder: turn one instance's describe JSON into a varfile.

Called by scripts/plan-sweep.sh once per stack/component pair, as

    python3 plan_sweep_varfile.py VARFILE STACK STACKS_DIR COMPONENTS_DIR < describe.json

and once at startup as `--self-test COMPONENTS_DIR TMPDIR` (which also runs
by hand, from anywhere). Kept out of the shell script because it grew an HCL
reader (plan_sweep_hcl.py) and a self-test; the contract with the shell is the
five lines printed at the end, nothing else.

--process-functions=false leaves Atmos's YAML functions as literal strings:
'!terraform.state vpc/main .vpc_id' needs another component's state, and
'!env PROD_ELASTICACHE_AUTH_TOKEN' needs an environment variable. Neither is
available here. Rather than drop them all and report INCONCLUSIVE, substitute
a SYNTHETIC value, so the component's own validations are actually exercised.

For !terraform.state / !terraform.output the value is built the way Atmos
builds the real one (Atmos v1.229.0, https://atmos.tools/functions/yaml/terraform.state):

  - the arguments are split by Atmos's own grammar (pkg/function/parser,
    ParseTerraform), ported below as parse_ref;
  - the expression gets a leading '.' unless it already starts with one
    (GetTerraformBackendVariable, extractYqValue) -- so `[.a | .[]]` is really
    `.[.a | .[]]`, an INDEX into the outputs, not a list constructor;
  - mikefarah yq v4 evaluates it over the outputs map, and the printed result
    is re-read as YAML (pkg/utils EvaluateYqExpression): several results come
    back as ONE string joined by spaces, not as a list. See atmos_yq.

This script infers the SHAPE of each referenced output from the target
component's *.tf, builds a synthetic outputs map of that shape, and runs the
reference through the same three steps. Guessing a value from the CONSUMING
variable's name could never see a shape mismatch: that is how #166 (acm's
certificate_arns map wired into monitoring's list(string)) passed this sweep,
and how its first fix, `[.certificate_arns // {} | .[]]` -- which real Atmos
turns into the string "null null" -- would have passed it again.

Only when the output's shape cannot be inferred does it fall back to guessing
by the variable's name, as it always did; the fallback is counted, not silent.

What is modelled is the S3 backend path, the one these stacks use. The static
remote_state_backend differs in corners -- a missing output is an error there
rather than null -- and those quirks are not modelled.
"""
import csv
import json
import os
import re
import subprocess
import sys

# The shapes and the HCL reader live next to this file, in plan_sweep_hcl.py.
from plan_sweep_hcl import (
    BOOL, IDENT, LIST, MAP, NUMBER, OBJ, SCALAR, UNKNOWN, Ctx, blocks, known, load_component,
    shape_of,
)

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
# A default, so that `--self-test` run by hand works without the shell's
# environment; the sweep always exports the real constant.
EKS_HOST = os.environ.get('PLAN_SWEEP_EKS_HOST', 'EXAMPLE0123456789.gr7.eu-west-2.eks.amazonaws.com')

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
    (r'^host$',                       'https://' + EKS_HOST),
    (r'^cluster_name$',               'example-cluster'),
    # Cloud Posse eks/cluster and ec2-instance output names, so a reference is
    # valued by the output it reads, not by the consuming variable's name.
    (r'^eks_cluster_id$',             'example-cluster'),
    # The same synthetic host as `host`, which the diagnostic classifier
    # recognises when it fails to resolve.
    (r'^eks_cluster_endpoint$',       'https://' + EKS_HOST),
    (r'^eks_cluster_identity_oidc_issuer$', 'https://oidc.eks.eu-west-2.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E'),
    (r'^eks_cluster_identity_oidc_issuer_arn$', 'arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-west-2.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E'),
    (r'^ssh_key_pair$',               'example-keypair'),
    (r'^security_group_id$',          'sg-0123456789abcdef0'),
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
    # security-monitoring consumes guardduty's detector and securityhub's hub.
    (r'^detector_id$',                '12abc34d567e8fa901bc2d34e56789f0'),
    (r'^account_arn$',                'arn:aws:securityhub:eu-west-2:123456789012:hub/default'),
]

# Only offered when the caller actually managed to generate one. An empty entry
# here would substitute '' and trip the kubernetes provider's PEM decode, which
# is exactly the self-inflicted failure the real certificate exists to avoid.
CA_CERT = os.environ.get('PLAN_SWEEP_CA_CERT') or ''
if CA_CERT:
    SYNTH.append((r'^cluster_ca_certificate$', CA_CERT))
    SYNTH.append((r'^eks_cluster_certificate_authority_data$', CA_CERT))


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
TF_REF = re.compile(r'^!terraform\.(state|output)(?:\s+(.*))?$', re.S)


# ---------------------------------------------------------------------------
# References: Atmos's own argument grammar, ported from
# pkg/function/parser/parser.go (ParseTerraform, Atmos v1.229.0). Anything
# Atmos rejects is rejected here, as a defect: `(.vpc_id // "x")` is a parse
# error in Atmos, and reading it as a stack name and falling back used to pass
# it silently.
# ---------------------------------------------------------------------------
class ParseError(Exception):
    pass


# Whitespace, then a quoted token ("" and '' escape their own quote), a pipe,
# or a run of anything else. Tried in this order at each position, as the
# participle lexer does.
TOKEN = re.compile(r'''(\s+)|("(?:[^"\r\n]|"")*"|'(?:[^'\r\n]|'')*')|(\|)|([^\s|]+)''')


def tokenize(s):
    out, i = [], 0
    while i < len(s):
        m = TOKEN.match(s, i)
        if m.group(1) is None:
            kind = 'quoted' if m.group(2) else 'pipe' if m.group(3) else 'text'
            if kind == 'text' and m.group(0)[0] in '"\'':
                raise ParseError('unterminated quoted value at %d' % i)
            out.append((m.group(0), kind, i))
        i = m.end()
    return out


def unquote(v):
    v = v.strip()
    if len(v) < 2 or v[0] != v[-1]:
        return v
    if v[0] == "'":
        return v[1:-1].replace("''", "'")
    if v[0] == '"':
        return v[1:-1].replace('""', '"')
    return v


def is_expression_start(v):
    v = v.strip()
    return bool(v) and v[0] in '.[{|\'"'


def parse_args(s):
    """(instance, stack or None, expression) for `component [stack] expression`."""
    tokens = tokenize(s)
    last = tokens[-1] if tokens else None
    if last and len(tokens) in (2, 3) and last[1] == 'quoted' and last[0].startswith('"') \
            and '""' in last[0]:
        # Atmos's legacy CSV form, kept for compatibility there, so here too.
        parts = [p.strip() for p in next(csv.reader([s], delimiter=' ', skipinitialspace=True))]
        if 2 <= len(parts) <= 3:
            return (parts[0], None, parts[1]) if len(parts) == 2 else tuple(parts)
    if not tokens:
        raise ParseError('expected arguments')
    if len(tokens) == 1:
        raise ParseError('terraform function requires 2 or 3 arguments')
    instance = unquote(tokens[0][0])
    if len(tokens) == 2 or is_expression_start(tokens[1][0]):
        expr = unquote(s[tokens[1][2]:].strip())
        stack = None
    else:
        if len(tokens) > 3 and not is_expression_start(tokens[2][0]):
            raise ParseError('terraform function requires 2 or 3 arguments')
        stack = unquote(tokens[1][0])
        expr = unquote(s[tokens[2][2]:].strip())
    if not instance:
        raise ParseError('component must not be empty')
    if not expr:
        raise ParseError('output expression must not be empty')
    return instance, stack, expr


def parse_ref(s):
    """(kind, instance, stack or None, expression) for a !terraform.* string;
    None if it is not one; ParseError where Atmos would refuse it."""
    m = TF_REF.match(s.strip())
    if not m:
        return None
    instance, stack, expr = parse_args(m.group(2) or '')
    return (m.group(1), instance, stack, expr)


def atmos_expr(expr):
    """The expression as Atmos hands it to yq: with a leading '.' prepended when
    it has none (GetTerraformBackendVariable / extractYqValue). This is why
    `[.a // {} | .[]]` is an index, `.[...]`, and not a list constructor."""
    return expr if expr.startswith('.') else '.' + expr


def skip_yq_string(e, i):
    """e[i] opens a double-quoted yq string; the index just past its close."""
    i += 1
    while i < len(e) and e[i] != '"':
        i += 2 if e[i] == '\\' else 1
    return i + 1


def has_alternative(expr):
    """True when the expression uses yq's '//' alternative operator -- outside
    a string: the '//' of `"s3://" + .` is no default, and reading it as one
    turned a broken reference into a stale warning."""
    i = 0
    while i < len(expr):
        if expr[i] == '"':
            i = skip_yq_string(expr, i)
            continue
        if expr.startswith('//', i) and not expr.startswith('//=', i):
            return True
        i += 1
    return False


def root_outputs(expr):
    """Every output an expression reads off the ROOT of the outputs map.

    A yq-aware scan: only double-quoted strings are skipped -- '//' is yq's
    alternative operator and '#' is not a comment, so the HCL skipper would
    swallow the rest of `.a // .b`. A `.name` counts when no '|' has come
    before it in its own bracket group or an enclosing one: after a pipe the
    context is the piped value, not the outputs map.
    """
    e = atmos_expr(expr)
    names, piped, i = [], [False], 0
    while i < len(e):
        c = e[i]
        if c == '"':
            i = skip_yq_string(e, i)
            continue
        if c in '([{':
            piped.append(piped[-1])
        elif c in ')]}' and len(piped) > 1:
            piped.pop()
        elif c == '|':
            piped[-1] = True
        elif c == '.' and not piped[-1] and (i == 0 or not re.match(r'[\w\]\)".]', e[i - 1])):
            m = re.compile(IDENT).match(e, i + 1)
            if m and m.group(0) not in names:
                names.append(m.group(0))
        i += 1
    return names


def accessed_keys(expr, output):
    """Keys an expression reads off a map output by name.

    `.m.k`, `.m["k"]`, then the same through a pipe -- `.m | .k`, `.m // {} |
    .["k"]`, `.m | ."k"` -- and a `select(.key == "k")` anywhere in an
    expression that reads the output (`to_entries | map(select(...))`,
    `with_entries(select(...))`). A key read any other way is not collected,
    and resolve_ref falls back when that is what made the result null.

    Deliberately broad: the sweep cannot see a map's real keys, so every key
    a reference names is assumed to exist -- a typo'd key included, as
    `.m.typo` always was -- and a select() adds its key to every output its
    expression reads, even when it filters a different map. More keys only
    mean more values, never a missed parse or yq error.
    """
    o = re.escape(output)
    quoted = r'"([^"\\]+)"'
    found = set()
    direct = re.compile(r'\.' + o + r'(?:\.(' + IDENT + r')|\[' + quoted + r'\])')
    piped = re.compile(r'\.' + o + r'\s*(?://\s*(?:\{\s*\}|null)\s*)?\|\s*\.(?:(' + IDENT + r')|\[?'
                       + quoted + r'\]?)')
    for pat in (direct, piped):
        found |= {a or b for a, b in pat.findall(expr)}
    if output in root_outputs(expr):
        sel = re.compile(r'select\(\s*(?:\.key\s*==\s*' + quoted + r'|' + quoted + r'\s*==\s*\.key)\s*\)')
        found |= {a or b for a, b in sel.findall(expr)}
    return found


def candidate_keys(expr):
    """Every name or double-quoted string in an expression: the keys it could
    possibly read off a map, collected or not."""
    return set(re.findall(r'\.(' + IDENT + r')', expr)) | set(re.findall(r'"([^"\\]*)"', expr))


def is_scalar_string(s):
    # EvaluateYqExpression's isScalarString, verbatim in behaviour.
    if s.startswith('#') and '\n' not in s:
        return True
    if s == '' or s.startswith(('{', '[')) or '\n' in s:
        return False
    return s.endswith(':') and ': ' not in s


def run_yq(args, stdin):
    try:
        p = subprocess.run(['yq'] + args, input=stdin, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, str(exc)
    if p.returncode != 0:
        return None, (p.stderr.strip().splitlines() or ['yq exited %d' % p.returncode])[-1]
    return p.stdout, None


def atmos_yq(expr, data):
    """(value, error) exactly as Atmos's !terraform.state would produce it.

    pkg/utils EvaluateYqExpression prints the result as YAML with scalars
    unwrapped and parses that text back as YAML. Several results therefore come
    back as one plain scalar spanning lines -- `null\\nnull` reads as the STRING
    "null null" -- never as a list, and never as an error. Reproduced with the
    same yq: evaluate to YAML, then re-read the YAML with yq.
    """
    # Keys sorted, as Atmos's ConvertToYAML sorts them: `.[]` over a map, and
    # anything joined from it, comes out in that order.
    out, err = run_yq(['-p=json', '-o=yaml', '-I=2', atmos_expr(expr)],
                      json.dumps(data, sort_keys=True))
    if err is not None:
        return None, err
    trimmed = out.strip()
    if is_scalar_string(trimmed):
        return trimmed, None
    # Several MAP results print as one mapping. Distinct keys merge -- real
    # Atmos returns the union -- but a repeated key makes Atmos's final
    # unmarshal fail (`.m | to_entries | .[]`), while yq's own YAML reader
    # would quietly keep one of them: a false PASS.
    top_keys = TOP_KEY.findall(out)
    if len(top_keys) != len(set(top_keys)):
        return None, 'the result repeats a top-level key, which Atmos cannot unmarshal'
    parsed, err = run_yq(['-p=yaml', '-o=json', '-I=0', '.'], out)
    if err is not None:
        if '\n' not in trimmed:
            return trimmed, None
        return None, 'result is not YAML: %s' % err
    lines = [ln for ln in parsed.splitlines() if ln.strip()]
    if len(lines) != 1:
        return None, 'result is %d YAML documents' % len(lines)
    value = json.loads(lines[0])
    # isMisinterpretedScalar: "value:" parses as {"value": null}.
    if isinstance(value, dict) and len(value) == 1:
        (k, v), = value.items()
        if v is None and trimmed in (k + ':', k + '::'):
            return trimmed, None
    return value, None


# A top-level mapping key in yq's block-style YAML output: at column 0, not a
# sequence item or a comment, followed by ':' and a space or the line's end.
# A plain key may itself hold ':' not followed by a space -- an ARN-like
# `arn:aws:x:1:` key, which yq prints unquoted -- so only ': ' or a ':' at
# the end of the line ends it.
TOP_KEY = re.compile(r'''^("(?:[^"\\]|\\.)*"|'[^']*'|[^\s#'"-](?:[^:\n]|:(?=[^ \n]))*):(?: |$)''', re.M)


def synth_value(shape, names, keys=()):
    """A synthetic value of this shape, or None if any part of it is unknown.

    names: where to look up a leaf, most specific first. keys: the keys other
    references read off this map; a map always gets at least two, because with
    one Atmos's joined multi-result and a single result are indistinguishable,
    and the verdict must not depend on how many keys other references happen
    to read.
    """
    # Values that pass the usual validations and keep features ON: 0 fails
    # checks like elasticache's `var.port > 0`, and false switches a feature
    # off so that its own checks never run.
    if shape == NUMBER:
        return 443 if any(n.endswith('port') for n in names) else 1
    if shape == BOOL:
        return True
    if shape == SCALAR:
        for n in names:
            got = synth(n)
            if isinstance(got, list):
                got = got[0] if got else None
            if got is not None:
                return got
        return None
    if shape[0] == 'list':
        if shape[1] == SCALAR and isinstance(synth(names[0]), list):
            # A list output named like a synthetic list keeps all of it: two
            # subnets, not one, for the reasons given at SYNTH.
            return list(synth(names[0]))
        v = synth_value(shape[1], names)
        return None if v is None else [v]
    if shape[0] == 'map':
        v = synth_value(shape[1], names)
        if v is None:
            return None
        ks = list(keys)
        for pad in ('synthetic_a', 'synthetic_b'):
            if len(ks) < 2:
                ks.append(pad)
        return {k: v for k in ks}
    if shape[0] == 'object':
        out = {}
        for attr, s in shape[1].items():
            v = synth_value(s, [attr, singular(attr)] + list(names))
            if v is None:
                return None
            out[attr] = v
        return out
    return None


class Resolver:
    """Everything needed to build a reference's value within one stack."""

    def __init__(self, stack, stacks_dir, components_dir):
        self.stack, self.stacks_dir, self.components_dir = stack, stacks_dir, components_dir
        self._stacks, self._keys = {}, {}

    def instances(self, stack):
        """(instances, None) or (None, why the stack cannot be read)."""
        # One `atmos describe stacks` per stack, written by the shell before the
        # loop. A stack named explicitly in a reference is described here, once.
        # A stack that is not there -- a typo in the 3-arg form, say -- is a
        # defect: Atmos would fail on it, so falling back would pass a broken
        # reference.
        if stack not in self._stacks:
            path = os.path.join(self.stacks_dir, stack + '.json')
            if not os.path.exists(path):
                with open(path + '.err', 'w') as err:
                    p = subprocess.run(['atmos', 'describe', 'stacks', '--process-functions=false',
                                        '--format', 'json', '-s', stack],
                                       stdout=subprocess.PIPE, stderr=err, text=True)
                if p.returncode != 0:
                    self._stacks[stack] = (None, 'atmos describe stacks -s %s failed' % stack)
                    return self._stacks[stack]
                with open(path, 'w') as fh:
                    fh.write(p.stdout)
            with open(path) as fh:
                d = json.load(fh)
            if stack not in d:
                self._stacks[stack] = (None, 'stack %s does not exist' % stack)
            else:
                self._stacks[stack] = (
                    ((d[stack] or {}).get('components') or {}).get('terraform') or {}, None)
        return self._stacks[stack]

    def component(self, name):
        return load_component(os.path.join(self.components_dir, name))

    def keys(self, stack, instance, output):
        # Every key ANY reference in the stack reads off this map output, so
        # `.certificate_arns.main_wildcard` finds main_wildcard in the synthetic
        # map instead of null.
        k = (stack, instance, output)
        if k not in self._keys:
            found = set()
            for c in (self.instances(stack)[0] or {}).values():
                for ref in refs_in(c.get('vars') or {}):
                    try:
                        r = parse_ref(ref)
                    except ParseError:
                        continue
                    if r and r[1] == instance and (r[2] or stack) == stack:
                        found |= accessed_keys(atmos_expr(r[3]), output)
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


def resolve_ref(s, var, resolver, warnings=None):
    """('shaped', value) | ('fallback', None) | ('defect', message).

    A shaped value may be None: Atmos hands the variable null, and so does
    this. Falling back to a name guess there is how `[.certificate_arns // {}
    | .[]]` would have passed. The one exception is a null that came from a
    map key the synthetic map lacks only because no reference read it in a
    form accessed_keys collects: that null is this script's, not Atmos's.

    warnings, when given, collects non-failing findings: a stale reference.
    """
    try:
        r = parse_ref(s)
    except ParseError as exc:
        return 'defect', '%s: Atmos cannot parse %r: %s' % (var, s, exc)
    if r is None:
        return 'fallback', None
    _, instance, stack, expr = r
    stack = stack or resolver.stack
    instances, why = resolver.instances(stack)
    if instances is None:
        return 'defect', '%s: %s (%s)' % (var, why, s)
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
    outputs = root_outputs(expr)
    if not outputs or not comp.readable or not comp.outputs:
        return 'fallback', None
    doc, maps, stale = {}, [], []

    def done(kind, value):
        # A stale reference is reported whenever the reference itself does
        # not fail -- a fallback included -- and never on top of a FAIL.
        if kind != 'defect' and warnings is not None:
            warnings.extend(stale)
        return kind, value

    for output in outputs:
        if output not in comp.outputs:
            if comp.declares_output(output):
                return done('fallback', None)   # declared, but the reader could not parse it
            # With real state a missing output reads as null from an S3
            # backend (an error from a static one). Without a '//' default
            # that null is the stack's defect.
            if not has_alternative(expr):
                return 'defect', '%s: %s (component %s) declares no output "%s", so it reads ' \
                    'null with real state (%s)' % (var, instance, comp_name, output, s)
            # With one, Atmos succeeds (both backends: the recorded rows in
            # ATMOS_CASES), so it is evaluated as Atmos would, the output
            # absent, and reported as stale without failing.
            stale.append('%s: %s (component %s) declares no output "%s", read in an expression '
                         'with a // default: the reference is stale (%s)' % (
                             var, instance, comp_name, output, s))
            continue
        shape = shape_of(comp.outputs[output], Ctx(comp))
        value = synth_value(shape, [output, singular(output), var],
                            resolver.keys(stack, instance, output)) if known(shape) else None
        if value is None:
            return done('fallback', None)
        doc[output] = value
        if shape[0] == 'map':
            maps.append(output)
    got, err = atmos_yq(expr, doc)
    if err is not None:
        return 'defect', '%s: yq cannot evaluate %r: %s' % (var, atmos_expr(expr), err)
    if has_null(got) and maps:
        # Would the result still hold that null if every map held every key the
        # expression could name? If not, the null is a key the builder did
        # not collect -- `.m as $x | $x.k` -- and passing it would be this
        # script's value. A key built at run time
        # (`.["a" + "b"]`) is named nowhere, and stays a limit.
        probe = dict(doc)
        for output in maps:
            leaf = next(iter(doc[output].values()))
            probe[output] = dict({k: leaf for k in candidate_keys(expr)}, **doc[output])
        # `.m | [.a, .x]` or `.m | {"a": .x}`: the null can sit inside the
        # result as well as be it.
        if atmos_yq(expr, probe)[0] != got:
            return done('fallback', None)
    return done('shaped', got)


def has_null(v):
    if v is None:
        return True
    if isinstance(v, dict):
        return any(has_null(x) for x in v.values())
    if isinstance(v, list):
        return any(has_null(x) for x in v)
    return False


SENTINEL = object()


class Builder:
    def __init__(self, resolver):
        self.resolver = resolver
        self.dropped, self.defects, self.warnings = [], [], []
        # !terraform references and every other function are counted apart:
        # the first is the number this file exists to drive up, the second
        # (!env, !store, ...) can only ever be guessed.
        self.counts = {'shaped': 0, 'fallback': 0, 'dropped': 0, 'other_guessed': 0,
                       'other_dropped': 0}

    def function(self, key, node):
        """(value, from_guess) for an Atmos function string, or (SENTINEL, _)."""
        is_tf = bool(TF_REF.match(node))
        if is_tf and self.resolver is not None:
            kind, got = resolve_ref(node, key, self.resolver, self.warnings)
            if kind == 'shaped':
                self.counts['shaped'] += 1
                return got, False
            if kind == 'defect':
                self.defects.append(got)
                return SENTINEL, False
        got = synth(key)
        if got is None:
            self.counts['dropped' if is_tf else 'other_dropped'] += 1
            self.dropped.append(key)
            return SENTINEL, False
        self.counts['fallback' if is_tf else 'other_guessed'] += 1
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
# Self-test, run by the shell before any pair. Built against the REAL acm,
# vpc and kms components, so a change there that this reader cannot follow
# fails here rather than silently falling back.
# ---------------------------------------------------------------------------
# Each row was run through real Atmos 1.229.0 (`atmos describe component`, a
# static remote_state_backend holding ATMOS_DATA) and the result recorded
# here, so atmos_yq is checked against Atmos itself, not against this file's
# idea of it.
#
# The rows after the first eleven were recorded the same way against a LOCAL
# backend (a terraform.tfstate holding ATMOS_DATA): GetTerraformBackendVariable,
# the S3 code path, where an output the state lacks reads as null. Against the
# static backend `.no_such_output` is an error instead, and `.no_such_output //
# "x"` is "x" there too -- so a '//' default wins on both.
ATMOS_DATA = {'certificate_arns': {'main_wildcard': 'arn:a', 'api': 'arn:b'},
              'one_key': {'only': 'arn:c'}, 'vpc_id': 'vpc-1', 'subnets': ['s1', 's2'],
              'nothing': None, 'arn_keyed': {'arn:aws:acm:eu-west-2:1:certificate/x': 'a'},
              'obj': {'a': 'id-1'}}
ATMOS_CASES = [
    ('[.certificate_arns // {} | .[]]', 'null null'),
    ('.certificate_arns // {} | [.[]]', ['arn:a', 'arn:b']),
    ('[.one_key // {} | .[]]', None),
    ('.certificate_arns // {}', {'api': 'arn:b', 'main_wildcard': 'arn:a'}),
    ('.certificate_arns // {} | keys', ['main_wildcard', 'api']),
    ('.vpc_id | "s3://" + . + "/data/"', 's3://vpc-1/data/'),
    ('vpc_id', 'vpc-1'),
    ('.subnets[0]', 's1'),
    ('.subnets[]', 's1 s2'),
    ('.nothing', None),
    ('.certificate_arns.main_wildcard', 'arn:a'),
    # L3': key reads through a pipe or a select().
    ('.certificate_arns | .main_wildcard', 'arn:a'),
    ('.certificate_arns // {} | .api', 'arn:b'),
    ('.certificate_arns | ."api"', 'arn:b'),
    ('.certificate_arns | .["api"]', 'arn:b'),
    ('.certificate_arns | to_entries | map(select(.key == "api")) | .[0].value', 'arn:b'),
    ('.certificate_arns | with_entries(select(.key == "api"))', {'api': 'arn:b'}),
    ('.certificate_arns | .missing', None),
    ('.certificate_arns as $x | $x.api', 'arn:b'),
    ('.obj.b', None),
    # L5': an output the state does not hold.
    ('.no_such_output', None),
    ('.no_such_output // "x"', 'x'),
    ('.vpc_id // .no_such_output', 'vpc-1'),
    ('.no_such_output | .x // "d"', 'd'),
    # A '//' inside a string is no default: Atmos hands the variable a
    # broken URI, which the sweep must FAIL, not call stale.
    ('.no_such_output | "s3://" + . + "/"', 's3:///'),
    ('"x//y" + .no_such_output', None),
    # A key missing inside the result, not as the result.
    ('.certificate_arns | [.main_wildcard, .missing]', ['arn:a', None]),
    ('.certificate_arns | {"a": .missing}', {'a': None}),
    ('.arn_keyed', {'arn:aws:acm:eu-west-2:1:certificate/x': 'a'}),
]
# Also recorded on the local backend, and rejected by real Atmos:
#   `.arn_keyed, .arn_keyed` -- mapping key "arn:aws:acm:..." already defined;
#   `.no_such_output // "x" | ][` -- a yq parse error, default or not.
ATMOS_REJECTS = ['.arn_keyed, .arn_keyed', '.no_such_output // "x" | ][']


# The component the M1' and null-passthrough checks read: variable types,
# locals and a local module, none of which the real components have in this
# combination.
FAKE_TF = '''
variable "m" {
  type = map(object({ name = list(string), port = number }))
}
variable "l" {
  type = list(object({ id = string }))
}
variable "untyped" {}
locals {
  objs  = { a = { name = "x" }, b = { name = "y" } }
  mixed = { a = "x", b = 1 }
  zones = merge(aws_route53_zone.a, aws_route53_zone.b)
  k8s   = kubernetes_service.s
}
module "here" {
  source = "./"
}
output "pairs" {
  value = { a = { id = "x" } }
}
output "obj" {
  value = { vpc_id = aws_x.y.id }
}
output "unreadable" {
  value = some_function_the_reader_does_not_know(aws_x.y.id)
}
'''


def self_test(components_dir, tmp):
    failures = []

    def check(what, got, want):
        if got != want:
            failures.append('%s: got %r, want %r' % (what, got, want))

    for expr, want in ATMOS_CASES:
        got, err = atmos_yq(expr, ATMOS_DATA)
        # Real Atmos sorted the map's keys; order within a list is not what
        # any of these rows is about.
        if isinstance(got, list) and isinstance(want, list):
            got, want = sorted(got, key=repr), sorted(want, key=repr)
        check('atmos_yq %s' % expr, (got, err), (want, None))
    check('atmos_yq merges distinct map results (real Atmos: the union)',
          atmos_yq('.one_key, .certificate_arns', ATMOS_DATA),
          ({'api': 'arn:b', 'main_wildcard': 'arn:a', 'only': 'arn:c'}, None))
    for bad in ['{"a": .vpc_id}', '.vpc_id | ][', '.certificate_arns | to_entries | .[]',
                '.one_key, .one_key'] + ATMOS_REJECTS:
        check('atmos_yq rejects %s' % bad, atmos_yq(bad, ATMOS_DATA)[1] is not None, True)

    stack = 'selftest'
    stacks = {stack: {'components': {'terraform': {
        'acm/main': {'component': 'acm', 'vars': {
            'x': '!terraform.state acm/main .certificate_arns.main_wildcard',
            # L3': keys read through a pipe or a select() are collected too.
            'y': '!terraform.state acm/main .certificate_arns // {} | .piped_key',
            'z': ['!terraform.state acm/main .certificate_arns | to_entries | '
                  'map(select(.key == "selected_key")) | .[0].value']}},
        'vpc/main': {'component': 'vpc', 'vars': {}},
        'kms/main': {'component': 'kms', 'vars': {}},
        # A component that is not in components/terraform: an absolute
        # component path wins the os.path.join in Resolver.component.
        'fake/main': {'component': os.path.join(tmp, 'fake'), 'vars': {}},
    }}}}
    os.makedirs(os.path.join(tmp, 'fake'), exist_ok=True)
    with open(os.path.join(tmp, 'fake', 'main.tf'), 'w') as fh:
        fh.write(FAKE_TF)
    with open(os.path.join(tmp, stack + '.json'), 'w') as fh:
        json.dump(stacks, fh)
    # What `atmos describe stacks -s <unknown>` prints: {} and exit 0. Seeded,
    # so the self-test never shells out to atmos.
    with open(os.path.join(tmp, 'no-such-stack.json'), 'w') as fh:
        fh.write('{}')
    res = Resolver(stack, tmp, components_dir)
    acm, vpc, kms = res.component('acm'), res.component('vpc'), res.component('kms')
    check('acm certificate_arns shape', shape_of(acm.outputs.get('certificate_arns', ''), Ctx(acm)),
          MAP(SCALAR))
    check('vpc vpc_id shape', shape_of(vpc.outputs.get('vpc_id', ''), Ctx(vpc)), SCALAR)
    check('vpc private_subnet_ids shape',
          shape_of(vpc.outputs.get('private_subnet_ids', ''), Ctx(vpc)), LIST(SCALAR))
    check('kms key_arn through its local module',
          shape_of(kms.outputs.get('key_arn', ''), Ctx(kms)), SCALAR)
    for expr, want in [
        ('{ for k, v in aws_x.y : k => v.arn }', MAP(SCALAR)),
        ('{ for k, v in aws_x.y : k => v.vpc_config }', MAP(UNKNOWN)),
        ('{ for k, v in aws_x.y : k => v.certificate_authority[0].data }', MAP(SCALAR)),
        ('{ requester = [for r in aws_x.y : r.id], accepter = [] }',
         OBJ({'requester': LIST(SCALAR), 'accepter': LIST(UNKNOWN)})),
        ('{ a = aws_x.y.id, b = "s" }', OBJ({'a': SCALAR, 'b': SCALAR})),
        ('[for c in var.a : aws_x.y[c].id]', LIST(SCALAR)),
        ('aws_x.y[*].arn', LIST(SCALAR)), ('one(aws_x.y[*].arn)', SCALAR),
        ('aws_x.y[*].arn[0]', UNKNOWN),
        ('merge({ for k, v in aws_x.y : k => v.key_name }, var.g ? { "g" = aws_k.g[0].key_name } : {})',
         MAP(SCALAR)),
        ('var.enabled ? aws_x.y[0].id : null', SCALAR),
        ('try(values({ for k, v in aws_x.y : k => v.id }), [])', LIST(SCALAR)),
        # M1': a bare name is no resource, so the allowlist does not apply.
        ('try(values({ for k, v in a : k => v.id }), [])', LIST(UNKNOWN)),
        ('module.nowhere.key_arn', UNKNOWN), ('aws_x.y.tags', UNKNOWN), ('aws_x.y.id', SCALAR),
        ('aws_x.y.certificate_authority', UNKNOWN), ('aws_x.y.identity', UNKNOWN),
        ('aws_x.y.data', UNKNOWN), ('aws_x.y.status', UNKNOWN), ('element_count(a)', UNKNOWN),
        ('{ p = 443, e = true, n = aws_x.y.port }', OBJ({'p': NUMBER, 'e': BOOL, 'n': NUMBER})),
        ('kubernetes_service.s.spec[0].port', UNKNOWN), ('kubernetes_x.y.enabled', UNKNOWN),
        ('data.aws_x.y.enabled', BOOL), ('aws_x.y[*].port', LIST(NUMBER)),
        ('{ for k, s in kubernetes_service.all : k => s.spec[0].port }', MAP(UNKNOWN)),
        ('var.x', UNKNOWN),
    ]:
        check('shape of %s' % expr, shape_of(expr, Ctx(acm)), want)
    check('number and bool leaves', synth_value(OBJ({'n': NUMBER, 'e': BOOL, 'id': SCALAR}), ['vpc_id']),
          {'n': 1, 'e': True, 'id': 'vpc-0123456789abcdef0'})
    check('a port is 443', (synth_value(NUMBER, ['db_port']), synth_value(OBJ({'port': NUMBER}), ['x'])),
          (443, {'port': 443}))
    for expr, want in [
        ('one(aws_eks_cluster.default[*].certificate_authority[0].data)', SCALAR),
        ('one(aws_eks_cluster.default[*].identity[0].oidc[0].issuer)', SCALAR),
        ('aws_eks_cluster.default[*].certificate_authority[0].data', LIST(SCALAR)),
        ('aws_x.y[*].data', LIST(UNKNOWN)),
        ('aws_x.y[*].blk.id', UNKNOWN),
        ('aws_x.y[*].blk[0]', UNKNOWN),
        ('kubernetes_service.s[*].spec[0].port', LIST(UNKNOWN)),
        # The legacy splat carries attributes only: [0] after `.*` indexes
        # the resulting list, so this is no list of certificate data.
        ('aws_x.y.*.arn', LIST(SCALAR)), ('aws_x.y.*', LIST(UNKNOWN)),
        ('aws_x.y.*.certificate_authority[0].data', UNKNOWN),
        ('aws_x.y.*.blk[0].id', UNKNOWN),
    ]:
        check('shape of %s' % expr, shape_of(expr, Ctx(acm)), want)
    # M1': a for-loop variable is an element of its collection.
    fake = res.component(os.path.join(tmp, 'fake'))
    for expr, want in [
        # var.m is map(object({name = list(string), ...})): was MAP(SCALAR).
        ('{ for k, v in var.m : k => v.name }', MAP(LIST(SCALAR))),
        ('{ for k, v in var.m : k => v.port }', MAP(NUMBER)),
        ('{ for k, v in var.m : k => v.nope }', MAP(UNKNOWN)),
        ('{ for k, v in var.m : k => [for n in v.name : n] }', MAP(LIST(SCALAR))),
        ('[for v in var.l : v.id]', LIST(SCALAR)),
        ('[for v in var.l : v[0]]', LIST(UNKNOWN)),
        ('{ for k, v in var.untyped : k => v.name }', MAP(UNKNOWN)),
        ('{ for k, v in local.objs : k => v.name }', MAP(SCALAR)),
        ('{ for k, v in local.mixed : k => v }', MAP(UNKNOWN)),
        ('{ for k, v in module.here.pairs : k => v.id }', MAP(SCALAR)),
        # dns's managed_zones: a local merging two aws_* resources.
        ('{ for k, z in local.zones : k => z.zone_id }', MAP(SCALAR)),
        ('{ for k, v in aws_x.y : k => v.port }', MAP(NUMBER)),
        ('{ for k, v in aws_x.y : k => v.enabled }', MAP(BOOL)),
        ('[for v in data.aws_x.y : v.enabled]', LIST(BOOL)),
        ('{ for k, v in kubernetes_service.s : k => v.id }', MAP(UNKNOWN)),
        ('{ for k, v in local.k8s : k => v.name }', MAP(UNKNOWN)),
        ('{ for k, v in merge(aws_x.a, kubernetes_x.b) : k => v.id }', MAP(UNKNOWN)),
    ]:
        check('shape of %s' % expr, shape_of(expr, Ctx(fake)), want)
    check('Cloud Posse eks leaves', (
        synth_value(SCALAR, ['eks_cluster_identity_oidc_issuer']),
        synth_value(SCALAR, ['eks_cluster_endpoint']),
        synth_value(SCALAR, ['eks_cluster_certificate_authority_data']),
    ), ('https://oidc.eks.eu-west-2.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E',
        'https://' + EKS_HOST, CA_CERT or None))
    check('indented output block', [k for k, _ in blocks('  output "x" {\n  value = 1\n}\n', 'output')],
          ['x'])

    # #166. Passing the map as-is keeps it a map, which monitoring's
    # list(string) rejects. The first fix, `[.certificate_arns // {} | .[]]`,
    # is `.[...]` to Atmos -- an index -- and comes back as the STRING
    # "null null", which list(string) rejects too. Only `... | [.[]]` is a list.
    def ref(expr, var='certificate_arns'):
        return resolve_ref('!terraform.state acm/main ' + expr, var, res)

    kind, bug = ref('.certificate_arns // {}')
    check('#166 bug form is an object', (kind, isinstance(bug, dict)), ('shaped', True))
    kind, broken = ref('[.certificate_arns // {} | .[]]')
    check('#166 bracket form is a string, not a list', (kind, isinstance(broken, str)), ('shaped', True))
    kind, fixed = ref('.certificate_arns // {} | [.[]]')
    check('#166 fixed form is a list of strings',
          (kind, isinstance(fixed, list) and len(fixed) >= 2 and all(isinstance(x, str) for x in fixed)),
          ('shaped', True))
    check('map key accessor', ref('.certificate_arns.main_wildcard', 'certificate_arn')[1],
          'arn:aws:acm:eu-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012')
    # L3'. Keys read through a pipe or a select() anywhere in the stack are
    # in the synthetic map, so those reads get a value, not null.
    check('keys collected', res.keys(stack, 'acm/main', 'certificate_arns'),
          ['main_wildcard', 'piped_key', 'selected_key'])
    check('pipe key', ref('.certificate_arns // {} | .piped_key', 'certificate_arn')[1],
          'arn:aws:acm:eu-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012')
    check('select key', ref('.certificate_arns | to_entries | map(select(.key == "selected_key"))'
                            ' | .[0].value', 'certificate_arn')[0], 'shaped')
    for e, want in [('.m.k', {'k'}), ('.m["k"]', {'k'}), ('.m | .k', {'k'}), ('.m // {} | .k', {'k'}),
                    ('.m | ."k"', {'k'}), ('.m | .["k"]', {'k'}), ('.m // null | .k', {'k'}),
                    ('.m | with_entries(select(.key == "k"))', {'k'}),
                    ('.m | to_entries | map(select("k" == .key))', {'k'}),
                    ('.other | select(.key == "k")', set()), ('.mm | .k', set())]:
        check('accessed_keys %s' % e, accessed_keys(e, 'm'), want)
    # A null that only an uncollected key produced falls back, rather than
    # hand the variable a null Atmos would not.
    check('uncollected key falls back', ref('.certificate_arns.no_such_key'), ('fallback', None))
    check('uncollected $var key falls back', ref('.certificate_arns as $x | $x.api'), ('fallback', None))
    # A null INSIDE the result from an uncollected key falls back too.
    check('uncollected key in a list falls back', ref('.certificate_arns | [.main_wildcard, .api]'),
          ('fallback', None))
    check('uncollected key in an object falls back', ref('.certificate_arns | {"a": .api}'),
          ('fallback', None))
    # A genuine null still passes through: an object attribute that the
    # output does not have.
    check('null passes through, no fallback',
          resolve_ref('!terraform.state fake/main .obj.b', 'x', res), ('shaped', None))

    def vref(args, var='x'):
        return resolve_ref('!terraform.state ' + args, var, res)

    check('s3:// concatenation', vref('vpc/main .vpc_id | "s3://" + . + "/data/"'),
          ('shaped', 's3://vpc-0123456789abcdef0/data/'))
    check('quoted expression', vref('vpc/main \'.vpc_id | "s3://" + .\''),
          ('shaped', 's3://vpc-0123456789abcdef0'))
    check('[0] index', vref('vpc/main .private_subnet_ids[0]', 'subnet_id'),
          ('shaped', 'subnet-0123456789abcdef0'))
    check('several results are joined', vref('vpc/main .private_subnet_ids[]'),
          ('shaped', 'subnet-0123456789abcdef0 subnet-0123456789abcdef1'))
    check('short form', vref('vpc/main vpc_id'), ('shaped', 'vpc-0123456789abcdef0'))
    check('3-arg form, this stack', vref('vpc/main selftest .vpc_id'), ('shaped', 'vpc-0123456789abcdef0'))
    for what, args in [
        ('missing instance', 'nope/main .x'),
        ('missing output', 'vpc/main .no_such_output'),
        ('missing output, no default', 'vpc/main .no_such_output | .x'),
        ('missing output behind // but yq rejects it', 'vpc/main .no_such_output // "x" | ]['),
        # A '//' inside a string is no default: the repo's own s3:// idiom.
        ('missing output, // only in a string', 'vpc/main .no_such_output | "s3://" + . + "/"'),
        ('missing output, // only in a string before it', 'vpc/main "x//y" + .no_such_output'),
        ('yq error', 'vpc/main .vpc_id | ]['),
        ('parenthesised expression is an Atmos parse error', 'vpc/main (.vpc_id // "x")'),
        ('object expression gets the leading dot', 'vpc/main {"a": .vpc_id}'),
        ('unknown stack', 'vpc/main no-such-stack .vpc_id'),
        ('unterminated quote', 'vpc/main ".vpc_id'),
    ]:
        check(what, vref(args)[0], 'defect')
    # L5'. Behind a '//' Atmos succeeds with the default (ATMOS_CASES), so
    # the reference is evaluated, and reported as stale without failing.
    for args, want in [
        ('vpc/main .no_such_output // "x"', 'x'),
        ('vpc/main .vpc_id // .no_such_output', 'vpc-0123456789abcdef0'),
        ('vpc/main .no_such_output | .x // "d"', 'd'),
    ]:
        warned = []
        got = resolve_ref('!terraform.state ' + args, 'x', res, warned)
        check('stale %s' % args, (got, len(warned), all('stale' in w for w in warned)),
              (('shaped', want), 1, True))
    for args in ['vpc/main .no_such_output', 'vpc/main .no_such_output // "x" | ][',
                 'vpc/main .no_such_output | "s3://" + . + "/"']:
        warned = []
        resolve_ref('!terraform.state ' + args, 'x', res, warned)
        check('a FAIL is not also a warning: %s' % args, warned, [])
    # A stale reference stays reported when another output in the same
    # expression falls back: fake's `unreadable` has a shape the reader
    # cannot tell.
    warned = []
    got = resolve_ref('!terraform.state fake/main .no_such_output // .unreadable', 'x', res, warned)
    check('stale kept when a later output falls back', (got, len(warned)), (('fallback', None), 1))
    check('has_alternative', [has_alternative(e) for e in
                              ['.a // "x"', '.a | "s3://" + .', '"x//y" + .a', '"a\\"//" + .b', '.a //= 1']],
          [True, False, False, False, False])
    top, b = build({'vars': {'x': '!terraform.state vpc/main .no_such_output // "x"'}},
                   stack, tmp, components_dir)
    check('stale reference is a warning, not a defect', (top, b.defects, len(b.warnings)),
          ({'x': 'x'}, [], 1))
    check('parse: 3-arg with pipes', parse_ref('!terraform.state vpc other .a | "x" + .'),
          ('state', 'vpc', 'other', '.a | "x" + .'))
    check('root outputs', root_outputs('.a // .b | .c + "//#" + .d'), ['a', 'b'])
    check('root outputs in brackets', root_outputs('[.a // {} | .[]]'), ['a'])

    # Only a name-guessed list is spliced into its parent list; an
    # output-shaped one is inserted as-is, as Atmos would.
    top, b = build({'vars': {
        'subnet_ids': ['!terraform.state vpc/main .private_subnet_ids'],
    }}, stack, tmp, components_dir)
    check('shaped list is not spliced', top['subnet_ids'],
          [['subnet-0123456789abcdef0', 'subnet-0123456789abcdef1']])
    top, b = build({'vars': {'subnet_ids': ['!env X'], 'z': '!env Y'}}, None, None, None)
    check('guessed list is spliced', top['subnet_ids'],
          ['subnet-0123456789abcdef0', 'subnet-0123456789abcdef1'])
    check('!env is not counted as a !terraform reference',
          (b.counts['fallback'], b.counts['other_guessed'], b.counts['other_dropped']), (0, 1, 1))
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
    # Line 3: reference defects -- a stack, instance or output that is not
    # there, an argument Atmos cannot parse, an expression yq rejects -- joined
    # by TAB.
    #
    # Line 4: !terraform references output-shaped, name-guessed, dropped; then
    # other functions guessed, dropped.
    #
    # Line 5: warnings, joined by TAB: references that work but are stale --
    # an output the target does not declare, behind a '//' default that
    # therefore always applies. Reported, never failing.
    c = b.counts
    print(d.get('component') or (d.get('metadata') or {}).get('component') or '')
    print(','.join(sorted(set(b.dropped))))
    print('\t'.join(m.replace('\t', ' ').replace('\n', ' ') for m in b.defects))
    print('%d %d %d %d %d' % (c['shaped'], c['fallback'], c['dropped'], c['other_guessed'],
                              c['other_dropped']))
    print('\t'.join(m.replace('\t', ' ').replace('\n', ' ') for m in b.warnings))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
