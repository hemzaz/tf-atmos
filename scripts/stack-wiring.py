#!/usr/bin/env python3
"""Wire a new stage stack into the state backend that owns its state.

Usage: stack-wiring.py [--root DIR] <tenant> <stage> <account> <region> <stack>

The stack scaffold's `wire` hook (scaffolds/stack/scaffold.yaml) runs this after
it writes stacks/orgs/<tenant>/<stage>/<region>.yaml. It edits the owning
backend's file, stacks/orgs/<tenant>/root/us-east-1.yaml (fnx-ue1-root), or
root/eu-west-1.yaml (fnx-ew1-root) for the prod-eu account, and adds what
check-state-keys.py and check-ci-state-roles.py require there:
  - the stack's exact state pattern pair, "*/<stack>/*" and "*/<stack>-*", to
    its stage's anchored list (`object_key_patterns: &non_prod_state` for dev
    and staging, `&prod_state` for prod), which the write role reuses through
    its alias;
  - its CI roles, <stack>-ci-plan to the read role's allowed_principal_arns
    (read, or prod_read for prod) and <stack>-ci-apply to the write role's
    (write, prod_write), in its account (settings.account_map).
The edit is textual: it inserts lines after each list's last item and leaves
every other byte, anchors and comments included, as it was. A file without a
final newline keeps it missing, unless a line goes after its last line, which
then gets one. A value already in its list is skipped, so a second run changes
nothing. When a marker is missing
(the access_roles block, the role, the anchored list, the write role's alias),
or a value sits in some other list, it changes nothing and prints the edit to
make by hand. NS delegation needs the deployed zone's name servers, so it only
prints that step.

--root is the repository to edit (the tests' copies); by default this script's
own, so a scratch copy's hook edits that copy. A concurrent run waits on a lock
on the backend file's directory.
Every argument is validated here too, whatever the scaffold's fields already
checked; the stack's region code must be its region mixin's environment. Exit 0 when the stack is
wired (now or already), 1 otherwise.
"""
import argparse
import contextlib
import fcntl
import os
import pathlib
import re
import sys
import tempfile
from typing import Optional

TENANT = re.compile(r"[a-z][a-z0-9]{1,9}")
REGION = re.compile(r"[a-z]{2}-[a-z]+-[0-9]")
STAGES = ("dev", "staging", "prod")
ACCOUNTS = ("dev", "staging", "prod", "prod-eu")
# Each owning backend's file and stack (the region code of its bucket's region).
BACKENDS = {False: ("us-east-1", "ue1"), True: ("eu-west-1", "ew1")}


class Refused(Exception):
    """A marker is missing or the file disagrees: nothing is written."""


def fail(message: str) -> None:
    raise Refused(message)


def validate(tenant: str, stage: str, account: str, region: str, stack: str) -> str:
    """The account (the stage's own when empty); Refused on any bad argument."""
    if not TENANT.fullmatch(tenant):
        fail(f"tenant {tenant!r} is not 2-10 lowercase letters/digits starting with a letter")
    if stage not in STAGES:
        fail(f"stage {stage!r} is not one of {', '.join(STAGES)}")
    account = account or stage
    if account not in ACCOUNTS:
        fail(f"account {account!r} is not one of {', '.join(ACCOUNTS)}")
    if account != stage and not (stage == "prod" and account == "prod-eu"):
        fail(f"account {account!r} does not belong to stage {stage!r} (its own, or prod-eu for prod)")
    if not REGION.fullmatch(region):
        fail(f"region {region!r} is not an AWS region")
    if (account == "prod-eu") != region.startswith("eu-"):
        fail(f"account {account!r} and region {region!r} disagree: the EU regions are exactly the prod-eu account's")
    if not re.fullmatch(rf"{tenant}-[a-z]{{2}}[a-z]?[0-9]-{stage}", stack):
        fail(f"stack {stack!r} is not {tenant}-<region code>-{stage}")
    return account


def arn(account: str, stack: str, kind: str) -> tuple[str, str]:
    """(value, YAML line text) of the stack's CI role ARN, as the root files write it."""
    if re.fullmatch(r"[a-z]+", account):
        value = f"arn:aws:iam::{{{{ .settings.account_map.full_account_map.{account} }}}}:role/{stack}-ci-{kind}"
        return value, f'"{value}"'
    # A hyphenated account map key needs index (fnx-ew1-root's style).
    value = f'arn:aws:iam::{{{{ index .settings.account_map.full_account_map "{account}" }}}}:role/{stack}-ci-{kind}'
    return value, f"'{value}'"


