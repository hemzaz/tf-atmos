#!/usr/bin/env python3
"""First-deploy preflight: fail while a stack that would be deployed still holds a placeholder.

Reads `atmos describe stacks --process-functions=false --format json` on stdin,
so it checks the RESOLVED values (settings.environment.account_id and
management_account_id after any account-map template, vars after inheritance),
whatever file they are written in. Covers every row of docs/OPERATIONS.md
"First-deploy inputs"; each finding names the stack, the key and that row.

Errors (fatal unless --warn):
  - an AWS docs placeholder account ID (123456789012, 000000000000) in any
    string: account IDs, ARNs (backend access_roles, trusted_principal_arns...)
  - the placeholder AWS Organization ID (o-xxxxxxxxxx)
  - a reserved example domain (RFC 2606: example.com/.net/.org, *.example,
    *.test, *.invalid) in a domain or an alert address
  - an enabled eks instance with no map_additional_iam_roles (EKS admin role)
  - a prod-stage rds instance with no sns_topic_arn
  - a github-runners instance whose GitHub App ID or installation ID is the
    placeholder 0
  - a workload account equal to the management account
  - two stages sharing an account (one account per stage)
The last two skip placeholder IDs, which are already an error.
Notices (printed, never fatal): the rows a file cannot settle (Cognito
feature plan, cross-account caller role existence, Lambda packages, GitHub
protection, deploy tags, the GitHub App's private key and outside-collaborator
approval).

Only deployable stacks are checked: every stage but EXEMPT_STAGES. --stacks
limits the placeholder checks to some of them (the bootstrap workflow passes
the stack it is about to deploy); the account checks still compare against
every deployable stack. --warn prints errors as WARN and exits 0 (lint: the
repo holds placeholders until the first deploy). Exit 1 on any error otherwise.
"""
import argparse
import json
import re
import sys
from dataclasses import dataclass

DOCS = "docs/OPERATIONS.md#first-deploy-inputs"
# Never deployed to a real account: the emulator lanes and the template fixtures.
EXEMPT_STAGES = {"local", "fixtures"}
# The management account's own stage: its account IS management_account_id.
MANAGEMENT_STAGES = {"root"}

PLACEHOLDER_ACCOUNTS = ("123456789012", "000000000000")
# A 12-digit run that is not part of a longer hex token (a digest) and not a
# UUID's last group: the lookbehind is the whole 8-4-4-4 UUID prefix, so
# names like "backups-2026-123456789012" or "logs-cafe-123456789012" still match.
ACCOUNT_RE = re.compile(
    r"(?<![0-9a-fA-F])(?<![0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-)(?:%s)(?![0-9a-fA-F])"
    % "|".join(PLACEHOLDER_ACCOUNTS)
)
WARN_LIMIT = 10
ORG_RE = re.compile(r"\bo-x{10}\b", re.IGNORECASE)
EXAMPLE_DOMAIN_RE = re.compile(
    r"(?:^|[.@/])(?:example\.(?:com|net|org)|[a-z0-9-]+\.(?:example|test|invalid))(?![a-z0-9-])",
    re.IGNORECASE,
)
OPERATOR_ROLE = "-cross-account-operator"


@dataclass(frozen=True)
class Finding:
    level: str  # "error" or "notice"
    stack: str
    key: str
    detail: str
    row: str

    def line(self, warn: bool) -> str:
        label = {"error": "WARN" if warn else "ERROR", "notice": "NOTICE"}[self.level]
        where = f"{self.stack}: {self.key}" if self.key else self.stack
        return f"{label} {where}: {self.detail} ({DOCS}: {self.row})"


def deployable(instance: dict) -> bool:
    metadata = instance.get("metadata") or {}
    return metadata.get("type") != "abstract" and metadata.get("enabled", True) is not False


def instances(config: dict) -> dict:
    return ((config or {}).get("components") or {}).get("terraform") or {}


