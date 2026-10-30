#!/usr/bin/env python3
"""Checkov gate for findings in vendored code that cannot carry an inline skip.

A vendored component (vendor.yaml) cannot be edited, so `#checkov:skip` is not available
there, and checkov has no per-path check skip. ALLOWLIST below holds one
(file regex, check ID, reason) per accepted finding: the regex is matched in full against
checkov's file_path (relative to components/terraform, e.g. /aws-dns-primary/main.tf; a
module's finding names the module's own file). No baselines: an entry names one file and
one check, with its reason, and is reviewed like code.

Usage:
  check-checkov-allowlist.py gate RESULTS_JSON
      Fail (exit 1) on a failed check that is neither LOW/MEDIUM (checkov's
      --soft-fail-on LOW,MEDIUM) nor allowlisted -- without a Prisma API key checkov
      knows no severities, so every failed check counts, as with --hard-fail-on -- and
      on an allowlist entry that matched no finding (stale: drop it).
  check-checkov-allowlist.py drop-sarif SARIF...
      Drop the allowlisted results from published SARIF, as inline skips are dropped.
Exit 2 on an unreadable input.
"""

import json
import re
import sys

TF_1 = "Cloud Posse pins this registry module to an exact version in vendored code, not house code"
DNSSEC = "signed and query-logged by the house dns external_zones mode, E6b"
ALLOWLIST = (
    # aws-dns-primary (vendor.yaml): the service domain's zone.
    (r"/aws-dns-primary/main\.tf", "CKV2_AWS_38", DNSSEC),
    (r"/aws-dns-primary/main\.tf", "CKV2_AWS_39", DNSSEC),
    (r"/aws-dns-primary/acm\.tf", "CKV_TF_1", TF_1),
    (r"/aws-dns-primary/context\.tf", "CKV_TF_1", TF_1),
    # aws-dns-delegated (vendor.yaml): a stage's delegated subdomain.
    (r"/aws-dns-delegated/main\.tf", "CKV2_AWS_39", DNSSEC),
    (r"/aws-dns-delegated/main\.tf", "CKV_TF_1", TF_1),
    (r"/aws-dns-delegated/acm\.tf", "CKV_TF_1", TF_1),
    (r"/aws-dns-delegated/acm\.tf", "CKV2_AWS_34",
     "Cloud Posse's /acm/<domain> parameter holds the ACM certificate ARN, an identifier and "
     "not a secret, as a String"),
    (r"/aws-dns-delegated/context\.tf", "CKV_TF_1", TF_1),
    (r"/aws-dns-delegated/remote-state\.tf", "CKV_TF_1", TF_1),
    # aws-account-settings (vendor.yaml): each account's account-level settings (E3d).
    (r"/aws-account-settings/context\.tf", "CKV_TF_1", TF_1),
    # account-map's iam-roles module (vendor.yaml), reached through the dns providers.tf.
    (r"/account-map/modules/iam-roles/context\.tf", "CKV_TF_1", TF_1),
    (r"/account-map/modules/iam-roles/main\.tf", "CKV_TF_1", TF_1),
)
SOFT = {"LOW", "MEDIUM"}


def allowed(path, check_id, allowlist=ALLOWLIST):
    """The index of the entry that accepts this finding, or None."""
    for i, (pattern, cid, _) in enumerate(allowlist):
        if cid == check_id and re.fullmatch(pattern, path):
            return i
    return None


def failed_checks(data):
    """checkov's failed checks; its JSON is one report, a list of them, or a flat summary."""
    reports = data if isinstance(data, list) else [data]
    return [c for r in reports for c in (r.get("results") or {}).get("failed_checks", [])]


def gate(data, allowlist=ALLOWLIST):
    """(findings, stale entries) as printable lines; both empty means pass."""
    findings, used = [], set()
    for c in failed_checks(data):
        path, cid = c.get("file_path", ""), c.get("check_id", "")
        i = allowed(path, cid, allowlist)
        if i is not None:
            used.add(i)
        elif (c.get("severity") or "").upper() not in SOFT:
            findings.append(f"{cid} {path} {c.get('resource')}: {c.get('check_name')}")
    stale = [f"{p} {cid} ({why})" for i, (p, cid, why) in enumerate(allowlist) if i not in used]
    return findings, stale


def sarif_path(result):
    """A SARIF result's file as checkov's JSON names it: /<component>/<file>."""
    loc = (result.get("locations") or [{}])[0].get("physicalLocation") or {}
    uri = loc.get("artifactLocation", {}).get("uri", "")
    return "/" + uri.lstrip("/").removeprefix("components/terraform/")


def drop_sarif(sarif, allowlist=ALLOWLIST):
    """Drop allowlisted results in place; the number dropped."""
    dropped = 0
    for run in sarif.get("runs", []):
        results = run.get("results") or []
        kept = [r for r in results if allowed(sarif_path(r), r.get("ruleId", ""), allowlist) is None]
        dropped += len(results) - len(kept)
        run["results"] = kept
    return dropped


def load(path):
    try:
        with open(path) as fh:
            return json.load(fh)
    except (OSError, ValueError) as exc:
        print(f"check-checkov-allowlist: cannot read {path}: {exc}", file=sys.stderr)
        sys.exit(2)


def main(argv):
    if len(argv) == 3 and argv[1] == "gate":
        findings, stale = gate(load(argv[2]))
        for f in findings:
            print(f"FAIL: {f}")
        for s in stale:
            print(f"FAIL: allowlist entry matched no finding (stale; drop it): {s}")
        if findings or stale:
            return 1
        print(f"checkov gate: no finding outside the allowlist; {len(ALLOWLIST)} allowlist entries in use")
        return 0
    if len(argv) >= 3 and argv[1] == "drop-sarif":
        for path in argv[2:]:
            sarif = load(path)
            n = drop_sarif(sarif)
            with open(path, "w") as fh:
                json.dump(sarif, fh)
            print(f"{path}: dropped {n} allowlisted result(s)")
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