def indent(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def ignorable(line: str) -> bool:
    text = line.strip()
    return not text or text.startswith("#")


def block_end(lines: list[str], start: int) -> int:
    """The index after the block that lines[start] opens (its deeper lines)."""
    end = start + 1
    while end < len(lines) and (ignorable(lines[end]) or indent(lines[end]) > indent(lines[start])):
        end += 1
    # Trailing comments and blank lines belong to whatever follows.
    while end > start + 1 and ignorable(lines[end - 1]):
        end -= 1
    return end


def find(lines: list[str], start: int, end: int, pattern: str, what: str) -> int:
    """The one line in [start, end) matching pattern, as a key at the block's child level."""
    child = next((indent(lines[i]) for i in range(start, end) if not ignorable(lines[i])), None)
    hits = [i for i in range(start, end)
            if indent(lines[i]) == child and re.fullmatch(pattern, lines[i].strip())]
    if len(hits) != 1:
        fail(f"found {len(hits)} {what}, expected exactly one")
    return hits[0]


def scalar(item: str) -> str:
    """A list item's value: '- "x"' / "- 'x'" / '- x', with any trailing comment -> x."""
    text = item.strip()[1:].strip()
    double = re.fullmatch(r'"([^"\\]*)"(\s+#.*)?', text)
    if double:
        return double.group(1)
    single = re.fullmatch(r"'((?:[^']|'')*)'(\s+#.*)?", text)
    if single:
        return single.group(1).replace("''", "'")
    return re.sub(r"\s+#.*$", "", text)


def items(lines: list[str], key: int) -> tuple[list[int], int]:
    """The item lines of the block list under lines[key], and their indentation."""
    end = block_end(lines, key)
    found = [i for i in range(key + 1, end) if not ignorable(lines[i])]
    for i in found:
        if not lines[i].strip().startswith("- "):
            fail(f"{lines[key].strip()!r} is not a plain list (line {i + 1}: {lines[i].strip()!r})")
    if found and len({indent(lines[i]) for i in found}) != 1:
        fail(f"{lines[key].strip()!r}'s items are not evenly indented")
    return found, indent(lines[found[0]]) if found else indent(lines[key]) + 2


def every_value(lines: list[str]) -> list[str]:
    return [scalar(line) for line in lines if line.strip().startswith("- ")]


def plan(text: str, stage: str, account: str, stack: str) -> tuple[list[tuple[int, list[str]]], list[str]]:
    """The insertions (after line index, new lines) and a description of each; Refused if unsafe."""
    lines = text.splitlines(keepends=True)
    prod = stage == "prod"
    anchor = "prod_state" if prod else "non_prod_state"
    read, write = ("prod_read", "prod_write") if prod else ("read", "write")
    newline = "\r\n" if "\r\n" in text else "\n"

    access = [i for i, line in enumerate(lines) if re.fullmatch(r"access_roles:", line.strip())]
    if len(access) != 1:
        fail(f"found {len(access)} access_roles: blocks, expected exactly one")
    roles_end = block_end(lines, access[0])
    roles = {}
    for role in (read, write):
        line = find(lines, access[0] + 1, roles_end, rf"{role}:", f"{role}: roles under access_roles")
        roles[role] = (line, block_end(lines, line))

    start, end = roles[read]
    patterns_key = find(lines, start + 1, end, rf"object_key_patterns: &{anchor}",
                        f"'object_key_patterns: &{anchor}' lists in the {read} role")
    start, end = roles[write]
    find(lines, start + 1, end, rf"object_key_patterns: \*{anchor}",
         f"'object_key_patterns: *{anchor}' aliases in the {write} role")

    everywhere = every_value(lines)
    inserts, done = [], []

    found, pad = items(lines, patterns_key)
    present = [scalar(lines[i]) for i in found]
    pair = [f"*/{stack}/*", f"*/{stack}-*"]
    have = [p for p in pair if p in present]
    if len(have) == 1:
        fail(f"&{anchor} has {have[0]!r} without its companion; add the pair by hand")
    if not have:
        for pattern in pair:
            if pattern in everywhere:
                fail(f"{pattern!r} is already in another list (another stage's roles?)")
        after = found[-1] if found else patterns_key
        inserts.append((after, [f'{" " * pad}- "{p}"{newline}' for p in pair]))
        done.append(f"state patterns {pair[0]} and {pair[1]} -> &{anchor} ({read}, and {write} by alias)")

    for role, kind in ((read, "plan"), (write, "apply")):
        start, end = roles[role]
        key = find(lines, start + 1, end, r"allowed_principal_arns:",
                   f"allowed_principal_arns: lists in the {role} role")
        found, pad = items(lines, key)
        value, text_value = arn(account, stack, kind)
        if value in [scalar(lines[i]) for i in found]:
            continue
        if value in everywhere:
            fail(f"{value!r} is already in another list (another role's?)")
        inserts.append((found[-1] if found else key, [f'{" " * pad}- {text_value}{newline}']))
        done.append(f"CI {kind} role {stack}-ci-{kind} -> {role}.allowed_principal_arns")
    return inserts, done


def apply(text: str, inserts: list[tuple[int, list[str]]]) -> str:
    lines = text.splitlines(keepends=True)
    # The last line gets its newline only when something is inserted after it.
    if lines and not lines[-1].endswith("\n") and any(after == len(lines) - 1 for after, _ in inserts):
        lines[-1] += "\r\n" if "\r\n" in text else "\n"
    for after, new in sorted(inserts, reverse=True):
        lines[after + 1:after + 1] = new
    return "".join(lines)


def manual(path: str, stage: str, account: str, stack: str) -> str:
    prod = stage == "prod"
    anchor = "prod_state" if prod else "non_prod_state"
    read, write = ("prod_read", "prod_write") if prod else ("read", "write")
    return "\n".join([
        f"Wire {stack} by hand in {path}, under backend/main's vars.access_roles:",
        f'  {read}.object_key_patterns (&{anchor}): - "*/{stack}/*" and - "*/{stack}-*"',
        f"  {read}.allowed_principal_arns: - {arn(account, stack, 'plan')[1]}",
        f"  {write}.allowed_principal_arns: - {arn(account, stack, 'apply')[1]}",
        "then run check-state-keys.py and check-ci-state-roles.py (atmos workflow lint -f lint).",
    ])


@contextlib.contextmanager
def exclusive(path: pathlib.Path):
    """Hold an exclusive lock over the read-modify-write of path (a concurrent run waits).

    The lock is on path's directory: the write replaces path's inode but not
    the directory's, and every run, whatever its TMPDIR, locks the same one,
    without creating a file.
    """
    fd = os.open(path.parent, os.O_RDONLY)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        os.close(fd)


def wire(root: pathlib.Path, tenant: str, stage: str, account: str, region: str, stack: str) -> list[str]:
    """Edit the owning backend's file; the changes made (empty: already wired). Refused if unsafe."""
    account = validate(tenant, stage, account, region, stack)
    backend_region, _ = BACKENDS[account == "prod-eu"]
    rel = f"stacks/orgs/{tenant}/root/{backend_region}.yaml"
    mixin = root / "stacks" / "mixins" / "region" / f"{region}.yaml"
    if not mixin.is_file():
        fail(f"no region mixin {mixin}")
    code = re.search(r"^ *environment: *([a-z0-9]*) *$", mixin.read_text(encoding="utf-8"), re.M)
    if not code or stack != f"{tenant}-{code.group(1)}-{stage}":
        fail(f"stack {stack!r} is not {tenant}-<{mixin.name}'s environment, {code and code.group(1)}>-{stage}")
    # A symlinked root file is edited through the link, which stays a link.
    path = (root / rel).resolve()
    if not path.is_file():
        fail(f"no {rel}, the backend owning {stack}'s state")
    with exclusive(path):
        # Bytes as they are: no newline translation.
        text = path.read_bytes().decode("utf-8")
        try:
            inserts, done = plan(text, stage, account, stack)
        except Refused as error:
            raise Refused(f"{rel}: {error}\n{manual(rel, stage, account, stack)}") from None
        if inserts:
            handle, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
            try:
                with os.fdopen(handle, "w", encoding="utf-8", newline="") as out:
                    out.write(apply(text, inserts))
                os.chmod(tmp, path.stat().st_mode & 0o7777)
                os.replace(tmp, path)
            except BaseException:
                os.unlink(tmp)
                raise
    return [f"{rel}: {line}" for line in done]


def next_steps(tenant: str, stage: str, account: str, stack: str, changed: bool) -> str:
    _, code = BACKENDS[(account or stage) == "prod-eu"]
    steps = []
    if changed:
        steps.append(f"Next for {stack}: apply backend/main in {tenant}-{code}-root (its access roles"
                     " changed) before the stack's first init.")
    steps += [
        f"Not automated for {stack}: before deploy layer certificates, delegate its",
        "settings.environment.domain_name to its network/main zone_name_servers.main",
        f"(atmos terraform output network/main -s {stack}); docs/OPERATIONS.md, Deploying a stack.",
    ]
    return "\n".join(steps)


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--root", type=pathlib.Path,
                        default=pathlib.Path(__file__).resolve().parents[1],
                        help="repository to edit (default: this script's)")
    for name in ("tenant", "stage", "account", "region", "stack"):
        parser.add_argument(name)
    args = parser.parse_args(argv)
    try:
        done = wire(args.root, args.tenant, args.stage, args.account, args.region, args.stack)
    except Refused as error:
        print(f"stack-wiring: refused, nothing written: {error}", file=sys.stderr)
        return 1
    for line in done:
        print(f"stack-wiring: added {line}")
    if not done:
        print(f"stack-wiring: {args.stack} is already wired (nothing to add)")
    print(next_steps(args.tenant, args.stage, args.account, args.stack, bool(done)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
