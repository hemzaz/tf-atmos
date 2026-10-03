#!/usr/bin/env python3
"""Check or add one entry of settings.account_map.full_account_map in an org _defaults.yaml.

Used by scripts/new-environment.sh. The account map is the only place account
IDs are written (stacks/orgs/fnx/_defaults.yaml), so a new stage's account goes
there, not into the stage's _defaults.yaml.

    account_map_entry.py check <org_defaults.yaml> <account> [<id>]
    account_map_entry.py add   <org_defaults.yaml> <account> [<id>]

check: exit 0 if <account> is in the map (with <id>, when given) or if it is
absent and a valid <id> is given (add would succeed); exit 1 otherwise, saying why.
add:   the same checks, then append `<account>: "<id>"` to full_account_map
when it is absent (a no-op when it is there). Text-level, so the file's
comments survive.
"""
import re
import sys

ID_RE = re.compile(r"^[0-9]{12}$")
HEADER_RE = re.compile(r"^(\s*)full_account_map:\s*$")


def entries(lines):
    """Return (index of the last entry line, entry indent, {account: id})."""
    for i, line in enumerate(lines):
        m = HEADER_RE.match(line)
        if not m:
            continue
        base = len(m.group(1))
        found, last, indent = {}, i, None
        for j in range(i + 1, len(lines)):
            text = lines[j]
            if not text.strip() or text.lstrip().startswith("#"):
                continue
            cur = len(text) - len(text.lstrip())
            if cur <= base:
                break
            em = re.match(r"^\s*([A-Za-z0-9_-]+):\s*[\"']?([0-9]*)[\"']?\s*(#.*)?$", text)
            if not em:
                raise SystemExit(f"error: unexpected line {j + 1} in full_account_map: {text.rstrip()}")
            found[em.group(1)] = em.group(2)
            last, indent = j, cur
        if indent is None:
            raise SystemExit("error: full_account_map has no entries to follow")
        return last, indent, found
    raise SystemExit("error: no settings.account_map.full_account_map in the org defaults")


def main(argv):
    if len(argv) not in (4, 5) or argv[1] not in ("check", "add"):
        raise SystemExit(__doc__)
    mode, path, account = argv[1], argv[2], argv[3]
    account_id = argv[4] if len(argv) == 5 else ""
    if account_id and not ID_RE.match(account_id):
        raise SystemExit(f"error: account ID '{account_id}' is not 12 digits")

    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines(keepends=True)
    last, indent, found = entries(lines)

    if account in found:
        if account_id and found[account] != account_id:
            raise SystemExit(
                f"error: account '{account}' is already in the account map as {found[account]}, not {account_id}"
            )
        print(f"account '{account}' is in the account map ({found[account]})")
        return 0
    if not account_id:
        raise SystemExit(
            f"error: account '{account}' is not in the account map ({path}); set AWS_ACCOUNT_ID to its 12-digit ID"
        )
    if mode == "check":
        print(f"account '{account}' will be added to the account map ({account_id})")
        return 0

    if not lines[last].endswith("\n"):
        lines[last] += "\n"
    lines.insert(last + 1, f'{" " * indent}{account}: "{account_id}"\n')
    with open(path, "w", encoding="utf-8") as f:
        f.writelines(lines)
    print(f"added account '{account}' ({account_id}) to the account map")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
