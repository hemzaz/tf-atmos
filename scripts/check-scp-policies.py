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
  - a Deny of a security service's disable actions never mixes two KINDS (CloudTrail/Config,
    the detectors GuardDuty/Security Hub/Inspector, Access Analyzer: their exceptions differ);
    a CloudTrail/Config or Access Analyzer one excepts the deploy roles in every account (a
    <tenant>-*-ci-apply pattern and the SSO_REQUIRED Identity Center sets), and a
    CloudTrail/Config one OrganizationAccountAccessRole on OAAR_TRAIL_OUS (core) and never on
    another OU (owner decision OQ-F); a detector one excepts BREAK_GLASS (AdministratorAccess)
    and, on core, otherwise only roles pinned to the security account
    (settings.account_map.full_account_map.security), including a ci-apply pattern; on any other
    OU nothing else (E5c10: since E5c8 no workload stack manages a detector or hub);
  - an Identity Center (AWSReservedSSO_) principal pattern names one permission set under
    the reserved path role/aws-reserved/sso.amazonaws.com/ (SSO_ROLE), and every role
    exception of a policy (ArnNotLike aws:PrincipalArn, Identity Center's too) is covered by a
    resource of a Deny in that policy of SQUAT_ACTIONS (no one else can create or re-trust a
    role of that name); such a protection of role/aws-reserved/ has no principal exception (only
    Identity Center's service-linked role writes there, and service-linked roles are outside SCPs);
  - per protected role: whoever every protection covering a Deny's role exception exempts (and so
    may create or re-trust that role, then act as it) is exempt from that Deny too, in the account
    the role is pinned to (a principal arn:aws:iam::*:role/X acts in its own account, so only
    those in account A can create a role pinned to A); action names compare case-insensitively;
  - no aws-scp/security-services-* instance is enabled while the stack's aws-identity-center is
    disabled (until Identity Center is applied, OrganizationAccountAccessRole runs the accounts);
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
  A Deny with an aws:Principal* condition (a principal exception) is taken as not applying to
  the deploy roles, which is what those conditions are for; any other condition is taken as
  possibly true, so the Deny applies.
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
KNOWN_KEYS = (REGION_KEY, PRINCIPAL_KEY, "aws:principalaccount", "aws:principalorgid", "aws:principalorgpaths",
              "aws:sourceaccount", "aws:sourcearn", "aws:resourceaccount")
# Global services a region deny must never deny (their requests carry us-east-1).
GLOBAL_SERVICES = ("iam:*", "sts:*", "organizations:*", "route53:*", "route53domains:*",
                   "cloudfront:*", "acm:*", "wafv2:*", "kms:*", "budgets:*", "ce:*", "cur:*",
                   "support:*", "health:*", "sso:*", "account:*")
TRAIL_CONFIG = ("cloudtrail:", "config:")
DETECTORS = ("guardduty:", "securityhub:", "inspector2:")
ANALYZERS = ("access-analyzer:",)
KINDS = (("CloudTrail/Config", TRAIL_CONFIG), ("detector (GuardDuty, Security Hub, Inspector)", DETECTORS),
         ("Access Analyzer", ANALYZERS))
SECURITY_SERVICES = TRAIL_CONFIG + DETECTORS + ANALYZERS
OAAR = "arn:aws:iam::*:role/OrganizationAccountAccessRole"
# The break-glass, the one detector exception in every account.
BREAK_GLASS = "arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*AWSReservedSSO_AdministratorAccess_*"
# OUs whose accounts' trails and recorders OrganizationAccountAccessRole applies (the core
# stacks, OPERATIONS Bootstrap order step 6). Every other OU's trail/Config deny must not except
# it (owner decision OQ-F): workload trails are applied by CI, the Terraform sets and the break-glass.
OAAR_TRAIL_OUS = ("aws-organizational-unit/core",)
IDENTITY_CENTER, SECURITY_SERVICES_SCP = "aws-identity-center", "aws-scp/security-services-"
CI_APPLY = re.compile(r"^arn:aws:iam::(\*|\d{12}):role/[a-z0-9]+-\*-ci-apply$")
ROLE_ARN = re.compile(r"^arn:aws:iam::([^:]*):role/(.+)$")
RESERVED = ":role/aws-reserved/"
# An Identity Center role: one named permission set under the path only Identity Center
# creates in (the * before the name admits the home region's path segment), any hash.
# `<set>_*` is that one set; `<set>-*` also takes its per-backend variants (TerraformApplyAccess-Prod),
# so only an SSO_REQUIRED set may end in `-*`.
SSO_ROLE = re.compile(r"^arn:aws:iam::(?:\*|\d{12}):role/aws-reserved/sso\.amazonaws\.com/\*?"
                      r"AWSReservedSSO_([A-Za-z0-9]+)([_-])\*$")
SSO_REQUIRED = ("AdministratorAccess", "TerraformApplyAccess")
# What a principal needs to squat on, or take over, a role an exception names.
SQUAT_ACTIONS = ("iam:CreateRole", "iam:UpdateAssumeRolePolicy", "iam:PutRolePolicy",
                 "iam:AttachRolePolicy", "iam:DeleteRole")
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
    if st.get("Effect") != "Deny" or any(k.startswith("aws:principal") for k in condition_keys(st)):
        return False
    match = any(fnmatch.fnmatchcase(action.lower(), p.lower())
                for p in as_list(st.get("Action") or st.get("NotAction")))
    if match == ("NotAction" in st):
        return False
    return region_condition(st) is None or denies_region(st, region)


def principal_exceptions(st):
    """The aws:PrincipalArn values of a statement's ArnNotLike condition."""
    keys = (st.get("Condition") or {}).get("ArnNotLike") or {}
    return [v for key, values in keys.items() if key.lower() == PRINCIPAL_KEY for v in as_list(values)]


def account_of(arn):
    """The account of a role ARN pattern ("*" for any), else None."""
    m = ROLE_ARN.match(arn)
    return m.group(1) if m else None


def detector_findings(where, allowed, ous, security_account):
    """A detector Deny's exception: BREAK_GLASS, and on core only the security account's roles."""
    core = [o for o in ous if o in OAAR_TRAIL_OUS]
    if core and len(core) < len(ous):
        return [f"{where}: one detector deny targets {', '.join(sorted(ous))}; {', '.join(OAAR_TRAIL_OUS)} "
                "needs its own policy (its exception keeps the security account's deploy roles)"]
    errs = [] if BREAK_GLASS in allowed else [
        f"{where}: detector deny does not except {BREAK_GLASS} (the break-glass)"]
    others = sorted(set(allowed) - {BREAK_GLASS})
    if not core:
        if others:
            errs.append(f"{where}: detector deny on {', '.join(sorted(ous)) or 'its OU'} excepts "
                        f"{', '.join(others)}; only {BREAK_GLASS} may (E5c10: since E5c8 no workload stack "
                        "manages a detector or hub)")
        return errs
    if not security_account:
        return errs + [f"{where}: detector deny on core, but no settings.account_map.full_account_map.security "
                       "to pin its deploy roles to"]
    unpinned = [p for p in others if account_of(p) != security_account]
    if unpinned:
        errs.append(f"{where}: detector deny on core excepts {', '.join(unpinned)}, not pinned to the security "
                    f"account {security_account} (only its deploy roles run the delegated administrators) "
                    f"nor {BREAK_GLASS}")
    if not any(CI_APPLY.match(p) for p in others if account_of(p) == security_account):
        errs.append(f"{where}: detector deny on core does not except the security account's "
                    f"arn:aws:iam::{security_account}:role/<tenant>-*-ci-apply, which applies the "
                    "delegated administrators")
    return errs


def security_findings(where, st, ous, security_account=None):
    """A Deny of security-service actions: its deploy-role exception, per kind and OU."""
    actions, allowed = as_list(st.get("Action")), principal_exceptions(st)
    kinds = [name for name, prefixes in KINDS if any(a.lower().startswith(prefixes) for a in actions)]
    if len(kinds) > 1:
        return [f"{where}: denies {' and '.join(kinds)} actions in one statement; split it "
                "(DenyTrailConfigTampering, DenyDetectorTampering, DenyAnalyzerTampering): their exceptions differ"]
    if kinds[0] == KINDS[1][0]:
        return detector_findings(where, allowed, ous, security_account)
    trail = kinds[0] == KINDS[0][0]
    every = [p for p in allowed if account_of(p) == "*"]
    sets = {m.group(1) for m in map(SSO_ROLE.match, every) if m}
    errs = []
    if not (any(CI_APPLY.match(p) for p in every) and set(SSO_REQUIRED) <= sets):
        errs.append(f"{where}: denies {kinds[0]} actions without the ArnNotLike aws:PrincipalArn exception for "
                    f"<tenant>-*-ci-apply and the Identity Center sets {', '.join(SSO_REQUIRED)} in every account "
                    "(arn:aws:iam::*:...)")
    core = [o for o in ous if o in OAAR_TRAIL_OUS]
    if trail and core and len(core) < len(ous):
        errs.append(f"{where}: one CloudTrail/Config deny targets {', '.join(sorted(ous))}; "
                    f"{', '.join(OAAR_TRAIL_OUS)} needs its own policy (its exception keeps {OAAR})")
    elif trail and core and OAAR not in allowed:
        errs.append(f"{where}: CloudTrail/Config deny on {', '.join(core)} does not except {OAAR}, which applies "
                    "the core stacks' trails and recorders (OPERATIONS, Bootstrap order step 6)")
    elif trail and ous and not core and OAAR in allowed:
        errs.append(f"{where}: CloudTrail/Config deny on {', '.join(sorted(ous))} excepts {OAAR}; only "
                    f"{', '.join(OAAR_TRAIL_OUS)} may (owner decision OQ-F: workload trails and recorders are "
                    "applied by <stack>-ci-apply, TerraformApplyAccess and AdministratorAccess)")
    return errs


def statement_findings(where, st, ous=(), security_account=None):
    """ous: the OU instances (aws-organizational-unit/<ou>) the statement's policy targets;
    security_account: the security account's id (settings.account_map.full_account_map.security)."""
    errs, actions = [], as_list(st.get("Action"))
    for keys in (st.get("Condition") or {}).values():
        for key, values in keys.items():
            for v in as_list(values) if key.lower() == PRINCIPAL_KEY else []:
                match = SSO_ROLE.match(v)
                if "AWSReservedSSO_" in v and not match:
                    errs.append(f"{where}: Identity Center principal {v!r} is not one named permission "
                                "set under arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/ (a name "
                                "outside that path, or any set, can be created or assumed by others)")
                elif match and match.group(2) == "-" and match.group(1) not in SSO_REQUIRED:
                    errs.append(f"{where}: Identity Center principal {v!r} ends in -*, which also takes "
                                f"every {match.group(1)}-<x> set; only {', '.join(SSO_REQUIRED)} have "
                                "per-backend variants")
    for key in condition_keys(st):
        near = difflib.get_close_matches(key, KNOWN_KEYS, n=1, cutoff=0.8)
        if key not in KNOWN_KEYS and near:
            errs.append(f"{where}: condition key {key!r} is not {near[0]!r}; on a missing key a "
                        "String*Not* test is true, so the deny would apply everywhere")
    if st.get("Effect") != "Deny":
        return errs
    keys = set(condition_keys(st))
    if is_protection(st) and any(RESERVED in r for r in as_list(st.get("Resource"))) and any(
            k.startswith("aws:principal") for k in keys):
        errs.append(f"{where}: protects role/aws-reserved/ with a principal exception; only Identity Center's "
                    "service-linked role writes there (outside SCPs), and an exempt principal could create an "
                    "AWSReservedSSO_ role (the break-glass's name) and act as it")
    if ("NotAction" in st or {"*", "*:*"} & set(actions)) and not keys & {REGION_KEY, PRINCIPAL_KEY}:
        errs.append(f"{where}: Deny with NotAction or of every action has no aws:RequestedRegion or "
                    "aws:PrincipalArn condition (it would lock out every principal)")
    cond = region_condition(st)
    if cond is not None and "NotAction" in st:
        missing = [g for g in GLOBAL_SERVICES if g not in as_list(st["NotAction"])]
        if missing:
            errs.append(f"{where}: region deny does not exempt global service(s) {', '.join(missing)}")
    if cond is None and any(a.lower().startswith(SECURITY_SERVICES) for a in actions):
        errs += security_findings(where, st, ous, security_account)
    return errs


def within(pattern, outer):
    """True when every ARN pattern matches is one outer matches (its wildcards taken literally)."""
    return fnmatch.fnmatchcase(pattern, outer)


def covering(statements, role):
    """The role-protection Denies whose Resource covers a role pattern."""
    return [st for st in statements if is_protection(st)
            and any(within(role, r) for r in as_list(st.get("Resource")))]


def squat_findings(where, statements):
    """Role exceptions (Identity Center's too) that no Deny of the same policy protects."""
    names = {v for st in statements if st.get("Effect") == "Deny" for v in principal_exceptions(st)
             if ":role/" in v}
    return [f"{where}: exception {v!r} is no resource of a Deny of {', '.join(SQUAT_ACTIONS)} in this "
            "policy, so anyone who can create a role of that name escapes the deny"
            for v in sorted(names) if not covering(statements, v)]


def acting_in(principal, account):
    """principal as it acts in account (it creates roles only in its own), else None."""
    own = account_of(principal)
    if own is None or account == "*" or own == account:
        return principal
    return re.sub(r"^(arn:aws:iam::)\*:", rf"\g<1>{account}:", principal) if own == "*" else None


def escalation_findings(where, statements):
    """Per protected role: a principal every protection covering a Deny's role exception exempts
    can create or re-trust that role (in its own account), assume it and escape the Deny, so it
    must be exempt from that Deny too, in the account the role is pinned to. A protection with no
    exception (aws-reserved/) lets no one create the role."""
    errs = []
    for st in statements:
        allowed = principal_exceptions(st)
        if st.get("Effect") != "Deny" or not allowed:
            continue
        escapers, roles, prots = set(), set(), set()
        for role in (v for v in allowed if ":role/" in v):
            prot = covering(statements, role)
            if not prot or not all(principal_exceptions(p) for p in prot):
                continue
            creators = [c for c in principal_exceptions(prot[0])
                        if all(any(within(c, e) for e in principal_exceptions(p)) for p in prot)]
            for c in creators:
                acting = acting_in(c, account_of(role))
                if acting and not any(within(acting, e) for e in allowed):
                    escapers.add(acting)
                    roles.add(role)
                    prots.update(p.get("Sid") or "?" for p in prot)
        if escapers:
            errs.append(f"{where}: {', '.join(sorted(escapers))} may create or re-trust a role {st.get('Sid')} "
                        f"excepts ({', '.join(sorted(roles))}; {', '.join(sorted(prots))} exempts it), so "
                        f"{st.get('Sid')} does not bind it")
    return errs


def is_protection(st):
    """A Deny of every SQUAT_ACTIONS action (the role-protection statement)."""
    actions = {a.lower() for a in as_list(st.get("Action"))}
    return st.get("Effect") == "Deny" and all(a.lower() in actions for a in SQUAT_ACTIONS)


def enabled(comp):
    return (comp.get("metadata") or {}).get("enabled") is not False and (comp.get("vars") or {}).get("enabled") is not False


def lockout_findings(stack, components):
    """An enabled security-services SCP while the stack's aws-identity-center is disabled or absent:
    until Identity Center is applied the accounts are run as OrganizationAccountAccessRole, which
    the plat trail/Config and protected-role denies do not except (root/global-region.yaml)."""
    if any(c.get("component") == IDENTITY_CENTER and enabled(c) and (c.get("metadata") or {}).get("type") != "abstract"
           for c in components.values()):
        return []
    return [f"{stack} {name}: enabled while {IDENTITY_CENTER} is disabled; enable the SCP only after Identity "
            "Center is applied (until then OrganizationAccountAccessRole runs the accounts, and plat's denies "
            "do not except it)"
            for name, c in sorted(components.items())
            if c.get("component") == COMPONENT and name.startswith(SECURITY_SERVICES_SCP) and enabled(c)
            and (c.get("metadata") or {}).get("type") != "abstract"]


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


def security_account_of(comp):
    """The security account's id from a component's settings.account_map, else None."""
    account_map = ((comp.get("settings") or {}).get("account_map") or {}).get("full_account_map") or {}
    return str(account_map["security"]) if account_map.get("security") else None


def policy_sizes(stacks):
    """[(stack, instance, characters)] of every aws-scp instance's policy that parses."""
    sizes = []
    for stack, body in sorted(stacks.items()):
        for name, comp in sorted(terraform(body).items()):
            if comp.get("component") != COMPONENT or (comp.get("metadata") or {}).get("type") == "abstract":
                continue
            try:
                doc = policy_document(comp.get("vars") or {})
            except (ValueError, KeyError, TypeError):
                continue
            sizes.append((stack, name, len(json.dumps(doc, separators=(",", ":")))))
    return sizes


def check(stacks):
    errs, per_target, ou_statements = [], {}, {}
    for stack, body in sorted(stacks.items()):
        errs += lockout_findings(stack, terraform(body))
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
            ous = sorted({m.group(1) for m in map(READ.match, map(str, targets)) if m})
            security = security_account_of(comp)
            for i, st in enumerate(doc["Statement"]):
                errs += statement_findings(f"{where} statement {st.get('Sid', i)}", st, ous, security)
            errs += squat_findings(where, doc["Statement"])
            errs += escalation_findings(where, doc["Statement"])
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
    for stack, name, size in policy_sizes(stacks):
        print(f"check-scp-policies: {stack} {name}: {size} of {MAX_CHARS} characters")
    for err in errs:
        print(f"check-scp-policies: {err}")
    if not errs:
        count = sum(1 for b in stacks.values() for c in terraform(b).values()
                    if c.get("component") == COMPONENT and (c.get("metadata") or {}).get("type") != "abstract")
        print(f"check-scp-policies: {count} SCP instance(s): OU targets only, valid and within limits, "
              "broad denies conditioned, global services exempt, deploy roles excepted and protected, every stack's "
              "account known, no stack in a denied region or denied a us-east-1 need, EU accounts kept "
              "out of us-east-1")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
