#!/usr/bin/env python3
"""Fail when one toolchain tool is pinned to two different versions.

Atmos (1.229, 1.233) gives each workflow and custom command only its own
`dependencies.tools` (no atmos.yaml-wide default; `.tool-versions` is not committed),
so a pin repeats in every workflow that needs the tool (or is shared through a YAML anchor,
alias or merge key).

The line scan below only finds the pins and their line numbers. For workflows/*.yaml it is then
cross-checked against `atmos describe workflows --format json -o all`, where Atmos's own YAML
parse has already resolved anchors, aliases and merge keys: per workflow, the (tool, version)
pairs read from the file must equal what Atmos resolves, else the check fails naming the
workflow, the tool and both values. Atmos must be on PATH (it is under `atmos workflow lint`
and in CI's ghcr.io/cloudposse/atmos image); for unit tests and offline use,
CHECK_TOOL_PINS_DESCRIBE_JSON=<file> names a saved copy of that command's output.

Each `dependencies.tools` entry under atmos.yaml, workflows/ and stacks/ declares a
tool (block or flow style; anything but an exact `x.y.z` pin fails). Every mention of
a declared tool with a version in MENTION_GLOBS must match: `tool: "x.y.z"` (any
quotes), `tool@`, `tool==`, `tool=`, `tool-x.y.z`, `TOOL_VERSION: x.y.z` (`TF_VERSION`
for terraform), and prose such as `Terraform 1.5.7`, which counts as a pin. A leading
`v` and an owner prefix (`hashicorp/`) are ignored.
Out of scope: constraints and two-part versions (`~> 1.16`), `.tf` files, nested docs.

Usage: check-tool-pins.py [ROOT]. Exit 0 when each tool has one version, else 1. Stdlib only.
"""

import json
import os
import pathlib
import re
import shutil
import subprocess
import sys

DESCRIBE_ENV = "CHECK_TOOL_PINS_DESCRIBE_JSON"
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
DEPS_LINE = re.compile(r"^(\s*)dependencies:(.*)$")
DEPS_TAIL = re.compile(r"^\s*(?:([&*])([\w-]+))?\s*(?:#.*)?$")
WORKFLOWS_LINE = re.compile(r"^workflows:\s*(#.*)?$")
WORKFLOW_KEY = re.compile(r"^\s*[\"']?([\w.-]+)[\"']?:")
MERGE_LINE = re.compile(r"^\s*<<:(.*)$")
MERGE_TAIL = re.compile(r"^\s*\*([\w-]+)\s*(?:#.*)?$")
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


