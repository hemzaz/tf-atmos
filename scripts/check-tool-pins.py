#!/usr/bin/env python3
"""Fail when one toolchain tool is pinned to two different versions.

Atmos (1.229 and 1.233) gives each workflow and custom command only its own
`dependencies.tools`: there is no atmos.yaml-wide default they inherit, and the
only shared base (`.tool-versions`) is a regenerated developer-shell file this repo
does not commit. So a pin such as `terraform: "1.16.3"` repeats in every workflow
that runs terraform, and a bump that misses one copy runs two versions.

Every `dependencies.tools` entry under atmos.yaml, workflows/ and stacks/ names a
tool. Each later mention of that tool next to a version (`tool: "x.y.z"`,
`tool@x.y.z`, `tool==x.y.z`, `Tool x.y.z` in prose) in the files below must carry
the same version. A leading `v` and an owner prefix (`hashicorp/terraform`) are
ignored, so `tflint: "v0.64.0"` and `tflint@0.64.0` agree.

Usage: check-tool-pins.py [ROOT]   (default: the current directory)
Exit 0 when every tool has one version, 1 on a mismatch. Pure stdlib (runs in the
CI image).
"""

import pathlib
import re
import sys

# Files holding a tool pin or a copy of one. YAML globs are searched for
# `dependencies.tools` blocks (the declarations) and for mentions.
DECLARING_GLOBS = ("atmos.yaml", "workflows/*.yaml", "stacks/**/*.yaml")
MENTION_GLOBS = DECLARING_GLOBS + (
    ".github/workflows/*.yml",
    ".pre-commit-config.yaml",
    "README.md",
    "docs/*.md",
    "scripts/*.sh",
)

# Names a mention uses for a declared tool: pre-commit installs the Python
# yamllint, the workflows the go-yamllint (wasm) build of the same release.
ALIASES = {"yamllint": "go-yamllint"}

VERSION = r"v?\d+\.\d+\.\d+"
DEPS_LINE = re.compile(r"^(\s*)dependencies:\s*$")
TOOLS_LINE = re.compile(r"^(\s*)tools:\s*$")
ENTRY_LINE = re.compile(rf'^(\s*)([\w./-]+):\s*"?({VERSION})"?\s*(#.*)?$')


def short(tool):
    return tool.rsplit("/", 1)[-1].lower()


def norm(version):
    return version[1:] if version.startswith("v") else version


def declarations(lines):
    """(tool, version, line number) for each entry of a dependencies.tools block."""
    deps_indent = tools_indent = None
    for number, line in enumerate(lines, 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        if tools_indent is not None:
            entry = ENTRY_LINE.match(line)
            if indent > tools_indent and entry:
                yield short(entry.group(2)), norm(entry.group(3)), number
                continue
            tools_indent = None
        if deps_indent is not None and indent <= deps_indent:
            deps_indent = None
        match = DEPS_LINE.match(line)
        if match:
            deps_indent = len(match.group(1))
            continue
        match = TOOLS_LINE.match(line)
        if match and deps_indent is not None and len(match.group(1)) > deps_indent:
            tools_indent = len(match.group(1))


def mention_pattern(names):
    alternatives = "|".join(sorted((re.escape(n) for n in names), key=len, reverse=True))
    return re.compile(
        rf'(?<![\w-])(?:[\w.-]+/)?({alternatives})"?(?:\s*(?:==|@|:)\s*|\s+)"?({VERSION})\b',
        re.IGNORECASE,
    )


def collect(root):
    """{tool: {version: [location, ...]}} over every declaration and mention."""
    def paths(globs):
        return [p for g in globs for p in sorted(root.glob(g)) if p.is_file()]

    files = {p: p.read_text(encoding="utf-8").splitlines() for p in paths(MENTION_GLOBS)}
    declared = {tool for p in paths(DECLARING_GLOBS) for tool, _, _ in declarations(files[p])}
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
                pins.setdefault(tool, {}).setdefault(norm(match.group(2)), []).append(location)
    return pins


def main(argv):
    root = pathlib.Path(argv[1] if len(argv) > 1 else ".").resolve()
    pins = collect(root)
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
