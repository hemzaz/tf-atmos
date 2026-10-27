#!/usr/bin/env python3
"""Fail a service control policy (aws-scp instance) that could lock out or break an account.

SCPs cannot be planned against AWS before E3e, so this proves offline, from
`atmos describe stacks --process-functions=false --format json` on stdin, for every aws-scp
instance (disabled ones too, which E3e enables):
  - targets: at least one, each an OU read (`!terraform.state aws-organizational-unit/<ou>
    organizational_unit_id`) or a literal ou-/account id; never the organization root
    (a literal r-, or a read of organization_root_id);
  - the policy document, built as the component's main.tf builds it (or policy_content),
    is valid JSON within AWS's 5,120 characters (whitespace outside strings not counted);
  - a Deny of every action ("*") carries a condition (no quarantine policy by accident);
  - a region deny (a NotAction statement on aws:RequestedRegion) exempts every global
    service in GLOBAL_SERVICES, which are served from us-east-1;
  - a Deny of a security service's disable actions excepts the deploy roles (PRINCIPALS);
  - no target has more than four (AWS allows five per target, FullAWSAccess included);
  - no stack runs in a region a region deny of its account's OU, or of an ancestor OU,
    denies: the account is the stack's tags.Account, its OU the parent_id read of
    aws-account/<account>, an OU's parent that of aws-organizational-unit/<ou>.
Usage: check-scp-policies.py < describe.json
Exit 0 when clean, 1 on a finding, 2 on unreadable input.
"""

import fnmatch
import json
import re
import sys

COMPONENT = "aws-scp"
MAX_CHARS, MAX_PER_TARGET = 5120, 4
READ = re.compile(r"^!terraform\.state\s+(\S+)\s+(\S+)$")
LITERAL = re.compile(r"^(ou-[0-9a-z]{4,32}-[0-9a-z]{8,32}|\d{12})$")
REGION_KEY = "aws:requestedregion"
# Global services a region deny must never deny (their requests carry us-east-1).
GLOBAL_SERVICES = ("iam:*", "sts:*", "organizations:*", "route53:*", "route53domains:*",
                   "cloudfront:*", "acm:*", "wafv2:*", "kms:*", "budgets:*", "ce:*", "cur:*",
                   "support:*", "health:*", "sso:*", "account:*")
SECURITY_SERVICES = ("cloudtrail:", "config:", "guardduty:", "securityhub:", "access-analyzer:")
PRINCIPALS = ("arn:aws:iam::*:role/OrganizationAccountAccessRole",)
CI_APPLY = re.compile(r"^arn:aws:iam::\*:role/[a-z0-9]+-\*-ci-apply$")


def policy_document(v):
    """The JSON the component sends to AWS: main.tf's generated_policy, or policy_content."""
    if v.get("policy_content"):
        return json.loads(v["policy_content"])
    statements = []
    for s in v.get("policy_statements") or []:
        st = {"Effect": s.get("effect")}
        for key, out in (("resources", "Resource"), ("not_resources", "NotResource"),
                         ("actions", "Action"), ("not_actions", "NotAction")):
            if s.get(key):
                st[out] = s[key]
        if s.get("sid"):
            st["Sid"] = s["sid"]
        conds = {}
        for c in s.get("conditions") or []:
            conds.setdefault(c["test"], {})[c["variable"]] = c["values"]
        if conds:
            st["Condition"] = conds
        statements.append(st)
    return {"Version": "2012-10-17", "Statement": statements}


def region_condition(st):
    """(operator, regions) of a statement's aws:RequestedRegion condition, else None."""
    for op, keys in (st.get("Condition") or {}).items():
        for key, values in keys.items():
            if key.lower() == REGION_KEY:
                return op, values
    return None


def denies_region(st, region):
    """True when a region statement denies regional (non-exempt) actions in region."""
    cond = region_condition(st)
    if st.get("Effect") != "Deny" or cond is None:
        return False
    op, values = cond
    matched = any(fnmatch.fnmatchcase(region, v) for v in values) if "Like" in op else region in values
    return not matched if "Not" in op else matched


def statement_findings(where, st):
    errs, actions = [], st.get("Action") or []
    if st.get("Effect") != "Deny":
        return errs
    if "*" in actions and not st.get("Condition"):
        errs.append(f"{where}: Deny of every action with no condition (it would lock out every principal)")
    cond = region_condition(st)
    if cond is not None and "NotAction" in st:
        missing = [g for g in GLOBAL_SERVICES if g not in st["NotAction"]]
        if missing:
            errs.append(f"{where}: region deny does not exempt global service(s) {', '.join(missing)}")
    if cond is None and any(a.startswith(SECURITY_SERVICES) for a in actions):
        allowed = ((st.get("Condition") or {}).get("ArnNotLike") or {}).get("aws:PrincipalArn") or []
        if not (all(p in allowed for p in PRINCIPALS) and any(CI_APPLY.match(p) for p in allowed)):
            errs.append(f"{where}: denies security-service actions without the ArnNotLike aws:PrincipalArn "
                        f"exception for <tenant>-*-ci-apply and {', '.join(PRINCIPALS)}")
    return errs


