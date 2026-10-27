#!/usr/bin/env python3
"""Fail a vendored component (QE1) that does not match its vendor.yaml pin or was edited in place.

Offline: each source pins an exact cloudposse-terraform-components tag via ?ref={{ .Version }}
into one components/terraform/<name>; vendor.lock.yaml holds a receipt per target and no other;
each receipt file is on disk with its sha256; only .terraform.lock.hcl and *_override.tf are
added. Atmos 1.229's receipt omits the version (`atmos vendor verify` passes a changed pin), so
--repull pulls the manifest into a scratch dir and fails a file that differs from the receipt.
Usage: check-vendor.py [--list | --repull]   (--list prints the vendored dirs). No vendor.yaml:
exit 0. Exit 1 on a finding, 2 on a usage or tool error. YAML is read with yq (mikefarah v4).
"""

import fnmatch
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

MANIFEST, LOCK = "vendor.yaml", "vendor.lock.yaml"
VERSION = re.compile(r"^v?\d+\.\d+\.\d+$")
SOURCE = re.compile(r"^github\.com/cloudposse-terraform-components/aws-[a-z0-9-]+\.git"
                    r"(//[A-Za-z0-9_./-]+)?\?ref=\{\{ ?\.Version ?\}\}$")
TARGET = re.compile(r"^components/terraform/[a-z0-9][a-z0-9-]*$")
HOUSE_FILES = (".terraform.lock.hcl", "*_override.tf")
# Never committed: Terraform's working dir and the files Atmos writes before a run.
IGNORED = {".terraform", "backend.tf.json", "providers_override.tf.json"}
# The scratch pull's atmos.yaml (JSON is YAML); vendor.yaml and vendor.lock.yaml are the defaults.
PULL_CONFIG = {"base_path": ".", "components": {"terraform": {"base_path": "components/terraform"}},
               "stacks": {"base_path": "stacks", "included_paths": ["**/*.yaml"], "name_pattern": "{stage}"}}


class ToolError(Exception):
    """A missing tool or an unreadable input: exit 2."""


def load_yaml(path):
    try:
        out = subprocess.run(["yq", "-o=json", ".", path], capture_output=True, text=True, check=False)
    except OSError as exc:
        raise ToolError(f"cannot run yq: {exc}") from exc
    if out.returncode != 0:
        raise ToolError(f"yq cannot read {path}: {out.stderr.strip()}")
    return json.loads(out.stdout or "null") or {}


def sources(manifest):
    return (manifest.get("spec") or {}).get("sources") or []


def receipts(lock):
    return {a.get("target"): a for a in ((lock or {}).get("artifacts") or {}).values()}


def files(receipt):
    return {f["path"]: f.get("sha256") for f in (receipt or {}).get("files") or [] if f.get("type", "file") == "file"}


def check_manifest(manifest):
    errs = []
    if manifest.get("apiVersion") != "atmos/v1" or manifest.get("kind") != "AtmosVendorConfig":
        errs.append(f"{MANIFEST}: want apiVersion atmos/v1, kind AtmosVendorConfig")
    if (manifest.get("spec") or {}).get("imports"):
        errs.append(f"{MANIFEST}: no spec.imports; declare every source in {MANIFEST}")
    names, targets = set(), set()
    for i, src in enumerate(sources(manifest)):
        name = src.get("component") or f"sources[{i}]"
        if name in names:
            errs.append(f"{name}: declared twice")
        names.add(name)
        if not VERSION.match(str(src.get("version", ""))):
            errs.append(f"{name}: version {src.get('version')!r} is not an exact release tag vX.Y.Z")
        if not SOURCE.match(str(src.get("source", ""))):
            errs.append(f"{name}: source is not github.com/cloudposse-terraform-components/aws-<x>.git[//dir]?ref={{{{ .Version }}}}")
        tgt = src.get("targets") or []
        if len(tgt) != 1 or not TARGET.match(str(tgt[0])) or tgt[0] in targets:
            errs.append(f"{name}: want one target components/terraform/<name> no other source uses, got {tgt}")
        targets.update(tgt)
    return errs


