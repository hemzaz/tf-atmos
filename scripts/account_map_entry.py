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
comments survive; the file is replaced atomically, keeping its mode.

Tests: workflows/scripts/common/test_account_map_entry.py.
"""
import os
import re
import sys
import tempfile

ID_RE = re.compile(r"^[0-9]{12}$")
ACCOUNT_RE = re.compile(r"^[a-z][a-z0-9-]*$")
KEY_RE = re.compile(r"^(\s*)([A-Za-z0-9_-]+):(.*)$")
ENTRY_RE = re.compile(r"^\s*([A-Za-z0-9_-]+):\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s#]*))\s*(#.*)?$")
MAP_PATH = ("settings", "account_map", "full_account_map")


class MapError(Exception):
    """A problem with the arguments or the file, reported as `error: <message>`."""


def header_lines(lines):
    """Indexes of the lines whose key path is settings.account_map.full_account_map."""
    stack = []  # (indent, key)
    found = []
    for i, line in enumerate(lines):
        if not line.strip() or line.lstrip().startswith(("#", "-")):
            continue
        m = KEY_RE.match(line.rstrip("\r\n"))
        if not m:
            continue
        indent = len(m.group(1))
        while stack and stack[-1][0] >= indent:
            stack.pop()
        stack.append((indent, m.group(2)))
        if tuple(k for _, k in stack) == MAP_PATH and not m.group(3).strip():
            found.append(i)
    return found


def entries(lines):
    """Return (index of the last entry line, entry indent, {account: id})."""
    headers = header_lines(lines)
    if not headers:
        raise MapError("no settings.account_map.full_account_map in the org defaults")
    if len(headers) > 1:
        raise MapError(f"settings.account_map.full_account_map appears {len(headers)} times")
    i = headers[0]
    base = len(lines[i]) - len(lines[i].lstrip())
    found, last, indent = {}, i, None
    for j in range(i + 1, len(lines)):
        text = lines[j].rstrip("\r\n")
        if not text.strip() or text.lstrip().startswith("#"):
            continue
        cur = len(text) - len(text.lstrip())
        if cur <= base:
            break
        em = ENTRY_RE.match(text)
        if not em:
            raise MapError(f"unexpected line {j + 1} in full_account_map: {text}")
        account, quoted = em.group(1), em.group(2) if em.group(2) is not None else em.group(3)
        if quoted is None:
            raise MapError(
                f"line {j + 1}: account '{account}' has the unquoted value {em.group(4)}; quote it "
                f'(`{account}: "{em.group(4)}"`): YAML reads an unquoted number as an int and drops leading zeros'
            )
        found[account] = quoted
        last, indent = j, cur
    if indent is None:
        raise MapError("full_account_map has no entries to follow")
    return last, indent, found


def write_atomic(path, text):
    """Replace path with text through a temp file in the same directory, keeping the mode."""
    mode = os.stat(path).st_mode & 0o7777
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(path)), prefix=".account_map.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def run(mode, path, account, account_id=""):
    """Check or add the entry; return the message to print. Raises MapError."""
    if mode not in ("check", "add"):
        raise MapError(f"unknown mode '{mode}'")
    if not ACCOUNT_RE.fullmatch(account):
        raise MapError(f"account name '{account}' must match {ACCOUNT_RE.pattern}")
    if account_id and not ID_RE.fullmatch(account_id):
        raise MapError(f"account ID '{account_id}' is not 12 digits")

    with open(path, encoding="utf-8", newline="") as f:
        lines = f.read().splitlines(keepends=True)
    last, indent, found = entries(lines)

    if account in found:
        if account_id and found[account] != account_id:
            raise MapError(f"account '{account}' is already in the account map as {found[account]}, not {account_id}")
        return f"account '{account}' is in the account map ({found[account]})"
    if not account_id:
        raise MapError(f"account '{account}' is not in the account map ({path}); set AWS_ACCOUNT_ID to its 12-digit ID")
    if mode == "check":
        return f"account '{account}' will be added to the account map ({account_id})"

    eol = "\r\n" if lines[last].endswith("\r\n") else "\n"
    if not lines[last].endswith(("\n", "\r")):
        lines[last] += eol
    lines.insert(last + 1, f'{" " * indent}{account}: "{account_id}"{eol}')
    write_atomic(path, "".join(lines))
    return f"added account '{account}' ({account_id}) to the account map"


def main(argv):
    if len(argv) not in (4, 5) or argv[1] not in ("check", "add"):
        print(__doc__, file=sys.stderr)
        return 2
    try:
        print(run(*argv[1:]))
    except MapError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
