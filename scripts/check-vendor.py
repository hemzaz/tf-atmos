#!/usr/bin/env python3
"""Fail a vendored component (QE1) that does not match its vendor.yaml pin or was edited in place.

Offline: each source pins an exact cloudposse-terraform-components tag via ?ref={{ .Version }}
into one components/terraform/<name> (or a statement catalog into stacks/catalog/<name>/catalog);
a Cloud Posse mixins source (mixins.git//src/mixins, named <component>-mixins) adds the files it
names to its component's target and no other, and no two sources of a target write one file;
vendor.lock.yaml holds a receipt per source and no other;
each receipt file (a regular file at a relative path inside the target) is on disk with its
sha256; nothing else is in the target (no extra file, symlink or empty directory) but
.terraform.lock.hcl and *_override.tf. Atmos 1.229's receipt omits the version (`atmos vendor
verify` passes a changed pin), so --repull pulls the manifest into a scratch dir and fails a file
that differs from the receipt or a target the pull or the receipt lacks.
Usage: check-vendor.py [--list | --repull]   (--list prints the vendored dirs). No vendor.yaml:
exit 0. Exit 1 on a finding, 2 on a usage or tool error or (--list) a bad vendor.yaml.
YAML is read with yq (mikefarah v4).
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
# Cloud Posse's providers/verification mixins (the account-map-less providers.tf and friends),
# vendored into a component's own target beside its src: the component excludes the file the
# mixin replaces (excluded_paths), and the mixin source names its files in included_paths.
MIXIN_SOURCE = re.compile(r"^github\.com/cloudposse-terraform-components/mixins\.git//src/mixins"
                          r"\?ref=\{\{ ?\.Version ?\}\}$")
MIXIN_SUFFIX = "-mixins"
# A component's src into components/terraform/<name>, or a Cloud Posse statement catalog that a
# stack !includes (aws-scp's catalog/) into stacks/catalog/<name>/catalog: atmos.yaml stacks
# included_paths is orgs/** only, so its files are never read as stack manifests.
TARGET = re.compile(r"^(components/terraform/[a-z0-9][a-z0-9-]*|stacks/catalog/[a-z0-9][a-z0-9-]*/catalog)$")
HOUSE_FILES = (".terraform.lock.hcl", "*_override.tf")
# Never committed: Terraform's working dir and the files Atmos writes before a run.
IGNORED = {".terraform", "backend.tf.json", "providers_override.tf.json"}
# The scratch pull's atmos.yaml (JSON is YAML); vendor.yaml and vendor.lock.yaml are the defaults.
PULL_CONFIG = {"base_path": ".", "components": {"terraform": {"base_path": "components/terraform"}},
               "stacks": {"base_path": "stacks", "included_paths": ["**/*.yaml"], "name_pattern": "{stage}"}}
PULL_TIMEOUT = 600  # seconds for the whole re-pull


class ToolError(Exception):
    """A missing tool, a timeout or an unreadable input: exit 2."""


def load_yaml(path):
    try:
        out = subprocess.run(["yq", "-o=json", ".", path], capture_output=True, text=True, check=False, timeout=60)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ToolError(f"cannot run yq: {exc}") from exc
    if out.returncode != 0:
        raise ToolError(f"yq cannot read {path}: {out.stderr.strip()}")
    return json.loads(out.stdout or "null") or {}


def sources(manifest):
    return (manifest.get("spec") or {}).get("sources") or []


def receipts(lock):
    """{(source name, target): receipt}."""
    return {(a.get("name"), a.get("target")): a for a in ((lock or {}).get("artifacts") or {}).values()}


def is_mixin(src):
    return bool(MIXIN_SOURCE.match(str(src.get("source", ""))))


def target_files(have, target, errs):
    """{path: sha256} over every receipt for target; a path two receipts both record is an error."""
    found = {}
    for (_, tgt), receipt in sorted(have.items(), key=lambda kv: str(kv[0])):
        if tgt != target:
            continue
        for rel, digest in files(receipt, target, errs).items():
            if rel in found:
                errs.append(f"{target}/{rel}: written by two vendor sources (one must exclude it)")
            found[rel] = digest
    return found


def files(receipt, target, errs):
    """The receipt's {path: sha256}; an unsafe path or a non-file entry is appended to errs instead."""
    found = {}
    for entry in (receipt or {}).get("files") or []:
        path, kind = str(entry.get("path", "")), entry.get("type", "file")
        if not path or os.path.isabs(path) or ".." in path.split("/") or os.path.normpath(path) != path:
            errs.append(f"{target}: {LOCK} records unsafe path {path!r} (want a plain relative path)")
        elif kind != "file":
            errs.append(f"{target}/{path}: {LOCK} records a {kind!r}; vendored dirs hold regular files only")
        else:
            found[path] = entry.get("sha256")
    return found


