#!/usr/bin/env python3
"""Fail on stack names and stack paths from before the Q4 region-code rename.

Stacks are {tenant}-{environment}-{stage}[-{name}] with the region's Cloud Posse
code as environment (fnx-ue1-dev, fnx-ue1-fixtures-batch; atmos.yaml
name_template), in stacks/orgs/<tenant>/<stage>/<region>.yaml. The old names put
the stage second and an instance name last (fnx-dev-testenv-01,
fnx-prod-production, fnx-fixtures-batch) and lived in
<stage>/<region>/<instance>.yaml. An old name left in a script, workflow, test or
doc points at a stack that no longer exists, so this fails on any of them.

This file and its test quote the old names and are skipped; any other line
that must quote one carries the marker "old-stack-names: allow".

Files are those git tracks or would track (git ls-files: ignored files such as
.terraform/ are left out); outside a usable git work tree the directories are
walked instead, skipping SKIP_DIRS.

Usage: check-old-stack-names.py [PATH...]   (default: the repository root)
Exit 0 when clean, 1 on a hit. Pure stdlib (runs in the CI image).
"""

import os
import pathlib
import re
import subprocess
import sys

ALLOW = "old-stack-names: allow"
SKIP_DIRS = {".git", ".terraform", ".worktrees", "node_modules", "__pycache__", ".omc"}
# Binary or generated files that never hold a stack name.
SKIP_SUFFIXES = {".png", ".jpg", ".gif", ".ico", ".zip", ".gz", ".pyc", ".lock.hcl"}
SKIP_FILES = {"check-old-stack-names.py", "test_check_old_stack_names.py"}

OLD_NAMES = (
    # The stage second: fnx-dev-testenv-01, fnx-prod-production, fnx-core-root,
    # fnx-fixtures-batch, fnx-local-sandbox.
    (re.compile(r"\bfnx-(dev|staging|prod|core|local|fixtures)\b"), "old stack name order (fnx-<stage>-...)"),
    # The old instance names.
    (re.compile(r"\btestenv-\d+\b"), "old instance name (testenv-NN)"),
    (re.compile(r"\bstaging-\d\d\b"), "old instance name (staging-NN)"),
    # The old instance files and directories.
    (
        re.compile(r"orgs/fnx/(dev|staging|prod|core)/[a-z]{2}-[a-z]+-\d/(testenv-\d+|staging-\d+|production|root)\b"),
        "old stack path (<stage>/<region>/<instance>)",
    ),
    (re.compile(r"fixtures/us-east-1/idpplatform\b"), "old fixture path"),
)


def hits(text):
    """(line number, label, line) for every old name outside an allowed line."""
    for number, line in enumerate(text.splitlines(), 1):
        if ALLOW in line:
            continue
        for pattern, label in OLD_NAMES:
            if pattern.search(line):
                yield number, label, line.strip()
                break


def git_files(path):
    """The files git tracks or would track under path (ignored ones left out), or None outside a
    usable work tree (no git, not a repository, or an unsafe owner as in the CI container)."""
    try:
        out = subprocess.run(
            ["git", "-C", str(path), "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
            capture_output=True, check=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError):
        return None
    return sorted(path / name for name in out.decode().split("\0") if name)


def walked_files(path):
    for root, dirs, names in os.walk(path):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
        for name in sorted(names):
            yield pathlib.Path(root) / name


def files(paths):
    for path in paths:
        path = pathlib.Path(path)
        if path.is_file():
            if path.name not in SKIP_FILES:
                yield path
            continue
        listed = git_files(path)
        for file in walked_files(path) if listed is None else listed:
            if (file.name not in SKIP_FILES and not any(file.name.endswith(s) for s in SKIP_SUFFIXES)
                    and not SKIP_DIRS.intersection(file.parts) and file.is_file()):
                yield file


def main(argv):
    found = 0
    for path in files(argv or ["."]):
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for number, label, line in hits(text):
            print(f"{path}:{number}: {label}: {line}")
            found += 1
    if found:
        print(f"{found} old stack name(s): use {{tenant}}-{{environment}}-{{stage}}[-{{name}}] (fnx-ue1-dev) "
              "and stacks/orgs/<tenant>/<stage>/<region>.yaml (README.md, Stacks)")
        return 1
    print("no stack name or stack path from before the region-code rename")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
