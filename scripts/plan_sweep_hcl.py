"""plan-sweep's HCL reader: the SHAPE of a terraform output, from source text.

Used by plan_sweep_varfile.py to decide whether a referenced output is a map,
a list, an object or a scalar, and so what its synthetic value must look like.
The CI image has python3 and no HCL library, so this reads the *.tf text:
strings, interpolations, heredocs and comments are skipped properly, and
anything it cannot read is UNKNOWN -- never a guess. Its checks live in
plan_sweep_varfile.py's self-test, which runs before every sweep.
"""
import os
import re

# ---------------------------------------------------------------------------
# Shapes. Tuples, so they compare by value:
#   SCALAR, NUMBER, BOOL       -- a string leaf, and the two leaves that are
#                                 not strings: an object with a numeric
#                                 attribute given a string would be a false FAIL
#   UNKNOWN, NULL              -- "cannot tell", and HCL's null
#   ('list', elem)             -- list, set or tuple
#   ('map', elem)              -- keys decided at apply time ({ for ... })
#   ('object', {attr: shape})  -- keys written in the source
# An element shape that is UNKNOWN makes the whole value unsynthesizable, and
# the reference falls back: a map of strings standing in for a map of lists is
# a guess, and a guess here is exactly what this file exists to replace.
# ---------------------------------------------------------------------------
SCALAR, UNKNOWN, NULL = ('scalar',), ('unknown',), ('null',)
NUMBER, BOOL = ('scalar', 'number'), ('scalar', 'bool')


def LIST(e):
    return ('list', e)


def MAP(e):
    return ('map', e)


def OBJ(d):
    return ('object', d)


def known(shape):
    if shape in (UNKNOWN, NULL):
        return False
    if shape[0] in ('list', 'map'):
        return known(shape[1])
    if shape[0] == 'object':
        return all(known(s) for s in shape[1].values())
    return True


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
    """Yield (label, body) for every top-level `kind "label" {` (or `locals {`) block.

    Indented blocks count: the file-level position is what matters, and a
    reformatted or hand-indented outputs.tf must not lose its outputs -- that
    would report a declared output as missing.
    """
    i = 0
    while i < len(s):
        j = skip_trivia(s, i)
        if j != i:
            i = j
            continue
        if s[i] == '{':
            i = skip_balanced(s, i)
            continue
        line_start = s.rfind('\n', 0, i) + 1
        if s.startswith(kind, i) and not s[line_start:i].strip():
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
    """Outputs, variable types, locals and local modules of one terraform directory."""

    def __init__(self, path):
        self.path = path
        self.outputs, self.var_types, self.locals, self.modules = {}, {}, {}, {}
        self.text = ''
        self.readable = False
        try:
            names = sorted(f for f in os.listdir(path) if f.endswith('.tf'))
        except OSError:
            return
        for name in names:
            with open(os.path.join(path, name), encoding='utf-8') as fh:
                s = fh.read()
            self.readable = True
            self.text += s + '\n'
            for label, body in blocks(s, 'output'):
                self.outputs.setdefault(label, attributes(body).get('value', ''))
            for label, body in blocks(s, 'variable'):
                self.var_types.setdefault(label, attributes(body).get('type', ''))
            for _, body in blocks(s, 'locals'):
                for k, v in attributes(body).items():
                    self.locals.setdefault(k, v)
            for label, body in blocks(s, 'module'):
                self.modules.setdefault(label, attributes(body).get('source', ''))

    def declares_output(self, name):
        # A raw-text check behind the parser: a declared output the parser
        # missed must never be reported as a missing one.
        return re.search(r'^\s*output\s+"' + re.escape(name) + r'"', self.text, re.M) is not None


_COMPONENTS = {}


def load_component(path):
    path = os.path.normpath(path)
    if path not in _COMPONENTS:
        _COMPONENTS[path] = Component(path)
    return _COMPONENTS[path]


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


def top_level_word(expr, word):
    """Index of the first top-level occurrence of a keyword, or -1."""
    for m in re.finditer(r'\b' + word + r'\b', expr):
        if m.start() in top_level(expr[:m.start() + 1], expr[m.start()]):
            return m.start()
    return -1


def whole(expr, i):
    """True when the bracket opening at i closes at the very end of expr."""
    return skip_balanced(expr, i) == len(expr)


def split_top(inner, seps):
    cuts = top_level(inner, seps)
    parts, prev = [], 0
    for c in cuts + [len(inner)]:
        parts.append(inner[prev:c].strip())
        prev = c + 1
    return [p for p in parts if p]


