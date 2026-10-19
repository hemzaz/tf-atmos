#!/usr/bin/env python3
"""Fail when a stack file overrides a state read that a catalog instance file sets.

Instance wiring (vars that read other instances with !terraform.state /
!terraform.output) lives in stacks/catalog/<c>/<i>[-flavor].yaml, not in
stacks/orgs/**. A read in a catalog instance must then
never be replaced by a stack: the stack's value wins in describe, but the read
stays in the import chain, so the shape no longer says which value the instance
gets. For each real (non-abstract) component instance in a catalog file, this
collects the paths that carry a read, and fails when a stack file (stacks/orgs/**
or stacks/mixins/**) sets that path, or a parent of it to a non-map value (a map
parent deep-merges and leaves the read in place; a list, scalar or null replaces
it), through:
  - components.terraform.<same key>, in a file that shares an import chain with
    the catalog file (some stack file imports both, directly or nested), so a
    -<flavor> file's reads are matched only against the stacks that use it;
  - a top-level `overrides:` or `terraform.overrides:` section, whatever the key,
    in a file whose own import chain includes the catalog file (Atmos applies a
    file's overrides to the components of that file and its imports).

Not checked: one catalog file overriding another's read, and a read in an
abstract instance that an inheriting instance or stack overrides (`inherits`).
Atmos still resolves an inherited read that is overridden; keep reads out of
abstracts that a stack overrides (scripts/check-inherited-state-reads.py fails
one whose target its stack lacks).

yq (mikefarah v4, in lint.yaml's and validate-all's tools) parses the YAML: it
keeps the custom tags the stdlib has no parser for, and expands `<<:` merge keys.
An import this cannot resolve (a Go template, a missing file) fails the check.

Usage: check-catalog-read-overrides.py [STACKS_DIR]   (default: stacks)
Exit 0 when clean, 1 on an override, 2 on an unresolvable import.
"""

import json
import os
import pathlib
import subprocess
import sys

READ_TAGS = ("!terraform.state", "!terraform.output")
EXPRESSION = ("explode(.) | {\"file\": filename, \"doc\": ., \"reads\": [.. | select("
              + " or ".join(f'tag == "{tag}"' for tag in READ_TAGS) + ") | path]}")
STACK_DIRS = ("orgs", "mixins")


def norm(path):
    return pathlib.Path(os.path.normpath(path))


def load(files):
    """{file: [(doc, read paths)]} for each YAML document of files."""
    docs = {norm(f): [] for f in files}
    if not files:
        return docs
    out = subprocess.run(["yq", "--yaml-fix-merge-anchor-to-spec", "-o", "json", "-I0", EXPRESSION,
                          *map(str, files)], capture_output=True, text=True, check=True).stdout
    for line in out.splitlines():
        if line.strip():
            entry = json.loads(line)
            docs[norm(entry["file"])].append((entry["doc"], entry["reads"]))
    return docs


def section(doc, *keys):
    """The dict at doc.keys..., or {}."""
    for key in keys:
        doc = doc.get(key) if isinstance(doc, dict) else None
    return doc if isinstance(doc, dict) else {}


def instance_reads(doc, read_paths):
    """(component key, path inside the component) for each read of a non-abstract instance."""
    components = section(doc, "components", "terraform")
    for path in read_paths:
        if len(path) < 4 or path[:2] != ["components", "terraform"]:
            continue
        block = components.get(path[2])
        if not isinstance(block, dict) or section(block, "metadata").get("type") == "abstract":
            continue
        yield path[2], tuple(path[3:])


def overridden(block, path):
    """The prefix of path that block (a stack's component or overrides block) sets over the read, or None."""
    node = block
    for depth, step in enumerate(path, 1):
        if not isinstance(node, dict) or step not in node:
            return None
        node = node[step]
        if depth == len(path) or not isinstance(node, dict):
            return path[:depth]
    return None


def resolve_import(root, file, entry):
    """The files one `import:` entry names (relative to root, or to file for ./ and ../)."""
    name = entry.get("path") if isinstance(entry, dict) else entry
    if not isinstance(name, str) or "{{" in name:
        raise ValueError(f"{file}: cannot resolve import {entry!r}")
    base = file.parent if name.startswith(".") else root
    names = [name] if name.endswith((".yaml", ".yml")) else [name + ".yaml", name + ".yml"]
    found = sorted({norm(p) for n in names for p in base.glob(n)})
    if not found:
        raise ValueError(f"{file}: import {name!r} names no file")
    return found


def closure(root, docs, file, seen=None):
    """file plus every file its imports reach, nested."""
    seen = set() if seen is None else seen
    if file in seen:
        return seen
    seen.add(file)
    for doc, _ in docs.get(file, []):
        for entry in (doc.get("import") or []) if isinstance(doc, dict) else []:
            for target in resolve_import(root, file, entry):
                closure(root, docs, target, seen)
    return seen


def dotted(path):
    return "".join(f"[{step}]" if isinstance(step, int) else f".{step}" for step in path).lstrip(".")


def violations(root, docs, stack_files):
    """Sorted (stack file, what it sets, read path, catalog file) for each overridden read."""
    reads = {}
    for file, entries in docs.items():
        if file not in stack_files:
            reads[file] = [r for doc, paths in entries for r in instance_reads(doc, paths)]
    chains = {file: closure(root, docs, file) for file in stack_files}
    found = set()
    for chain in chains.values():
        for catalog in sorted(chain & {f for f, r in reads.items() if r}):
            for stack in sorted(chain & stack_files):
                for doc, _ in docs.get(stack, []):
                    blocks = [(key, section(doc, "components", "terraform").get(key), path)
                              for key, path in reads[catalog]]
                    if catalog in chains[stack]:
                        blocks += [(label, section(doc, *keys), path) for _, path in reads[catalog]
                                   for label, keys in (("overrides", ("overrides",)),
                                                       ("terraform.overrides", ("terraform", "overrides")))]
                    for owner, block, path in blocks:
                        hit = overridden(block, path)
                        if hit is not None:
                            found.add((str(stack), f"{owner} sets {dotted(hit)}", dotted(path), str(catalog)))
    return sorted(found)


def main(argv):
    root = norm(argv[0] if argv else "stacks")
    stack_files = {norm(p) for d in STACK_DIRS for p in (root / d).rglob("*.y*ml")}
    files = sorted(stack_files | {norm(p) for p in (root / "catalog").rglob("*.y*ml")})
    try:
        found = violations(root, load(files), stack_files)
    except ValueError as error:
        print(error)
        return 2
    for stack, what, path, catalog in found:
        print(f"{stack}: {what} over the state read at {path} in {catalog}")
    if found:
        print(f"{len(found)} catalog state read override(s): set the value in the catalog "
              "instance file (or a -<flavor> file), never over the read")
        return 1
    print(f"no stack overrides a catalog instance's state read ({len(files) - len(stack_files)} catalog, "
          f"{len(stack_files)} stack files)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
