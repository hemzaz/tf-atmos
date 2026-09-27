#!/usr/bin/env python3
"""Make .checkov.baseline tolerant of checkov's count-index naming.

checkov 3.3.19 names a `count`-guarded singleton either `type.name[0]` or
`type.name` depending on how its directory-wide graph evaluation resolves the
count expression, and that flips with the total size of the scan (PR #225:
`aws_s3_bucket.flow_logs` went unindexed once components/terraform crossed
~570 resources, with no change to vpc). Baseline matching
(checkov/common/output/baseline.py `_is_check_in_baseline`) is an exact string
compare on `resource`, so the flip turns baselined findings into "new" ones.

For every finding this adds the other spelling with the same check_ids:
- `...name[0]` gets a bare `...name` twin;
- a bare `type.name` gets a `[0]` twin when its resource block declares count.
The gate stays exactly as strict: the same checks on the same resource.

Usage: checkov-baseline-index-twins.py <baseline> <components-dir>
"""
import json
import re
import sys
from pathlib import Path

INDEX = re.compile(r"\[0\]$")


def counted_resources(tf_file):
    """Return {"type.name"} for resource blocks in tf_file that declare count."""
    try:
        text = tf_file.read_text()
    except OSError:
        return set()
    counted = set()
    blocks = re.split(r'(?m)^resource\s+"', text)[1:]
    for block in blocks:
        header = re.match(r'([^"]+)"\s+"([^"]+)"', block)
        if header and re.search(r"(?m)^\s*count\s*=", block):
            counted.add(f"{header.group(1)}.{header.group(2)}")
    return counted


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    baseline_path, components = Path(sys.argv[1]), Path(sys.argv[2])
    data = json.loads(baseline_path.read_text())
    added = 0
    for entry in data.get("failed_checks", []):
        counted = counted_resources(components / entry["file"].lstrip("/"))
        by_resource = {f["resource"]: f for f in entry["findings"]}
        for resource, finding in list(by_resource.items()):
            if INDEX.search(resource):
                twin = INDEX.sub("", resource)
            elif resource in counted:
                twin = f"{resource}[0]"
            else:
                continue
            existing = by_resource.setdefault(twin, {"resource": twin, "check_ids": []})
            merged = sorted(set(existing["check_ids"]) | set(finding["check_ids"]))
            if merged != existing["check_ids"]:
                added += 1
                existing["check_ids"] = merged
        entry["findings"] = sorted(by_resource.values(), key=lambda f: f["resource"])
    baseline_path.write_text(json.dumps(data, indent=4))
    print(f"checkov baseline: {added} count-index twin entries added")


if __name__ == "__main__":
    main()
