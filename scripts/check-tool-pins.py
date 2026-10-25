#!/usr/bin/env python3
"""Fail when one toolchain tool is pinned to two different versions.

Atmos (1.229, 1.233) gives each workflow and custom command only its own
`dependencies.tools` (no atmos.yaml-wide default; `.tool-versions` is not committed),
so a pin repeats in every workflow that needs the tool.

Each `dependencies.tools` entry under atmos.yaml, workflows/ and stacks/ declares a
tool (block or flow style; anything but an exact `x.y.z` pin fails). Every mention of
a declared tool with a version in MENTION_GLOBS must match: `tool: "x.y.z"` (any
quotes), `tool@`, `tool==`, `tool=`, `tool-x.y.z`, `TOOL_VERSION: x.y.z` (`TF_VERSION`
for terraform), and prose such as `Terraform 1.5.7`, which counts as a pin. A leading
`v` and an owner prefix (`hashicorp/`) are ignored.
Out of scope: constraints and two-part versions (`~> 1.16`), `.tf` files, nested docs.

Usage: check-tool-pins.py [ROOT]. Exit 0 when each tool has one version, else 1. Stdlib only.
"""

import pathlib
import re
import sys

DECLARING_GLOBS = ("atmos.yaml", "workflows/*.yaml", "stacks/**/*.yaml")
MENTION_GLOBS = DECLARING_GLOBS + (
    ".github/workflows/*.yml",
    ".pre-commit-config.yaml",
    "README.md",
    "docs/*.md",
    "scripts/*.sh",
    "workflows/scripts/**/*.sh",
    "Makefile",
)

# pre-commit's yamllint is the release go-yamllint (wasm) builds; `tf` only as TF_VERSION.
ALIASES = {"yamllint": "go-yamllint", "tf": "terraform"}

VERSION = r"v?\d+\.\d+\.\d+"
Q = "[\"']?"
DEPS_LINE = re.compile(r"^(\s*)dependencies:\s*$")
TOOLS_LINE = re.compile(r"^(\s*)tools:\s*(#.*)?$")
FLOW_LINE = re.compile(r"^(\s*)tools:\s*\{(.*)\}\s*(#.*)?$")
ENTRY_LINE = re.compile(rf"^(\s*)([\w./-]+):\s*{Q}({VERSION}){Q}\s*(#.*)?$")
FLOW_ENTRY = re.compile(rf"^\s*{Q}([\w./-]+){Q}\s*:\s*{Q}({VERSION}){Q}\s*$")


class PinError(Exception):
    pass


def short(tool):
    return tool.rsplit("/", 1)[-1].lower()


def flow_entries(body, number):
    for item in filter(str.strip, body.split(",")):
        entry = FLOW_ENTRY.match(item)
        if not entry:
            raise PinError(f"{number}: flow-style tools entry {item.strip()!r} is not tool: x.y.z")
        yield short(entry.group(1)), entry.group(2).removeprefix("v"), number


def declarations(lines):
    """(tool, version, line number) for each entry of a dependencies.tools block.

    Raises PinError on an entry that is not an exact x.y.z pin."""
    deps_indent = tools_indent = None
    for number, line in enumerate(lines, 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        if tools_indent is not None:
            entry = ENTRY_LINE.match(line)
            if indent > tools_indent:
                if not entry:
                    raise PinError(f"{number}: tools entry {line.strip()!r} is not an exact x.y.z pin")
                yield short(entry.group(2)), entry.group(3).removeprefix("v"), number
                continue
            tools_indent = None
        if deps_indent is not None and indent <= deps_indent:
            deps_indent = None
        match = DEPS_LINE.match(line)
        if match:
            deps_indent = len(match.group(1))
            continue
        if deps_indent is None or indent <= deps_indent or not line.lstrip().startswith("tools:"):
            continue
        match = FLOW_LINE.match(line)
        if match:
            yield from flow_entries(match.group(2), number)
        elif TOOLS_LINE.match(line):
            tools_indent = indent
        else:
            raise PinError(f"{number}: unreadable tools line {line.strip()!r}")


def mention_pattern(names):
    alternatives = "|".join(sorted((re.escape(n) for n in names), key=len, reverse=True))
    return re.compile(
        rf"(?<![\w-])(?:[\w.-]+/)?({alternatives}|tf(?=_version))(?:_version)?{Q}"
        rf"(?:\s*(?:==|=|@|:)\s*|\s+|-){Q}({VERSION})\b",
        re.IGNORECASE,
    )


def collect(root):
    """{tool: {version: [location, ...]}} over every declaration and mention."""
    def paths(globs):
        return [p for g in globs for p in sorted(root.glob(g)) if p.is_file()]

    files = {p: p.read_text(encoding="utf-8").splitlines() for p in paths(MENTION_GLOBS)}
    declared = set()
    for path in paths(DECLARING_GLOBS):
        try:
            declared |= {tool for tool, _, _ in declarations(files[path])}
        except PinError as err:
            raise PinError(f"{path.relative_to(root)}:{err}") from None
    names = declared | {alias for alias, tool in ALIASES.items() if tool in declared}
    pins = {}
    if not names:
        return pins
    pattern = mention_pattern(names)
    for path, lines in files.items():
        for number, line in enumerate(lines, 1):
            for match in pattern.finditer(line):
                tool = short(match.group(1))
                tool = ALIASES.get(tool, tool)
                location = f"{path.relative_to(root)}:{number}"
                pins.setdefault(tool, {}).setdefault(match.group(2).removeprefix("v"), []).append(location)
    return pins


def main(argv):
    root = pathlib.Path(argv[1] if len(argv) > 1 else ".").resolve()
    try:
        pins = collect(root)
    except PinError as err:
        print(f"check-tool-pins: {err}", file=sys.stderr)
        return 1
    if not pins:
        print(f"check-tool-pins: no dependencies.tools under {root}", file=sys.stderr)
        return 1
    failed = False
    for tool in sorted(pins):
        versions = pins[tool]
        if len(versions) == 1:
            continue
        failed = True
        print(f"check-tool-pins: {tool} is pinned to {len(versions)} versions:", file=sys.stderr)
        for version in sorted(versions):
            print(f"  {version}: {', '.join(versions[version])}", file=sys.stderr)
    if failed:
        print("Bump every copy to one version (docs/OPERATIONS.md, Pinned versions).", file=sys.stderr)
        return 1
    summary = ", ".join(f"{t} {next(iter(v))}" for t, v in sorted(pins.items()))
    print(f"check-tool-pins: one version per tool ({summary})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
