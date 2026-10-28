#!/usr/bin/env python3
"""Fail a service control policy (aws-scp instance) that could lock out or break an account.

SCPs cannot be planned against AWS before E3e, so this proves offline, from
`atmos describe stacks --process-functions=false --format json` on stdin, for every aws-scp
instance (disabled ones too, which E3e enables):
  - targets: at least one, each an OU read (`!terraform.state aws-organizational-unit/<ou>
    organizational_unit_id`); never the organization root (a read of organization_root_id)
    and no literal id (a literal r-, ou- or account id escapes the OU walk below);
  - the policy document, built as the component's main.tf builds it (or policy_content),
    is valid JSON within AWS's 5,120 characters (whitespace outside strings not counted);
  - a Deny with NotAction, or of every action ("*", "*:*"), carries an aws:RequestedRegion
    or aws:PrincipalArn condition (no quarantine policy by accident), and no condition key
    is a near-miss of one of KNOWN_KEYS (on a missing key a String*Not* test is true, so
    a misspelled aws:RequestedRegion denies in every region);
  - a region deny (a NotAction statement on aws:RequestedRegion) exempts every global
    service in GLOBAL_SERVICES, which are served from us-east-1;
  - a Deny of a security service's disable actions excepts the deploy roles (PRINCIPALS);
  - no target has more than four (AWS allows five per target, FullAWSAccess included);
  - every stack's tags.Account is an aws-account instance (or in UNMATCHED_ACCOUNTS), and
    for its account's OU chain (the parent_id read of aws-account/<account>, an OU's
    parent that of aws-organizational-unit/<ou>):
      - no region deny on the chain denies a region the stack runs in;
      - no Deny on the chain denies an action a component needs in us-east-1 whatever the
        stack's region (US_EAST_1_NEEDS: the Route 53 health-check alarm and its B5 relay,
        DNSSEC keys, query logging, CloudFront log delivery);
      - an account whose stacks all run in eu- regions (B5) is denied every
        RESIDENCY_ACTIONS action in us-east-1.
  A Deny with a non-region condition (a principal exception) is taken as not applying to
  the deploy roles, which is what those conditions are for.
Usage: check-scp-policies.py < describe.json
Exit 0 when clean, 1 on a finding, 2 on unreadable input.
"""

import difflib
import fnmatch
import json
import re
import sys

COMPONENT = "aws-scp"
MAX_CHARS, MAX_PER_TARGET = 5120, 4
READ = re.compile(r"^!terraform\.state\s+(\S+)\s+(\S+)$")
REGION_KEY, PRINCIPAL_KEY = "aws:requestedregion", "aws:principalarn"
KNOWN_KEYS = (REGION_KEY, PRINCIPAL_KEY, "aws:principalaccount", "aws:principalorgid", "aws:sourceaccount")
# Global services a region deny must never deny (their requests carry us-east-1).
GLOBAL_SERVICES = ("iam:*", "sts:*", "organizations:*", "route53:*", "route53domains:*",
                   "cloudfront:*", "acm:*", "wafv2:*", "kms:*", "budgets:*", "ce:*", "cur:*",
                   "support:*", "health:*", "sso:*", "account:*")
SECURITY_SERVICES = ("cloudtrail:", "config:", "guardduty:", "securityhub:", "access-analyzer:")
PRINCIPALS = ("arn:aws:iam::*:role/OrganizationAccountAccessRole",)
CI_APPLY = re.compile(r"^arn:aws:iam::\*:role/[a-z0-9]+-\*-ci-apply$")
# tags.Account values with no aws-account instance, and why no SCP reaches them.
UNMATCHED_ACCOUNTS = {
    "root": "the management account, which SCPs never apply to",
    "fixtures": "stage fixtures, never deployed",
    "local": "the local emulator lanes, never deployed to AWS",
}
US_EAST_1 = "us-east-1"
# Calls (create, refresh, tag, delete) of resources pinned to us-east-1 in component code.
ALARM = ("cloudwatch:PutMetricAlarm", "cloudwatch:DescribeAlarms", "cloudwatch:DeleteAlarms",
         "cloudwatch:ListTagsForResource", "cloudwatch:TagResource", "cloudwatch:UntagResource")
RELAY = ("events:PutRule", "events:DescribeRule", "events:DeleteRule", "events:EnableRule",
         "events:DisableRule", "events:PutTargets", "events:ListTargetsByRule", "events:RemoveTargets",
         "events:ListTagsForResource", "events:TagResource", "events:UntagResource")