def environment(config: dict) -> dict:
    """The stack's settings.environment (the same on every instance), and its stage."""
    for spec in instances(config).values():
        settings = (spec or {}).get("settings") or {}
        if settings.get("environment") or settings.get("context"):
            return {**(settings.get("environment") or {}), "_stage": (settings.get("context") or {}).get("stage")}
    return {}


def strings(value, path):
    """(dotted path, string) for every string inside `value`."""
    if isinstance(value, dict):
        for key, item in value.items():
            yield from strings(item, f"{path}.{key}")
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from strings(item, f"{path}[{index}]")
    elif isinstance(value, str):
        yield path, value


def placeholder(stack: str, key: str, text: str):
    """The finding for one string, or None."""
    if ACCOUNT_RE.search(text):
        return Finding("error", stack, key, f"placeholder account ID in {text!r}", "Account IDs")
    if ORG_RE.search(text):
        return Finding("error", stack, key, f"placeholder organization ID {text!r}", "AWS Organization ID")
    if EXAMPLE_DOMAIN_RE.search(text):
        row = "Alert recipients" if "@" in text else "Domains"
        return Finding("error", stack, key, f"example domain in {text!r}", row)
    return None


def stack_findings(name: str, config: dict) -> list:
    findings, seen = [], set()

    def add(finding):
        if finding and (finding.key, finding.detail) not in seen:
            seen.add((finding.key, finding.detail))
            findings.append(finding)

    env = environment(config)
    for path, text in strings({k: v for k, v in env.items() if k != "_stage"}, "settings.environment"):
        add(placeholder(name, path, text))
    operator_roles = False
    for instance_name, spec in sorted(instances(config).items()):
        spec = spec or {}
        if not deployable(spec):
            continue
        variables = spec.get("vars") or {}
        component = spec.get("component") or (spec.get("metadata") or {}).get("component")
        for path, text in strings(variables, "vars"):
            add(placeholder(name, f"{instance_name} {path}", text))
            if path.startswith("vars.trusted_principal_arns") and OPERATOR_ROLE in text:
                operator_roles = True
        if component == "eks" and not variables.get("map_additional_iam_roles"):
            add(Finding("error", name, f"{instance_name} vars.map_additional_iam_roles",
                        "empty: no EKS cluster admin role (an operator's full IAM role ARN, path included)",
                        "EKS cluster admins"))
        if component == "rds" and env.get("_stage") == "prod" and not variables.get("sns_topic_arn"):
            add(Finding("error", name, f"{instance_name} vars.sns_topic_arn",
                        "unset: its CloudWatch alarms have no action", "Prod RDS alarm target"))
        if component == "github-runners":
            for key in ("github_app_id", "github_app_installation_id"):
                if str(variables.get(key, "0")) == "0":
                    add(Finding("error", name, f"{instance_name} vars.{key}",
                                "placeholder 0: the owner's GitHub App is not set up", "GitHub App"))
        if component == "cognito" and variables.get("user_pool_tier") == "PLUS":
            add(Finding("notice", name, f"{instance_name} vars.user_pool_tier",
                        "PLUS is billed from the first monthly active user; confirm it is intended",
                        "Cognito feature plan"))
    if operator_roles:
        add(Finding("notice", name, "vars.trusted_principal_arns",
                    f"the <tenant>{OPERATOR_ROLE} role must exist in the management account (not checkable here)",
                    "Cross-account role callers"))
    return findings


def account_findings(stacks: dict, targets: set) -> list:
    """Workload account == management account; two stages sharing an account."""
    findings, by_account = [], {}
    for name in sorted(stacks):
        env = environment(stacks[name])
        stage, account, management = env.get("_stage"), env.get("account_id"), env.get("management_account_id")
        if stage in EXEMPT_STAGES or stage in MANAGEMENT_STAGES or not account:
            continue
        account = str(account)
        if account in PLACEHOLDER_ACCOUNTS:
            continue
        if name in targets and management and account == str(management):
            findings.append(Finding(
                "error", name, "settings.environment.account_id",
                f"{account} is the management account: a workload stack there bypasses the state access roles",
                "every workload account_id must differ from management_account_id"))
        by_account.setdefault(account, {}).setdefault(stage, []).append(name)
    for account, stages in sorted(by_account.items()):
        if len(stages) < 2:
            continue
        for stage, names in sorted(stages.items()):
            for name in names:
                if name in targets:
                    others = sorted(f"{s} ({', '.join(n)})" for s, n in stages.items() if s != stage)
                    findings.append(Finding(
                        "error", name, "settings.environment.account_id",
                        f"{account} is also the account of stage {'; '.join(others)}: one account per stage",
                        "Account IDs"))
    return findings