# Attributes that are a single string, number or bool on every AWS resource
# that has them. Anything else is UNKNOWN: certificate_authority, vpc_config,
# identity, access_logs and root_block_device are all list BLOCKS, and calling
# one a scalar because its name does not end in 's' manufactures a type error.
SCALAR_ATTRS = {
    'id', 'arn', 'name', 'name_prefix', 'endpoint', 'dns_name', 'zone_id', 'address', 'port',
    'fqdn', 'cidr_block', 'invoke_arn', 'qualified_arn', 'execution_arn', 'function_name',
    'domain_name', 'regional_domain_name', 'regional_zone_id', 'target_domain_name',
    'hosted_zone_id', 'key_id', 'key_name', 'version', 'stage_name', 'root_resource_id',
    'replication_group_id', 'primary_endpoint_address', 'reader_endpoint_address',
    'configuration_endpoint_address', 'cluster_security_group_id', 'bucket',
    'bucket_domain_name', 'bucket_regional_domain_name', 'invoke_url', 'url', 'identifier',
    'secret_arn', 'owner_id', 'accept_status', 'db_name', 'username',
    'instance_id', 'function_url', 'queue_url', 'table_name', 'stream_arn', 'role_arn',
}
FN_CALL = re.compile(r'^([a-z][a-z0-9_]*)\(')
IDENT = r'[A-Za-z_][A-Za-z0-9_-]*'
INDEX = r'(?:\[[^\[\]]*\])'
# aws_vpc.main.id, aws_x.y[0].arn, aws_x.y[each.key].arn,
# aws_eks_cluster.c.certificate_authority[0].data, data.aws_x.y.id
RESOURCE_ATTR = re.compile(
    r'^(?:data\.)?[a-z][a-z0-9_]*\.' + IDENT + INDEX + r'?(?:\.' + IDENT + r'\[0\])*\.(' + IDENT + r')$')
SPLAT = re.compile(r'^(.*?)(?:\[\*\]|\.\*)(?:\.(' + IDENT + r'))?$')
STRING_FNS = {'format', 'join', 'jsonencode', 'tostring', 'lower', 'upper', 'replace',
              'trimprefix', 'trimsuffix', 'trimspace', 'substr', 'base64encode', 'md5',
              'sha256', 'title'}
NUMBER_FNS = {'tonumber', 'length', 'abs', 'max', 'min', 'floor', 'ceil'}
NUMBER_ATTRS = {'port'}
BOOL_ATTRS = {'enabled'}


def attr_shape(attr, indexed=False):
    # `data` is a string only as a nested block's attribute --
    # certificate_authority[0].data -- and something else anywhere else.
    if attr in NUMBER_ATTRS:
        return NUMBER
    if attr in BOOL_ATTRS:
        return BOOL
    if attr in SCALAR_ATTRS or (attr == 'data' and indexed):
        return SCALAR
    return UNKNOWN


def type_shape(t):
    """Shape of a variable's declared type expression."""
    t = t.strip()
    if t in ('string', 'number', 'bool'):
        return {'string': SCALAR, 'number': NUMBER, 'bool': BOOL}[t]
    m = re.match(r'^(list|set|map|tuple|object|optional)\s*\(', t)
    if not m or not whole(t, m.end() - 1):
        return UNKNOWN
    inner = t[m.end():-1].strip()
    kind = m.group(1)
    if kind == 'optional':
        return type_shape(split_top(inner, ',')[0]) if inner else UNKNOWN
    if kind in ('list', 'set'):
        return LIST(type_shape(inner))
    if kind == 'map':
        return MAP(type_shape(inner))
    if kind == 'tuple':
        items = split_top(inner[1:-1], ',\n') if inner.startswith('[') else []
        return LIST(type_shape(items[0])) if items else UNKNOWN
    if inner.startswith('{') and whole(inner, 0):
        items = object_items(inner[1:-1])
        if items is None:
            return UNKNOWN
        return OBJ({k: type_shape(v) for k, v in items if k is not None})
    return UNKNOWN