KMS_KEY = ("kms:CreateKey", "kms:DescribeKey", "kms:GetPublicKey", "kms:PutKeyPolicy")
QUERY_LOGS = ("logs:CreateLogGroup", "logs:DescribeLogGroups", "logs:PutResourcePolicy",
              "logs:PutRetentionPolicy") + KMS_KEY
LOG_DELIVERY = ("logs:PutDeliverySource", "logs:PutDeliveryDestination", "logs:CreateDelivery",
                "logs:GetDelivery")
US_EAST_1_NEEDS = (
    # (terraform component, predicate on its vars, why, actions)
    ("apigateway", lambda v: v.get("route53_failover_type") and v.get("zone_id"),
     "the health-check alarm (main.tf)", ALARM),
    ("apigateway", lambda v: v.get("route53_failover_type") and v.get("zone_id")
     and v.get("health_check_alarm_relay_regions"), "the B5 alarm relay (health-check-alarm-relay.tf)", RELAY),
    ("dns", lambda v: v.get("dnssec_enabled"), "the DNSSEC signing key", KMS_KEY),
    ("dns", lambda v: any(isinstance(z, dict) and z.get("enable_query_logging")
                          for z in (v.get("zones") or {}).values()), "query logging", QUERY_LOGS),
    ("cloudfront", lambda v: v.get("logging_enabled"), "logging v2 delivery", LOG_DELIVERY),
)
# Data-bearing calls an EU-only account (B5) must not make in us-east-1.
RESIDENCY_ACTIONS = ("events:PutEvents", "events:CreateArchive", "cloudwatch:PutMetricData",
                     "cloudwatch:PutDashboard", "logs:PutLogEvents", "s3:PutObject", "sns:Publish",
                     "sqs:SendMessage", "dynamodb:PutItem")


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


def as_list(value):
    return [value] if isinstance(value, str) else list(value or [])


def condition_keys(st):
    return [key.lower() for keys in (st.get("Condition") or {}).values() for key in keys]


def region_condition(st):
    """(operator, regions) of a statement's aws:RequestedRegion condition, else None."""
    for op, keys in (st.get("Condition") or {}).items():
        for key, values in keys.items():
            if key.lower() == REGION_KEY:
                return op, as_list(values)
    return None


def denies_region(st, region):
    """True when a region statement denies regional (non-exempt) actions in region."""
    cond = region_condition(st)
    if st.get("Effect") != "Deny" or cond is None:
        return False
    op, values = cond
    matched = any(fnmatch.fnmatchcase(region, v) for v in values) if "Like" in op else region in values
    return not matched if "Not" in op else matched


def denies(st, action, region):
    """True when st denies the deploy roles action in region (see the module docstring)."""
    if st.get("Effect") != "Deny" or any(k != REGION_KEY for k in condition_keys(st)):
        return False
    match = any(fnmatch.fnmatchcase(action.lower(), p.lower())
                for p in as_list(st.get("Action") or st.get("NotAction")))
    if match == ("NotAction" in st):
        return False
    return region_condition(st) is None or denies_region(st, region)


def statement_findings(where, st):
    errs, actions = [], as_list(st.get("Action"))
    for key in condition_keys(st):
        near = difflib.get_close_matches(key, KNOWN_KEYS, n=1, cutoff=0.8)
        if key not in KNOWN_KEYS and near:
            errs.append(f"{where}: condition key {key!r} is not {near[0]!r}; on a missing key a "
                        "String*Not* test is true, so the deny would apply everywhere")
    if st.get("Effect") != "Deny":
        return errs
    keys = set(condition_keys(st))
    if ("NotAction" in st or {"*", "*:*"} & set(actions)) and not keys & {REGION_KEY, PRINCIPAL_KEY}:
        errs.append(f"{where}: Deny with NotAction or of every action has no aws:RequestedRegion or "
                    "aws:PrincipalArn condition (it would lock out every principal)")
    cond = region_condition(st)
    if cond is not None and "NotAction" in st:
        missing = [g for g in GLOBAL_SERVICES if g not in as_list(st["NotAction"])]
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
        if not m:
            errs.append(f"{where}: target {t!r} is a literal id; target an OU by its read "
                        "(!terraform.state aws-organizational-unit/<ou> organizational_unit_id), "
                        "never the root, so the account walk sees it")
        elif (m.group(2) == "organization_root_id" or not m.group(1).startswith("aws-organizational-unit/")
              or m.group(2) != "organizational_unit_id"):
            errs.append(f"{where}: target {t!r} is not an OU's organizational_unit_id (never the root)")
    return errs


