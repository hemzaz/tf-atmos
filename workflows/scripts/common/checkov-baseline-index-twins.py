#!/usr/bin/env python3
"""Make .checkov.baseline tolerant of checkov's count-index naming.

checkov 3.3.19 names a `count`-guarded singleton either `type.name[0]` or
`type.name` depending on how its directory-wide graph evaluation resolves the
count expression, and that flips with the total size of the scan (PR #225:
`aws_s3_bucket.flow_logs` went unindexed once components/terraform crossed
~570 resources, with no change to vpc). Baseline matching
(checkov/common/output/baseline.py `_is_check_in_baseline`) is an exact string
compare on `resource` + check_id, so the flip turns baselined findings into
"new" ones.

For every finding this adds the other spelling with the same check_ids:
- `...name[0]` gets a bare `...name` twin;
- a bare `[module.x.]type.name` gets a `[0]` twin when the `type.name` resource
  block in the entry's file declares a top-level `count`.
Only the index suffix differs, so the gate checks the same resources for the
same check_ids. (checkov ignores `file` when matching, as it always has for
every baseline entry: a twin name also matches a same-named resource in
another component.)

Usage: checkov-baseline-index-twins.py <baseline> <components-dir>
"""
import json
import re
import sys
from pathlib import Path

INDEX = re.compile(r"\[0\]$")
RESOURCE_HEADER = re.compile(r'(?m)^resource\s+"([^"]+)"\s+"([^"]+)"\s*\{')
COUNT = re.compile(r"^\s*count\s*=")


def block_body(text, start):
    """Return the text between the `{` at text[start - 1] and its matching `}`."""
    depth = 1
    in_string = False
    i = start
    while i < len(text) and depth:
        char = text[i]
        if in_string:
            if char == "\\":
                i += 1
            elif char == '"':
                in_string = False
        elif char == '"':
            in_string = True
        elif char == "#" or text.startswith("//", i):
            newline = text.find("\n", i)
            i = len(text) if newline == -1 else newline
            continue
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
        i += 1
    return text[start:i - 1]


def top_level_lines(body):
    """Yield the lines of a block body that sit at nesting depth 0."""
    depth = 0
    for line in body.splitlines():
        if depth == 0:
            yield line
        depth += line.count("{") - line.count("}")


def counted_resources(tf_file):
    """Return {"type.name"} for resource blocks in tf_file with a top-level count."""
    try:
        text = tf_file.read_text()
    except (OSError, UnicodeDecodeError):
        return set()
    counted = set()
    for header in RESOURCE_HEADER.finditer(text):
        body = block_body(text, header.end())
        if any(COUNT.match(line) for line in top_level_lines(body)):
            counted.add(f"{header.group(1)}.{header.group(2)}")
    return counted


def twin_of(resource, counted):
    """Return the other spelling of resource, or None if it has none."""
    if INDEX.search(resource):
        return INDEX.sub("", resource)
    if ".".join(resource.split(".")[-2:]) in counted:
        return f"{resource}[0]"
    return None


def add_twins(data, components):
    """Add index twins to a parsed baseline in place; return how many were added."""
    added = 0
    for entry in data.get("failed_checks", []):
        counted = counted_resources(components / entry["file"].lstrip("/"))
        by_resource = {}
        for finding in entry["findings"]:
            existing = by_resource.setdefault(finding["resource"], {"resource": finding["resource"], "check_ids": []})
            existing["check_ids"] = sorted(set(existing["check_ids"]) | set(finding["check_ids"]))
        for resource, finding in list(by_resource.items()):
            twin = twin_of(resource, counted)
            if twin is None:
                continue
            existing = by_resource.setdefault(twin, {"resource": twin, "check_ids": []})
            merged = sorted(set(existing["check_ids"]) | set(finding["check_ids"]))
            if merged != existing["check_ids"]:
                added += 1
                existing["check_ids"] = merged
        entry["findings"] = sorted(by_resource.values(), key=lambda f: f["resource"])
    return added


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    baseline_path, components = Path(sys.argv[1]), Path(sys.argv[2])
    data = json.loads(baseline_path.read_text())
    added = add_twins(data, components)
    baseline_path.write_text(json.dumps(data, indent=4))
    print(f"checkov baseline: {added} count-index twin entries added")


if __name__ == "__main__":
    main()