def target_findings(where, targets):
    if not targets:
        return [f"{where}: no target_ids (attach to an OU, never the organization root)"]
    errs = []
    for t in targets:
        m = READ.match(str(t))
        if m and (m.group(2) == "organization_root_id" or not m.group(1).startswith("aws-organizational-unit/")
                  or m.group(2) != "organizational_unit_id"):
            errs.append(f"{where}: target {t!r} is not an OU's organizational_unit_id (never the root)")
        elif not m and not LITERAL.match(str(t)):
            errs.append(f"{where}: target {t!r} is not an OU or account id (r- roots are refused)")
    return errs


def parent_of(components, name, var):
    """The OU instance a component's parent_id reads, else None."""
    m = READ.match(str(((components.get(name) or {}).get("vars") or {}).get(var) or ""))
    return m.group(1) if m and m.group(2) == "organizational_unit_id" else None


def check(stacks):
    errs, per_target, region_policies = [], {}, {}
    for stack, body in sorted(stacks.items()):
        components = (body.get("components") or {}).get("terraform") or {}
        for name, comp in sorted(components.items()):
            meta = comp.get("metadata") or {}
            if comp.get("component") != COMPONENT or meta.get("type") == "abstract":
                continue
            where, v = f"{stack} {name}", comp.get("vars") or {}
            targets = v.get("target_ids") or ([v["target_id"]] if v.get("target_id") else [])
            errs += target_findings(where, targets)
            try:
                doc = policy_document(v)
            except (ValueError, KeyError, TypeError) as exc:
                errs.append(f"{where}: policy is not valid JSON ({exc})")
                continue
            size = len(json.dumps(doc, separators=(",", ":")))
            if size > MAX_CHARS:
                errs.append(f"{where}: policy is {size} characters, over AWS's {MAX_CHARS}")
            for i, st in enumerate(doc["Statement"]):
                errs += statement_findings(f"{where} statement {st.get('Sid', i)}", st)
            for t in targets:
                per_target.setdefault((stack, str(t)), []).append(name)
                m = READ.match(str(t))
                if m:
                    region_policies.setdefault((stack, m.group(1)), []).extend(
                        (name, st) for st in doc["Statement"] if region_condition(st))
    for (stack, target), names in sorted(per_target.items()):
        if len(names) > MAX_PER_TARGET:
            errs.append(f"{stack}: {len(names)} SCPs on {target} ({', '.join(names)}); AWS allows "
                        f"{MAX_PER_TARGET + 1} per target, FullAWSAccess included")
    errs += region_findings(stacks, region_policies)
    return errs


def region_findings(stacks, region_policies):
    """Stacks in a region that a region deny on their account's OU (or an ancestor) denies."""
    errs = []
    for org_stack, body in sorted(stacks.items()):
        components = (body.get("components") or {}).get("terraform") or {}
        for acct in sorted(n.split("/", 1)[1] for n in components if n.startswith("aws-account/")):
            ous, ou = [], parent_of(components, f"aws-account/{acct}", "parent_id")
            while ou and ou not in ous:
                ous.append(ou)
                ou = parent_of(components, ou, "parent_id")
            policies = [p for o in ous for p in region_policies.get((org_stack, o), [])]
            for stack, sbody in sorted(stacks.items()):
                comps = ((sbody.get("components") or {}).get("terraform") or {}).values()
                if not any(((c.get("vars") or {}).get("tags") or {}).get("Account") == acct for c in comps):
                    continue
                for region in sorted({(c.get("vars") or {}).get("region") for c in comps} - {None}):
                    for name, st in policies:
                        if denies_region(st, region):
                            errs.append(f"{stack}: runs in {region}, which {org_stack} {name} "
                                        f"({st.get('Sid')}) denies to account {acct}")
    return errs


def main(argv):
    if argv:
        print("usage: check-scp-policies.py < <atmos describe stacks --process-functions=false --format json>",
              file=sys.stderr)
        return 2
    try:
        stacks = json.load(sys.stdin)
    except ValueError as exc:
        print(f"check-scp-policies: cannot read the describe output: {exc}", file=sys.stderr)
        return 2
    errs = check(stacks)
    for err in errs:
        print(f"check-scp-policies: {err}")
    if not errs:
        count = sum(1 for b in stacks.values() for c in ((b.get("components") or {}).get("terraform") or {}).values()
                    if c.get("component") == COMPONENT and (c.get("metadata") or {}).get("type") != "abstract")
        print(f"check-scp-policies: {count} SCP instance(s): OU targets only, valid and within limits, "
              "global services exempt, deploy roles excepted, no stack in a denied region")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