def parent_of(components, name, var):
    """The OU instance a component's parent_id reads, else None."""
    m = READ.match(str(((components.get(name) or {}).get("vars") or {}).get(var) or ""))
    return m.group(1) if m and m.group(2) == "organizational_unit_id" else None


def terraform(body):
    return (body.get("components") or {}).get("terraform") or {}


def check(stacks):
    errs, per_target, ou_statements = [], {}, {}
    for stack, body in sorted(stacks.items()):
        for name, comp in sorted(terraform(body).items()):
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
                    ou_statements.setdefault((stack, m.group(1)), []).extend((name, st) for st in doc["Statement"])
    for (stack, target), names in sorted(per_target.items()):
        if len(names) > MAX_PER_TARGET:
            errs.append(f"{stack}: {len(names)} SCPs on {target} ({', '.join(names)}); AWS allows "
                        f"{MAX_PER_TARGET + 1} per target, FullAWSAccess included")
    return errs + account_findings(stacks, ou_statements)


def account_chains(stacks, ou_statements):
    """{account: (org stack, [(policy instance, statement)] on its OU chain)}."""
    chains = {}
    for org_stack, body in sorted(stacks.items()):
        components = terraform(body)
        for name, comp in sorted(components.items()):
            if not name.startswith("aws-account/") or (comp.get("metadata") or {}).get("type") == "abstract":
                continue
            ous, ou = [], parent_of(components, name, "parent_id")
            while ou and ou not in ous:
                ous.append(ou)
                ou = parent_of(components, ou, "parent_id")
            chains[name.split("/", 1)[1]] = (org_stack, [p for o in ous for p in ou_statements.get((org_stack, o), [])])
    return chains


def account_findings(stacks, ou_statements):
    """Stacks whose account's OU chain denies what they run or need (see the docstring)."""
    errs, chains, regions_of = [], account_chains(stacks, ou_statements), {}
    for stack, body in sorted(stacks.items()):
        comps = terraform(body)
        accounts = {((c.get("vars") or {}).get("tags") or {}).get("Account") for c in comps.values()} - {None}
        if not accounts:
            errs.append(f"{stack}: no component sets tags.Account, so no SCP check reaches it")
        regions = {(c.get("vars") or {}).get("region") for c in comps.values()} - {None}
        for acct in sorted(accounts):
            if acct not in chains:
                if acct not in UNMATCHED_ACCOUNTS:
                    errs.append(f"{stack}: tags.Account {acct!r} is no aws-account instance and not in "
                                "UNMATCHED_ACCOUNTS, so no SCP check reaches it")
                continue
            org_stack, policies = chains[acct]
            regions_of.setdefault(acct, set()).update(regions)
            for region in sorted(regions):
                errs += [f"{stack}: runs in {region}, which {org_stack} {name} ({st.get('Sid')}) denies to "
                         f"account {acct}" for name, st in policies if denies_region(st, region)]
            for cname, comp in sorted(comps.items()):
                v = comp.get("vars") or {}
                for component, needed, why, actions in US_EAST_1_NEEDS:
                    if comp.get("component") != component or not needed(v):
                        continue
                    for name, st in policies:
                        denied = [a for a in actions if denies(st, a, US_EAST_1)]
                        if denied:
                            errs.append(f"{stack} {cname}: {why} needs {', '.join(denied)} in {US_EAST_1}, "
                                        f"which {org_stack} {name} ({st.get('Sid')}) denies to account {acct}")
    for acct, regions in sorted(regions_of.items()):
        if regions and all(r.startswith("eu-") for r in regions):
            org_stack, policies = chains[acct]
            allowed = [a for a in RESIDENCY_ACTIONS if not any(denies(st, a, US_EAST_1) for _, st in policies)]
            if allowed:
                errs.append(f"account {acct}: every stack runs in eu- regions (B5), but no SCP on its OU chain "
                            f"denies {', '.join(allowed)} in {US_EAST_1}")
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
        count = sum(1 for b in stacks.values() for c in terraform(b).values()
                    if c.get("component") == COMPONENT and (c.get("metadata") or {}).get("type") != "abstract")
        print(f"check-scp-policies: {count} SCP instance(s): OU targets only, valid and within limits, "
              "broad denies conditioned, global services exempt, deploy roles excepted, every stack's "
              "account known, no stack in a denied region or denied a us-east-1 need, EU accounts kept "
              "out of us-east-1")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