def object_items(inner):
    """[(key or None-if-computed, value expression)] of an object literal body."""
    items = []
    for part in split_top(inner, ',\n'):
        part = re.sub(r'^\s*(#|//).*$', '', part, flags=re.M).strip()
        if not part:
            continue
        m = re.match(r'^(?:"([^"]+)"|(' + IDENT + r'))\s*(?:=(?![=>])|:)\s*(.+)$', part, re.S)
        if m:
            items.append((m.group(1) or m.group(2), m.group(3)))
            continue
        m = re.match(r'^(\(.*?\))\s*(?:=(?![=>])|:)\s*(.+)$', part, re.S)
        if m:
            items.append((None, m.group(2)))
            continue
        return None
    return items


def merge_shapes(shapes):
    """merge(): objects union, a map wins, empty literals drop out."""
    rest = [s for s in shapes if s != MAP(UNKNOWN)]    # `{}` adds nothing
    maps = [s for s in rest if s[0] == 'map']
    if maps:
        return maps[0]
    if rest and all(s[0] == 'object' for s in rest):
        merged = {}
        for o in rest:
            merged.update(o[1])
        return OBJ(merged)
    return UNKNOWN


def elem(shape):
    return shape[1] if shape[0] in ('list', 'map') else UNKNOWN


class Ctx:
    """What an expression can refer to: its component, and any `for` iterators."""

    def __init__(self, comp, key_vars=(), value_vars=(), depth=0):
        self.comp, self.key_vars, self.value_vars, self.depth = comp, key_vars, value_vars, depth

    def deeper(self, key_vars=(), value_vars=()):
        return Ctx(self.comp, self.key_vars + tuple(key_vars),
                   self.value_vars + tuple(value_vars), self.depth + 1)


def for_parts(body):
    """(key_vars, value_vars, element expr, grouped) of `for k, v in coll : ...`."""
    m = re.match(r'^\s*for\s+(' + IDENT + r')(?:\s*,\s*(' + IDENT + r'))?\s+in\s', body)
    colon = top_level(body, ':')
    if not m or not colon:
        return None
    first, second = m.group(1), m.group(2)
    keys, values = ((first,), (second,)) if second else ((), (first,))
    rest = body[colon[0] + 1:]
    cut = top_level_word(rest, 'if')
    if cut >= 0:
        rest = rest[:cut]
    rest = rest.strip()
    grouped = rest.endswith('...')
    return keys, values, (rest[:-3] if grouped else rest).strip(), grouped


def shape_of(expr, ctx):
    """The shape of an HCL expression; UNKNOWN whenever it cannot be read."""
    e = expr.strip()
    if not e or ctx.depth > 6:
        return UNKNOWN
    while e.startswith('(') and whole(e, 0):
        e = e[1:-1].strip()
    q = top_level(e, '?')
    if q:
        colons = top_level(e[q[0] + 1:], ':')
        if not colons:
            return UNKNOWN
        a = shape_of(e[q[0] + 1:q[0] + 1 + colons[0]], ctx.deeper())
        b = shape_of(e[q[0] + 2 + colons[0]:], ctx.deeper())
        # A branch that is null or an empty literal says nothing about the
        # other; take whichever branch is fully known.
        return a if known(a) else b if known(b) else a if a != NULL else b
    if e == 'null':
        return NULL
    if e[0] == '{' and whole(e, 0):
        inner = e[1:-1].strip()
        if not inner:
            return MAP(UNKNOWN)
        f = for_parts(inner)
        if f:
            keys, values, body, grouped = f
            arrow = [i for i in top_level(body, '=') if body.startswith('=>', i)]
            if not arrow:
                return UNKNOWN
            v = shape_of(body[arrow[0] + 2:], ctx.deeper(keys, values))
            return MAP(LIST(v) if grouped else v)
        items = object_items(inner)
        if items is None:
            return UNKNOWN
        if any(k is None for k, _ in items):
            vs = [shape_of(v, ctx.deeper()) for _, v in items]
            return MAP(vs[0]) if vs and all(s == vs[0] for s in vs) else UNKNOWN
        return OBJ({k: shape_of(v, ctx.deeper()) for k, v in items})
    if e[0] == '[' and whole(e, 0):
        inner = e[1:-1].strip()
        f = for_parts(inner) if inner else None
        if f:
            keys, values, body, _ = f
            return LIST(shape_of(body, ctx.deeper(keys, values)))
        items = split_top(inner, ',\n')
        return LIST(shape_of(items[0], ctx.deeper()) if items else UNKNOWN)
    if e[0] == '"' and skip_string(e, 0) == len(e):
        return SCALAR
    if re.match(r'^-?[0-9][0-9.]*$', e):
        return NUMBER
    if e in ('true', 'false'):
        return BOOL
    m = FN_CALL.match(e)
    if m and whole(e, m.end() - 1):
        return fn_shape(m.group(1), split_top(e[m.end():-1], ','), ctx)
    if top_level(e, '+*/%<>=!&|') or re.search(r'\s-\s', e):
        return UNKNOWN
    return ref_shape(e, ctx)