def declarations(lines, resolved=None):
    """(tool, version, line number) for each entry of a dependencies.tools block.

    Raises PinError on an entry that is not an exact x.y.z pin. When `resolved` is a dict, it
    also collects {workflow: {tool: (version, line)}} as the line scan reads each workflow of a
    `workflows:` map, following `dependencies: *name` aliases and `<<: *name` merge keys to the
    latest `dependencies: &name` block above them (the cross-check against Atmos's own parse
    decides whether that reading is right)."""
    deps_indent = tools_indent = child_indent = None
    in_workflows, wf_indent, workflow = False, None, None
    anchors, pins, local_tools = {}, {}, False
    for number, line in enumerate(lines, 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        if indent == 0:
            in_workflows, wf_indent, workflow = bool(WORKFLOWS_LINE.match(line)), None, None
        elif in_workflows:
            wf_indent = indent if wf_indent is None else wf_indent
            key = WORKFLOW_KEY.match(line) if indent == wf_indent else None
            workflow = key.group(1) if key else workflow
        if tools_indent is not None:
            entry = ENTRY_LINE.match(line)
            if indent > tools_indent:
                if not entry:
                    raise PinError(f"{number}: tools entry {line.strip()!r} is not an exact x.y.z pin")
                tool, version = short(entry.group(2)), entry.group(3).removeprefix("v")
                pins[tool] = (version, number)
                yield tool, version, number
                continue
            tools_indent = None
        if deps_indent is not None and indent <= deps_indent:
            deps_indent = None
        if deps_indent is not None and child_indent is None:
            child_indent = indent
        merge = MERGE_LINE.match(line) if deps_indent is not None and indent == child_indent else None
        if merge:
            alias = MERGE_TAIL.match(merge.group(1))
            if alias and alias.group(1) in anchors and not local_tools:
                pins.update(anchors[alias.group(1)])
            continue
        match = DEPS_LINE.match(line)
        if match:
            tail = DEPS_TAIL.match(match.group(2))
            if not tail:
                raise PinError(
                    f"{number}: unreadable dependencies line {line.strip()!r}; write dependencies as a block "
                    "(`dependencies:` then `tools:` / `components:` on their own lines) so check-tool-pins can read it"
                )
            sigil, name = tail.groups()
            pins, local_tools, child_indent = {}, False, None
            if sigil == "&":
                anchors[name] = pins
            elif sigil == "*":
                if name not in anchors:
                    raise PinError(
                        f"{number}: dependencies alias *{name} does not point at a `dependencies: &{name}` block"
                    )
                pins = dict(anchors[name])
            if resolved is not None and workflow is not None:
                resolved[workflow] = pins
            deps_indent = None if sigil == "*" else len(match.group(1))
            continue
        if deps_indent is None or indent <= deps_indent or not line.lstrip().startswith("tools:"):
            continue
        match = FLOW_LINE.match(line)
        if match or TOOLS_LINE.match(line):
            pins.clear()  # a local `tools:` replaces the whole mapping a merge key brought in
            local_tools = True
        if match:
            for tool, version, at in flow_entries(match.group(2), number):
                pins[tool] = (version, at)
                yield tool, version, at
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


def atmos_resolved(root):
    """`atmos describe workflows` output: {file: {"workflows": {name: {"dependencies": ...}}}}."""
    saved = os.environ.get(DESCRIBE_ENV)
    if saved:
        return json.loads(pathlib.Path(saved).read_text(encoding="utf-8"))
    if not shutil.which("atmos"):
        raise PinError(
            "atmos is not on PATH, so the pins cannot be cross-checked against Atmos's own parse; run this "
            f"under `atmos workflow lint -f lint` (or in the ghcr.io/cloudposse/atmos image), or set {DESCRIBE_ENV} "
            "to a file holding `atmos describe workflows --format json -o all`"
        )
    done = subprocess.run(
        ["atmos", "describe", "workflows", "--format", "json", "-o", "all"],
        cwd=root, capture_output=True, text=True, check=False,
    )
    if done.returncode:
        raise PinError(f"`atmos describe workflows` failed ({done.returncode}): {done.stderr.strip()}")
    return json.loads(done.stdout)


def cross_check(root, resolved):
    """Messages for each workflow whose pins the line scan reads differently from Atmos."""
    scanned = {}
    for path in sorted(root.glob("workflows/*.yaml")):
        per_workflow = {}
        for _ in declarations(path.read_text(encoding="utf-8").splitlines(), per_workflow):
            pass
        scanned[path.name] = per_workflow
    problems = []
    for name in sorted(scanned.keys() | resolved.keys()):
        atmos_workflows = (resolved.get(name) or {}).get("workflows") or {}
        for workflow in sorted(scanned.get(name, {}).keys() | atmos_workflows.keys()):
            read = scanned.get(name, {}).get(workflow, {})
            tools = ((atmos_workflows.get(workflow) or {}).get("dependencies") or {}).get("tools") or {}
            theirs = {short(tool): str(version).removeprefix("v") for tool, version in tools.items()}
            for tool in sorted(read.keys() | theirs.keys()):
                mine = read.get(tool)
                if mine and mine[0] == theirs.get(tool):
                    continue
                seen = f"{mine[0]} (line {mine[1]})" if mine else "no pin"
                problems.append(
                    f"workflows/{name}: workflow {workflow}, tool {tool}: check-tool-pins read {seen} from the "
                    f"file but Atmos resolves {theirs.get(tool, 'no pin')}; an anchor redefined later in the file, "
                    "or an alias or merge key the line scan reads differently from the YAML parser. Write the tools "
                    "under the workflow's own `dependencies:` block, or give each `dependencies: &name` anchor a unique name"
                )
    return problems


def main(argv):
    root = pathlib.Path(argv[1] if len(argv) > 1 else ".").resolve()
    try:
        pins = collect(root)
        problems = cross_check(root, atmos_resolved(root))
    except (PinError, json.JSONDecodeError, OSError) as err:
        print(f"check-tool-pins: {err}", file=sys.stderr)
        return 1
    if problems:
        for problem in problems:
            print(f"check-tool-pins: {problem}", file=sys.stderr)
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