def on_disk(root, target):
    """Committable files under root/target, relative to it."""
    base, found = os.path.join(root, target), []
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in IGNORED]
        found += [os.path.relpath(os.path.join(dirpath, f), base) for f in filenames if f not in IGNORED]
    return sorted(found)


def check_lock(manifest, lock, root):
    errs, have = [], receipts(lock)
    declared = {(s.get("targets") or [None])[0]: s.get("component") for s in sources(manifest)}
    for target in sorted(set(have) - set(declared)):
        errs.append(f"{LOCK}: receipt for {target}, which {MANIFEST} does not declare (atmos vendor clean)")
    for target, name in declared.items():
        if target not in have:
            errs.append(f"{name}: no receipt in {LOCK} (atmos vendor pull -c {name})")
            continue
        locked = files(have[target])
        for rel, digest in sorted(locked.items()):
            path = os.path.join(root, target, rel)
            if not os.path.isfile(path):
                errs.append(f"{target}/{rel}: in {LOCK} but missing on disk")
            else:
                with open(path, "rb") as fh:
                    if hashlib.sha256(fh.read()).hexdigest() != digest:
                        errs.append(f"{target}/{rel}: edited in place (sha256 differs from {LOCK}); use a *_override.tf")
        for rel in on_disk(root, target):
            if rel not in locked and not any(fnmatch.fnmatch(os.path.basename(rel), p) for p in HOUSE_FILES):
                errs.append(f"{target}/{rel}: not from the vendor pull; only {', '.join(HOUSE_FILES)} may be added")
    return errs


def repull(lock):
    """Findings where a fresh pull of the manifest differs from the committed receipt."""
    with tempfile.TemporaryDirectory(prefix="check-vendor-") as tmp:
        shutil.copy(MANIFEST, os.path.join(tmp, MANIFEST))
        with open(os.path.join(tmp, "atmos.yaml"), "w") as fh:
            json.dump(PULL_CONFIG, fh)
        os.makedirs(os.path.join(tmp, "stacks"))
        cmd = ["atmos", "vendor", "pull", "--everything", "--refresh-lock", "--base-path", tmp,
               "--config", os.path.join(tmp, "atmos.yaml")]
        try:
            out = subprocess.run(cmd, capture_output=True, text=True, check=False)
        except OSError as exc:
            raise ToolError(f"--repull cannot run atmos: {exc}") from exc
        if out.returncode != 0:
            raise ToolError(f"atmos vendor pull failed:\n{out.stdout}{out.stderr}")
        fresh, have = receipts(load_yaml(os.path.join(tmp, LOCK))), receipts(lock)
    errs = []
    for target, art in sorted(fresh.items()):
        pulled, locked = files(art), files(have.get(target))
        errs += [f"{target}/{rel}: differs from a fresh pull of its pinned version"
                 for rel in sorted(set(pulled) | set(locked)) if pulled.get(rel) != locked.get(rel)]
    return errs


def main(argv):
    flags = set(argv[1:])
    if len(argv) > 2 or not flags <= {"--list", "--repull"}:
        print("usage: check-vendor.py [--list | --repull]", file=sys.stderr)
        return 2
    if not os.path.exists(MANIFEST):
        if "--list" not in flags:
            print(f"check-vendor: no {MANIFEST}, nothing is vendored")
        return 0
    try:
        manifest = load_yaml(MANIFEST)
        if "--list" in flags:
            print("".join(f"{t}\n" for s in sources(manifest) for t in (s.get("targets") or [])[:1]), end="")
            return 0
        lock = load_yaml(LOCK) if os.path.exists(LOCK) else {}
        errs = check_manifest(manifest) or check_lock(manifest, lock, ".")
        # Atmos refuses to pull a manifest with no sources, so there is nothing to re-pull.
        if not errs and "--repull" in flags and sources(manifest):
            errs = repull(lock)
    except ToolError as exc:
        print(f"check-vendor: {exc}", file=sys.stderr)
        return 2
    for err in errs:
        print(f"check-vendor: {err}")
    if not errs:
        print(f"check-vendor: {len(sources(manifest))} vendored component(s) match {MANIFEST} and {LOCK}")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
