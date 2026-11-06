#!/usr/bin/env python3
"""Check that aws-identity-center's house Plan-set override still restates upstream.

Usage: check-identity-center-override.py [component dir]
(default components/terraform/aws-identity-center)

policy-TerraformPlanAccess_override.tf (house) overrides two policy documents of the
vendored policy-TerraformAccess.tf, terraform_plan_access and
terraform_plan_access_additional, so the TerraformPlanAccess* sets assume a backend's read
role. Terraform replaces every nested "statement" of an overridden block, so the override
restates upstream's statements, and a vendor bump that adds, drops or changes one would be
silently undone. This compares the two, statement by statement (keyed by sid, plain or
dynamic "statement" content, and the dynamic's own for_each): the same sids, and in each
the same attributes and the same list of each nested block (every condition and principals
block, not one per name), whitespace and trailing commas aside, except the assumed role (the
"resources" and dynamic for_each of TerraformStateBackendAssumeRole), the one intended
change. It also requires the override's tf_access_additional_backends type to keep every upstream field, unchanged, and add only
read_role_arn. A tests/ directory cannot live in the vendored dir (check-vendor.py allows
only *_override.tf and the lock file there), so this guard is a lint step, not a tftest.
Exits 1 on any difference.
"""
import pathlib
import re
import sys

UPSTREAM = "policy-TerraformAccess.tf"
OVERRIDE = "policy-TerraformPlanAccess_override.tf"
DOCUMENTS = ("terraform_plan_access", "terraform_plan_access_additional")
ASSUME_SID = "TerraformStateBackendAssumeRole"
# The intended change: the assumed role, and the dynamic for_each that skips a backend without one.
ASSUME_CHANGES = {"attr:resources", "dynamic.attr:for_each"}
ADDED_FIELDS = {"read_role_arn"}


def strip_comments(text: str) -> str:
    return re.sub(r"(?m)^\s*(#|//).*$", "", text)


def block(text: str, header: str) -> str:
    """The body of the first block whose opening line matches header (a regex), braces balanced."""
    match = re.search(header + r"\s*\{", text)
    if not match:
        raise ValueError(f"no block {header!r}")
    depth, start = 1, match.end()
    for i in range(start, len(text)):
        depth += {"{": 1, "}": -1}.get(text[i], 0)
        if depth == 0:
            return text[start:i]
    raise ValueError(f"unbalanced block {header!r}")


def children(body: str) -> list[tuple[str, str]]:
    """(name, text) of each top-level item of a block body: 'attr:<k>' -> value, 'block:<n>' -> body."""
    items, i = [], 0
    while i < len(body):
        rest = body[i:]
        head = re.match(r'\s*(dynamic\s+"(\w+)"|(\w+))\s*(=|\{)', rest)
        if not head:
            if rest.strip():
                raise ValueError(f"cannot parse {rest.strip()[:60]!r}")
            break
        name = head.group(2) or head.group(3)
        j = i + head.end()
        if head.group(4) == "{" or head.group(2):
            if head.group(4) == "=":
                raise ValueError(f"cannot parse dynamic {name}")
            depth = 1
            while depth:
                depth += {"{": 1, "}": -1}.get(body[j], 0)
                j += 1
            items.append(("dynamic:" + name if head.group(2) else "block:" + name, body[i + head.end():j - 1]))
        else:
            depth = 0
            while j < len(body) and not (depth == 0 and body[j] == "\n" and body[i + head.end():j].strip()):
                depth += {"[": 1, "(": 1, "{": 1, "]": -1, ")": -1, "}": -1}.get(body[j], 0)
                j += 1
            items.append(("attr:" + name, body[i + head.end():j]))
        i = j
    return items


def normalized(text: str) -> str:
    return re.sub(r",(?=[\]\)])", "", re.sub(r"\s+", "", text))


def statements(document: str) -> dict:
    """sid -> {child name: sorted normalized texts} of every statement (plain, or a dynamic one's content,
    plus the dynamic's own for_each/iterator as 'dynamic.<name>'). A list per name, so a second condition
    or principals block is compared, not collapsed into one."""
    found = {}
    for name, body in children(document):
        outer = {}
        if name == "dynamic:statement":
            dynamic = children(body)
            content = [text for child, text in dynamic if child == "block:content"]
            if len(content) != 1:
                raise ValueError("dynamic statement without one content block")
            outer = {"dynamic." + child: [normalized(text)] for child, text in dynamic if child != "block:content"}
            body = content[0]
        elif name != "block:statement":
            continue
        parts = dict(outer)
        for child, text in children(body):
            parts.setdefault(child, []).append(normalized(text))
        parts = {child: sorted(texts) for child, texts in parts.items()}
        sid = (parts.get("attr:sid") or [""])[0].strip('"')
        if not sid or sid in found:
            raise ValueError(f"statement without a unique literal sid: {parts}")
        found[sid] = parts
    return found


def fields(variable: str) -> dict:
    match = re.search(r"object\(\{(.*)\}\)", variable, re.S)
    if not match:
        raise ValueError("tf_access_additional_backends has no object type")
    return {name: normalized(value) for name, value in re.findall(r"(?m)^\s*(\w+)\s*=\s*(.+)$", match.group(1))}


def check(directory: pathlib.Path) -> list[str]:
    upstream = strip_comments((directory / UPSTREAM).read_text())
    override = strip_comments((directory / OVERRIDE).read_text())
    errors = []
    for document in DOCUMENTS:
        header = rf'data\s+"aws_iam_policy_document"\s+"{document}"'
        theirs, ours = statements(block(upstream, header)), statements(block(override, header))
        if sorted(theirs) != sorted(ours):
            errors.append(f"{document}: statement sids {sorted(ours)} in {OVERRIDE}, {sorted(theirs)} upstream")
        for sid in sorted(set(theirs) & set(ours)):
            keys = set(theirs[sid]) | set(ours[sid])
            for key in sorted(keys - (ASSUME_CHANGES if sid == ASSUME_SID else set())):
                if theirs[sid].get(key) != ours[sid].get(key):
                    errors.append(f"{document}: statement {sid} {key}: {ours[sid].get(key)!r} in {OVERRIDE}, "
                                  f"{theirs[sid].get(key)!r} upstream")
    variable = r'variable\s+"tf_access_additional_backends"'
    theirs, ours = fields(block(upstream, variable)), fields(block(override, variable))
    for name in sorted(set(theirs) | set(ours)):
        if name in ADDED_FIELDS and name not in theirs:
            continue
        if theirs.get(name) != ours.get(name):
            errors.append(f"tf_access_additional_backends field {name}: {ours.get(name)!r} in {OVERRIDE}, "
                          f"{theirs.get(name)!r} upstream")
    return errors


def main(argv: list[str]) -> int:
    directory = pathlib.Path(argv[1] if len(argv) > 1 else "components/terraform/aws-identity-center")
    try:
        errors = check(directory)
    except (OSError, ValueError) as error:
        errors = [str(error)]
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{OVERRIDE} no longer restates upstream {UPSTREAM}: re-derive it from the vendored file")
        return 1
    print(f"{OVERRIDE} restates upstream's {', '.join(DOCUMENTS)} statements, only the assumed role changed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