def check_manifest(manifest):
    errs = []
    if manifest.get("apiVersion") != "atmos/v1" or manifest.get("kind") != "AtmosVendorConfig":
        errs.append(f"{MANIFEST}: want apiVersion atmos/v1, kind AtmosVendorConfig")
    if (manifest.get("spec") or {}).get("imports"):
        errs.append(f"{MANIFEST}: no spec.imports; declare every source in {MANIFEST}")
    names, targets, mixins = set(), {}, []
    for i, src in enumerate(sources(manifest)):
        name = src.get("component") or f"sources[{i}]"
        if name in names:
            errs.append(f"{name}: declared twice")
        names.add(name)
        if not VERSION.match(str(src.get("version", ""))):
            errs.append(f"{name}: version {src.get('version')!r} is not an exact release tag vX.Y.Z")
        tgt = src.get("targets") or []
        if is_mixin(src):
            mixins.append((name, src, tgt))
            continue
        if not SOURCE.match(str(src.get("source", ""))):
            errs.append(f"{name}: source is not github.com/cloudposse-terraform-components/aws-<x>.git[//dir]"
                        "?ref={{ .Version }} or mixins.git//src/mixins?ref={{ .Version }}")
        if len(tgt) != 1 or not TARGET.match(str(tgt[0])) or tgt[0] in targets:
            errs.append(f"{name}: want one target components/terraform/<name> or stacks/catalog/<name>/catalog"
                        f" no other source uses, got {tgt}")
        targets.update({t: name for t in tgt})
    for name, src, tgt in mixins:
        owner = targets.get(tgt[0]) if len(tgt) == 1 else None
        if owner is None or not str(tgt[0]).startswith("components/terraform/") or name != owner + MIXIN_SUFFIX:
            errs.append(f"{name}: a mixins source targets one components/terraform/<c> another source vendors"
                        f" and is named <c>{MIXIN_SUFFIX}, got {tgt}")
        paths = src.get("included_paths") or []
        if not paths or any(not re.fullmatch(r"[A-Za-z0-9_.-]+\.tf", str(p)) for p in paths):
            errs.append(f"{name}: a mixins source names its files in included_paths (<file>.tf, no glob), got {paths}")
    return errs


def on_disk(root, target):
    """(regular files, symlinks, directories) under root/target, relative to it; symlinks are not followed."""
    base, regular, links, dirs = os.path.join(root, target), [], [], []
    for dirpath, dirnames, filenames in os.walk(base):
        rel = os.path.relpath(dirpath, base)
        names = [n for n in dirnames + filenames if n not in IGNORED]
        dirnames[:] = [d for d in dirnames if d not in IGNORED and not os.path.islink(os.path.join(dirpath, d))]
        for n in names:
            path = os.path.normpath(os.path.join(rel, n))
            full = os.path.join(dirpath, n)
            (links if os.path.islink(full) else dirs if os.path.isdir(full) else regular).append(path)
    return sorted(regular), sorted(links), sorted(dirs)