def notices() -> list:
    return [
        Finding("notice", "repository", "", "every lambda/* instance stays metadata.enabled: false until the "
                "application repo is in lambda_uploader_trusted_github_repos and each function is uploaded",
                "Lambda packages"),
        Finding("notice", "repository", "", "default-branch protection with the required check `CI gate`",
                "GitHub"),
        Finding("notice", "repository", "", "after each stack's first deploy, push its deployed/<stack> tag",
                "Deploy tags"),
        Finding("notice", "repository", "", "the GitHub App's private key in each account's SSM, and "
                "\"Require approval for all outside collaborators\" on (self-hosted runners, public repository)",
                "GitHub App"),
    ]


def check(stacks: dict, only=None) -> list:
    """All findings for the deployable stacks (`only`: limit the per-stack checks to these)."""
    deployable_stacks = {
        name: config for name, config in stacks.items()
        if environment(config).get("_stage") not in EXEMPT_STAGES and instances(config)
    }
    targets = set(deployable_stacks) if not only else set(only) & set(deployable_stacks)
    findings = []
    for name in sorted(targets):
        findings.extend(stack_findings(name, deployable_stacks[name]))
    findings.extend(account_findings(deployable_stacks, targets))
    return findings + notices()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--stacks", default="", help="comma-separated stacks to check (default: every deployable stack)")
    parser.add_argument("--warn", action="store_true",
                        help=f"print errors as WARN and exit 0; only the first {WARN_LIMIT} unless --all")
    parser.add_argument("--all", action="store_true", help="with --warn, print every finding")
    args = parser.parse_args()

    stacks = json.load(sys.stdin)
    # Quotes tolerated: the bootstrap workflow passes an `atmos describe stacks --query` value.
    only = [s.strip().strip('"') for s in args.stacks.split(",") if s.strip().strip('"')]
    unknown = [s for s in only if s not in stacks]
    if unknown:
        print(f"ERROR unknown stack(s): {', '.join(unknown)}", file=sys.stderr)
        return 1
    exempt = [s for s in only if environment(stacks[s]).get("_stage") in EXEMPT_STAGES]
    if exempt:
        print(f"NOTICE never deployed to a real account, not checked: {', '.join(exempt)}")
    findings = sorted(check(stacks, only), key=lambda f: (f.level != "error", f.stack, f.row, f.key))
    errors = [f for f in findings if f.level == "error"]
    # Fatal mode (and --all) prints every finding; --warn (lint, every run)
    # prints the first WARN_LIMIT errors and the per-row counts.
    shown = findings if (args.all or not args.warn) else errors[:WARN_LIMIT]
    for finding in shown:
        print(finding.line(args.warn))
    if len(shown) < len(findings):
        print(f"... {len(errors) - len(shown)} more WARN and {len(findings) - len(errors)} NOTICE line(s) not shown; "
              "see them all with --warn --all, or run without --warn")
    checked = ", ".join(sorted(set(only) - set(exempt))) if only else "every deployable stack"
    if errors:
        rows = {}
        for finding in errors:
            rows[finding.row] = rows.get(finding.row, 0) + 1
        print("By row: " + ", ".join(f"{row} {count}" for row, count in sorted(rows.items())))
        print(f"{len(errors)} first-deploy input(s) still hold placeholders or break the account model "
              f"(checked: {checked}). Replace them before deploying: {DOCS}")
        return 0 if args.warn else 1
    print(f"First-deploy inputs: no placeholders (checked: {checked}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
