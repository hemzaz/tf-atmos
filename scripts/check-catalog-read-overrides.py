#!/usr/bin/env python3
"""Fail when a stack file overrides a state read that a catalog instance file sets.

Wave C1 moves instance wiring (vars that read other instances with
!terraform.state / !terraform.output) out of stacks/orgs/** into
stacks/catalog/<c>/<i>[-flavor].yaml. A read in a catalog instance must then
never be replaced by a stack: the stack's value would win in describe, but the
read stays in the import chain, so the shape no longer says which value the
instance gets (and whether Atmos still resolves the read). For each real
(non-abstract) component instance in a catalog file, this collects the paths
that carry a read and fails when a stack file under stacks/orgs/ sets, for the
same component key, that path or a parent of it to a non-map value (a map
parent deep-merges and leaves the read in place; a list or scalar replaces it).

yq (mikefarah v4, in lint.yaml's tools) parses the YAML: it keeps the custom
tags the stdlib has no parser for. Abstract instances are skipped: a stack
sets their values through its own instance, which this does not follow.

Usage: check-catalog-read-overrides.py [STACKS_DIR]   (default: stacks)
Exit 0 when clean, 1 on an override.
"""

import json
import pathlib
import subprocess
import sys

READ_TAGS = ("!terraform.state", "!terraform.output")
READS_EXPR = ("{\"file\": filename, \"doc\": ., \"reads\": [.. | select("
              + " or ".join(f'tag == "{tag}"' for tag in READ_TAGS) + ") | path]}")
DOC_EXPR = '{"file": filename, "doc": .}'


def load(files, expression):
    """One JSON object per YAML document of files, as yq evaluates expression on it."""
    if not files:
        return []
    out = subprocess.run(["yq", "-o", "json", "-I0", expression, *map(str, files)],
                         capture_output=True, text=True, check=True).stdout
    return [json.loads(line) for line in out.splitlines() if line.strip()]


def terraform_components(doc):
    components = (doc or {}).get("components") if isinstance(doc, dict) else None
    terraform = (components or {}).get("terraform") if isinstance(components, dict) else None
    return terraform if isinstance(terraform, dict) else {}


def instance_reads(doc, read_paths):
    """(component key, path inside the component) for each read of a non-abstract instance."""
    components = terraform_components(doc)
    for path in read_paths:
        if len(path) < 4 or path[:2] != ["components", "terraform"]:
            continue
        block = components.get(path[2])
        if not isinstance(block, dict) or (block.get("metadata") or {}).get("type") == "abstract":
            continue
        yield path[2], tuple(path[3:])


def overridden(block, path):
    """The prefix of path that block (a stack's component block) sets over the read, or None."""
    node = block
    for depth, step in enumerate(path, 1):
        if not isinstance(node, dict) or step not in node:
            return None
        node = node[step]
        if depth == len(path) or not isinstance(node, dict):
            return path[:depth]
    return None


def dotted(path):
    return "".join(f"[{step}]" if isinstance(step, int) else f".{step}" for step in path).lstrip(".")


def violations(catalog_docs, stack_docs):
    """(stack file, component, set path, read path, catalog file) for each overridden read."""
    reads = [(entry["file"], component, path)
             for entry in catalog_docs for component, path in instance_reads(entry["doc"], entry["reads"])]
    for entry in stack_docs:
        components = terraform_components(entry["doc"])
        for catalog_file, component, path in reads:
            hit = overridden(components.get(component), path)
            if hit is not None:
                yield entry["file"], component, hit, path, catalog_file


def main(argv):
    root = pathlib.Path(argv[0] if argv else "stacks")
    catalog = sorted((root / "catalog").rglob("*.yaml"))
    stacks = sorted((root / "orgs").rglob("*.yaml"))
    found = 0
    for stack_file, component, hit, path, catalog_file in violations(load(catalog, READS_EXPR),
                                                                      load(stacks, DOC_EXPR)):
        print(f"{stack_file}: {component} sets {dotted(hit)} over the state read at {dotted(path)} "
              f"in {catalog_file}")
        found += 1
    if found:
        print(f"{found} catalog state read(s) overridden by a stack: set the value in the catalog "
              "instance file (or a -<flavor> file), never over the read")
        return 1
    print(f"no stack overrides a catalog instance's state read ({len(catalog)} catalog, {len(stacks)} stack files)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