def fn_shape(fn, args, ctx):
    a = [shape_of(x, ctx.deeper()) for x in args]
    if fn in STRING_FNS:
        return SCALAR
    if fn in NUMBER_FNS:
        return NUMBER
    if fn == 'tobool':
        return BOOL
    if fn in ('keys', 'split', 'range'):
        return LIST(SCALAR)
    if fn == 'values':
        return LIST(elem(a[0])) if a and a[0][0] == 'map' else UNKNOWN
    if fn in ('tolist', 'toset', 'compact', 'distinct', 'sort', 'reverse', 'slice', 'concat',
              'setunion', 'setintersection', 'setsubtract', 'coalescelist'):
        return a[0] if a and a[0][0] == 'list' else UNKNOWN
    if fn == 'flatten':
        if a and a[0][0] == 'list':
            inner = elem(a[0])
            return inner if inner[0] == 'list' else a[0] if inner[0] == 'scalar' else UNKNOWN
        return UNKNOWN
    if fn == 'one':
        return elem(a[0]) if a and a[0][0] == 'list' else UNKNOWN
    if fn in ('element', 'lookup'):
        return elem(a[0]) if a else UNKNOWN
    if fn == 'merge':
        return merge_shapes(a) if a else UNKNOWN
    if fn == 'tomap':
        return a[0] if a and a[0][0] == 'map' else UNKNOWN
    if fn == 'zipmap':
        return MAP(elem(a[1])) if len(a) == 2 else UNKNOWN
    if fn in ('try', 'coalesce'):
        return a[0] if a else UNKNOWN
    return UNKNOWN


def ref_shape(e, ctx):
    comp = ctx.comp
    # A splat is a list only when it ENDS the expression: `aws_x.y[*].arn` is
    # a list of ARNs, `aws_x.y[*].arn[0]` is one ARN.
    m = SPLAT.match(e)
    if m:
        base, attr = m.group(1), m.group(2)
        resource = re.match(r'^(?:data\.)?[a-z][a-z0-9_]*\.' + IDENT + '$', base)
        if not resource or base.startswith(('var.', 'local.', 'module.', 'each.', 'count.')):
            return UNKNOWN
        return LIST(attr_shape(attr) if attr else UNKNOWN)
    m = re.match(r'^(' + IDENT + r')((?:\.' + IDENT + r'|' + INDEX + r')*)$', e)
    if m and m.group(1) in ctx.key_vars and not m.group(2):
        return SCALAR
    if m and m.group(1) in ctx.value_vars:
        tail = re.findall(r'\.(' + IDENT + r')', m.group(2))
        if not tail or not m.group(2).endswith(tail[-1]):
            return UNKNOWN
        return attr_shape(tail[-1], m.group(2).endswith('[0].' + tail[-1]))
    m = re.match(r'^var\.(' + IDENT + r')$', e)
    if m:
        return type_shape(comp.var_types.get(m.group(1), ''))
    m = re.match(r'^local\.(' + IDENT + r')$', e)
    if m:
        return shape_of(comp.locals.get(m.group(1), ''), ctx.deeper())
    m = re.match(r'^module\.(' + IDENT + r')\.(' + IDENT + r')$', e)
    if m:
        # A module with a LOCAL source is just another directory in this
        # repository -- kms wraps _library/security/kms-multi-region, and
        # idp-platform calls ../eks and ../rds -- so read its outputs too. A
        # registry or git module stays UNKNOWN: its source is not here.
        src = comp.modules.get(m.group(1), '').strip().strip('"')
        if not src.startswith(('./', '../')):
            return UNKNOWN
        mod = load_component(os.path.join(comp.path, src))
        out = mod.outputs.get(m.group(2))
        return UNKNOWN if out is None else shape_of(out, Ctx(mod, depth=ctx.depth + 1))
    m = RESOURCE_ATTR.match(e)
    if m and not e.startswith(('var.', 'local.', 'each.', 'count.', 'path.', 'terraform.', 'module.')):
        return attr_shape(m.group(1), e.endswith('[0].' + m.group(1)))
    return UNKNOWN