def check_lock(manifest, lock, root):
    errs, have = [], receipts(lock)
    declared = {(s.get("component"), (s.get("targets") or [None])[0]) for s in sources(manifest)}
    for name, target in sorted(set(have) - declared, key=str):
        errs.append(f"{LOCK}: receipt for {name} -> {target}, which {MANIFEST} does not declare (atmos vendor clean)")
    for name, _ in sorted(declared - set(have), key=str):
        errs.append(f"{name}: no receipt in {LOCK} (atmos vendor pull -c {name})")
    for target in sorted({t for _, t in declared & set(have)}):
        locked = target_files(have, target, errs)
        for rel, digest in sorted(locked.items()):
            path = os.path.join(root, target, rel)
            if os.path.islink(path) or not os.path.isfile(path):
                errs.append(f"{target}/{rel}: in {LOCK} but missing on disk or not a regular file")
            else:
                with open(path, "rb") as fh:
                    if hashlib.sha256(fh.read()).hexdigest() != digest:
                        errs.append(f"{target}/{rel}: edited in place (sha256 differs from {LOCK}); use a *_override.tf")
        regular, links, dirs = on_disk(root, target)
        kept = [r for r in regular if r in locked or any(fnmatch.fnmatch(os.path.basename(r), p) for p in HOUSE_FILES)]
        errs += [f"{target}/{r}: not from the vendor pull; only {', '.join(HOUSE_FILES)} may be added"
                 for r in regular if r not in kept]
        errs += [f"{target}/{r}: a symlink; {LOCK} records regular files only" for r in links]
        errs += [f"{target}/{d}: a directory with no vendored or house file" for d in dirs
                 if not any(k.startswith(d + "/") for k in kept)]
    return errs


def repull(lock):
    """Findings where a fresh pull of the manifest differs from the committed receipt."""
    with tempfile.TemporaryDirectory(prefix="check-vendor-") as scratch:
        # realpath: on macOS $TMPDIR is under the /var symlink, and Atmos rejects a target it
        # resolves outside the base path ("invalid vendor lock target").
        tmp = os.path.realpath(scratch)
        shutil.copy(MANIFEST, os.path.join(tmp, MANIFEST))
        with open(os.path.join(tmp, "atmos.yaml"), "w") as fh:
            json.dump(PULL_CONFIG, fh)
        os.makedirs(os.path.join(tmp, "stacks"))
        cmd = ["atmos", "vendor", "pull", "--everything", "--refresh-lock", "--base-path", tmp,
               "--config", os.path.join(tmp, "atmos.yaml")]
        try:
            # cwd=tmp: Atmos 1.229 resolves the lock target against the working directory.
            out = subprocess.run(cmd, cwd=tmp, capture_output=True, text=True, check=False, timeout=PULL_TIMEOUT)
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise ToolError(f"--repull cannot run atmos: {exc}") from exc
        if out.returncode != 0:
            raise ToolError(f"atmos vendor pull failed:\n{out.stdout}{out.stderr}")
        fresh, have = receipts(load_yaml(os.path.join(tmp, LOCK))), receipts(lock)
    errs = []
    for key in sorted(set(fresh) | set(have), key=str):
        name, target = key
        if key not in fresh or key not in have:
            errs.append(f"{name} -> {target}: in {'the committed ' + LOCK if key in have else 'a fresh pull'} only")
            continue
        pulled, locked = files(fresh[key], target, errs), files(have[key], target, errs)
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
        errs = check_manifest(manifest)
        if "--list" in flags:
            if errs:
                raise ToolError(f"{MANIFEST} is invalid, so no vendored dirs are listed: " + "; ".join(errs))
            print("".join(f"{t}\n" for t in dict.fromkeys(s["targets"][0] for s in sources(manifest))), end="")
            return 0
        lock = load_yaml(LOCK) if os.path.exists(LOCK) else {}
        errs = errs or check_lock(manifest, lock, ".")
        # Atmos refuses to pull a manifest with no sources, so there is nothing to re-pull.
        if not errs and "--repull" in flags and sources(manifest):
            errs = repull(lock)
    except ToolError as exc:
        print(f"check-vendor: {exc}", file=sys.stderr)
        return 2
    for err in errs:
        print(f"check-vendor: {err}")
    if not errs:
        print(f"check-vendor: {len(sources(manifest))} vendor source(s) match {MANIFEST} and {LOCK}")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
