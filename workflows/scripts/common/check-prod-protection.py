#!/usr/bin/env python3
"""Check that every prod rds, elasticache and cognito instance keeps its data-loss protections.

Usage: check-prod-protection.py <components/terraform dir> < describe-stacks.json
(`atmos describe stacks --process-functions=false --format json`).

The stack templates (web-application, idp-platform) ship non-prod values and
leave the prod ones to the importing stack (their ENVIRONMENT-SPECIFIC
OVERRIDES). A prod stack that forgets an override would deploy a database
without deletion protection or a cache without failover. For every deployable
instance of rds or elasticache in a stack of stage prod, the effective value of
each setting below (the instance's var, else the variable's default read from
the component's variables.tf) must be safe:

  rds:          environment = "prod" (turns on the component's own prod
                validations), multi_az, deletion_protection and prevent_destroy
                true, skip_final_snapshot false, backup_retention_period >= 7
  elasticache:  automatic_failover_enabled and multi_az_enabled true, at least
                2 nodes (num_cache_nodes) unless cluster_mode_enabled, and
                snapshot_retention_limit >= 7
  cognito:      deletion_protection true (a deleted user pool loses every user,
                including those fnx-ue2-prod's DR pool migrated in)

And every deployable aws-iam-role instance with GitHub OIDC trust
(github_oidc_provider_enabled; the CI roles, stacks/catalog/aws-iam-role/ci.yaml), in any
stage, carries the trust the house iam's variable validations used to enforce (E6a4: the
vendored component validates none; gap G3): every trusted_github_repos entry is
"<org>/<repo>:<constraint>" with an explicit org and a constraint (upstream turns a
constraint-less entry into the wildcard subject repo:<org>/<repo>:*) and no * or ? anywhere
(the sub is matched with StringLike); a role other than ci-plan (apply, an uploader) trusts
branches only (no pull_request, environment:, ref: or other claim); ci-plan trusts a
branch, pull_request (github-assume-role-policy_override.tf) or an environment, and in
stage prod the master branch only (owner decision D3: no pull_request, so PR-controlled
code never reads prod state); no role sets eks_oidc_provider_enabled (an EKS IRSA trust
merged into the GitHub one); ci-plan's permissions are an allow-list (pull-request code
assumes it): managed_policy_arns only ReadOnlyAccess, policy_statements only
AssumeStateReadRoles (Allow sts:AssumeRole on the stage's ...-read-role ARNs, nothing else),
no policy_documents; the Lambda package uploader's (ci-lambda-uploader,
stacks/catalog/aws-iam-role/lambda-uploader.yaml, E6a5) are one too: no managed_policy_arns or
policy_statements, one policy_documents entry of exactly its four statements (conditional
PutObject, GetObject and ListBucket on one <...>-lambda-artifacts-<account id> bucket, and
GenerateDataKey/Encrypt/Decrypt by one KMS alias via S3 in one region; check-lambda-packages.py
pins the bucket and alias to the stack's); the trust list is not empty and no assume_role_policy
is merged into it (a hand-written trust would bypass these rules), nor principals. A role with
enabled false creates nothing and is skipped (the uploader's catalog default). The CI instances
(aws-iam-role/ci-plan, ci-apply, lambda-uploader) are recognised by instance name, so an override
cannot slip them out of these rules: each must keep its vars.name (the name its ARN is derived from)
and github_oidc_provider_enabled true. Every enabled aws-iam-role's resolved name
(ci-apply-role-arn.py's role_name, the one copy of the rule) fits IAM's 64 characters: with use_fullname
false the name is vars.name and must be at most 64; with true (the default) the null-label id must be, or
the module truncates it and appends a hash (id_length_limit never reaches the role name).

And every deployable aws-cloudtrail instance, in any stage (OQ-F, E5b4b), keeps
its trail and the trail's KMS key: Cloud Posse's component always creates the
key, with a hardcoded 10-day deletion window, so the only routine change that
schedules its deletion (and the trail's and log group's) is enabled false (the
var, or vars.context.enabled when the var is null); a new label replaces the
trail and its log group and renames the key alias, so the label must be the
stack's resolved `vendored` abstract context (namespace, tenant, environment,
stage, delimiter, label_order, id_length_limit, label_value_case,
regex_replace_chars; each var overriding its context field), with name
"cloudtrail" and no attributes (var or context), giving
<tenant>-<settings.prefix>-<stage>-cloudtrail. Removing the instance or
metadata.enabled false destroys nothing (Atmos stops planning it). The core
stacks that hold the trails are outside CD, so check-plan-destroys' deploy gate
never sees them: this lint is the guard.

Exits 1 on any unsafe value.
"""
import importlib.util
import json
import pathlib
import re
import sys
from typing import Any, Callable, Optional

PROD_STAGE = "prod"
# Owner decision D3: a prod plan role trusts the master branch's ref, nothing else.
PROD_PLAN_BRANCH = "master"
# The CI roles (stacks/catalog/aws-iam-role/ci.yaml): the vendored aws-iam-role with GitHub OIDC trust.
CI_ROLE_COMPONENT = "aws-iam-role"
CI_PLAN_NAME = "ci-plan"
# The GitHub OIDC issuer host: a trust that names it (directly or in an oidc-provider ARN) is a GitHub trust.
GITHUB_OIDC_HOST = "token.actions.githubusercontent.com"
# The component whose outputs (the provider ARN) a DRY hand-written trust would read with an Atmos function.
GITHUB_PROVIDER_COMPONENT = "aws-github-oidc-provider"
# An Atmos YAML function left unresolved (describe --process-functions=false keeps it as a raw string).
ATMOS_FUNCTION = re.compile(r"(?:^|[\s\"'])!(?:terraform\.|store|exec|env)\b")
# "<org>/<repo>:<constraint>": an explicit org (upstream's unqualified form takes trusted_github_org).
TRUSTED_REPO = re.compile(r"[A-Za-z0-9._-]+/[A-Za-z0-9._-]+:(.+)")
# A bare branch name: no ':' (so no ref:, environment: or other claim), no wildcard.
BRANCH = re.compile(r"[A-Za-z0-9._/-]+")
# The plan role's whole permission set, an allow-list (catalog/aws-iam-role/ci.yaml): pull-request code
# assumes it, so anything beyond read-only plus its state read role is a write it must never hold.
PLAN_READ_ONLY_POLICY = "arn:aws:iam::aws:policy/ReadOnlyAccess"
PLAN_STATE_STATEMENT = "AssumeStateReadRoles"
# A state backend read role (<role_prefix>[-prod]-read-role); check-ci-state-roles.py pins the exact one.
STATE_READ_ROLE = re.compile(r"arn:aws[a-z-]*:iam::[0-9]{12}:role/(?:[\w+=,.@-]+/)*[\w+=,.@-]+-read-role")
# The Lambda package uploader (stacks/catalog/aws-iam-role/lambda-uploader.yaml): an application repo's
# CI assumes it, so its whole permission set is an allow-list too. check-lambda-packages.py pins the
# bucket and alias to the stack's s3/lambda-artifacts and kms/main; this pins the statements' shape.
UPLOADER_NAME = "ci-lambda-uploader"
UPLOADER_FIX = "stacks/catalog/aws-iam-role/lambda-uploader.yaml renders exactly that; drop the override"
LAMBDA_BUCKET = re.compile(r"arn:aws:s3:::[a-z0-9.-]+-lambda-artifacts-[0-9]{12}")
KMS_ALIAS = re.compile(r"alias/[A-Za-z0-9/_-]+")
VIA_S3 = re.compile(r"s3\.[a-z]{2}(-[a-z]+)+-[0-9]+\.amazonaws\.com")
# The CI instances by instance name -> the vars.name each must keep (their names and ARNs are derived
# from it; the instance name, not vars.name, decides which rules apply).
CI_INSTANCES = {"aws-iam-role/ci-plan": CI_PLAN_NAME, "aws-iam-role/ci-apply": "ci-apply",
                "aws-iam-role/lambda-uploader": UPLOADER_NAME}
# The one copy of the null-label role name rule (ci-apply-role-arn.py; check-ci-state-roles.py uses it too).
_spec = importlib.util.spec_from_file_location(
    "ci_apply_role_arn", pathlib.Path(__file__).with_name("ci-apply-role-arn.py"))
ci_apply_role_arn = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ci_apply_role_arn)
MIN_RETENTION_DAYS = 7
# OQ-F: the vendored trail component and its sticky label name (fnx-ue1-<stage>-cloudtrail).
TRAIL_COMPONENT, TRAIL_NAME = "aws-cloudtrail", "cloudtrail"
# The trail's label must equal the stack's resolved `vendored` abstract context
# (stacks/catalog/_base/vendored.yaml) in every null-label field that shapes the id.
VENDORED_ABSTRACT = "vendored"
TRAIL_LABEL_FIELDS = ("namespace", "tenant", "environment", "stage", "delimiter", "label_order",
                      "id_length_limit", "label_value_case", "regex_replace_chars")

# component -> [(variable, is_safe, what safe means)]
RULES: dict[str, list[tuple[str, Callable[[Any, dict], bool], str]]] = {
    "rds": [
        ("environment", lambda v, _: v == "prod", '"prod"'),
        ("multi_az", lambda v, _: v is True, "true"),
        ("deletion_protection", lambda v, _: v is True, "true"),
        ("prevent_destroy", lambda v, _: v is True, "true"),
        ("skip_final_snapshot", lambda v, _: v is False, "false"),
        ("backup_retention_period", lambda v, _: isinstance(v, (int, float)) and v >= MIN_RETENTION_DAYS,
         f">= {MIN_RETENTION_DAYS}"),
    ],
    "elasticache": [
        ("automatic_failover_enabled", lambda v, _: v is True, "true"),
        ("multi_az_enabled", lambda v, _: v is True, "true"),
        ("num_cache_nodes", lambda v, eff: eff("cluster_mode_enabled") is True or (isinstance(v, (int, float)) and v >= 2),
         ">= 2 (or cluster_mode_enabled)"),
        ("snapshot_retention_limit", lambda v, _: isinstance(v, (int, float)) and v >= MIN_RETENTION_DAYS,
         f">= {MIN_RETENTION_DAYS}"),
    ],
    "cognito": [
        ("deletion_protection", lambda v, _: v is True, "true"),
    ],
}
DEFAULT = re.compile(r'^\s*default\s*=\s*("(?:[^"\\]|\\.)*"|true|false|-?\d+(?:\.\d+)?|null)\s*(?:#.*)?$')


def normalize(value: Any) -> Any:
    """Atmos renders Go templates as strings: "true"/"7" mean true/7."""
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered in ("true", "false"):
            return lowered == "true"
        if re.fullmatch(r"-?\d+", lowered):
            return int(lowered)
    return value


def variable_default(components_dir: pathlib.Path, component: str, name: str) -> Any:
    """A scalar default from the component's variables.tf; raises if it has none."""
    text = (components_dir / component / "variables.tf").read_text(encoding="utf-8")
    match = re.search(r'^variable\s+"' + re.escape(name) + r'"\s*\{\n(.*?)^\}', text, re.MULTILINE | re.DOTALL)
    if not match:
        raise KeyError(f"{component}: variable {name!r} is not declared in variables.tf")
    for line in match.group(1).splitlines():
        found = DEFAULT.match(line)
        if found:
            return json.loads(found.group(1))
    raise KeyError(f"{component}: variable {name!r} has no scalar default in variables.tf")


is_deployable = ci_apply_role_arn.is_deployable
def check(stacks: dict, components_dir: pathlib.Path) -> list[str]:
    errors = []
    for stack_name, stack in sorted(stacks.items()):
        for name, instance in sorted(((stack.get("components") or {}).get("terraform") or {}).items()):
            component = instance.get("component")
            stage = ((instance.get("settings") or {}).get("context") or {}).get("stage")
            if component not in RULES or stage != PROD_STAGE or not is_deployable(instance):
                continue
            variables = instance.get("vars") or {}

            def effective(var: str, _vars: dict = variables, _component: str = component) -> Optional[Any]:
                if var in _vars and _vars[var] is not None:
                    return normalize(_vars[var])
                return variable_default(components_dir, _component, var)

            for var, is_safe, safe in RULES[component]:
                try:
                    value = effective(var)
                except KeyError as error:
                    errors.append(f"{stack_name}: {name} {error}")
                    continue
                if not is_safe(value, effective):
                    source = "set" if var in variables else "the default"
                    errors.append(
                        f"{stack_name}: {name} ({component}) {var} is {json.dumps(value)} ({source}); "
                        f"a prod instance needs {safe}"
                    )
    return errors


def check_ci_trust(stacks: dict) -> list[str]:
    """GitHub-trusted aws-iam-role instances whose trust or plan permissions break the CI rules."""
    errors = []
    for stack_name, stack in sorted(stacks.items()):
        for name, instance in sorted(((stack.get("components") or {}).get("terraform") or {}).items()):
            variables = instance.get("vars") or {}
            # enabled false (the Cloud Posse switch; the uploader's catalog default) creates no role.
            if (instance.get("component") != CI_ROLE_COMPONENT or not is_deployable(instance)
                    or ci_apply_role_arn.flag(variables.get("enabled"), "vars.enabled") is False):
                continue
            where = f"{stack_name}: {name} ({CI_ROLE_COMPONENT})"
            errors += role_name_errors(where, name, instance)
            # The CI instances are checked by their instance name, whatever their vars say (an
            # override of name or github_oidc_provider_enabled must not drop them out of the rules).
            if name not in CI_INSTANCES and ci_apply_role_arn.flag(variables.get("github_oidc_provider_enabled"), "vars.github_oidc_provider_enabled") is not True:
                if names_github_trust(variables):
                    errors.append(f"{where} trusts GitHub OIDC ({GITHUB_OIDC_HOST}) through its assume_role_policy, "
                                  "principals or assume_role_conditions, which skips every CI trust rule; trust "
                                  "GitHub only through github_oidc_provider_enabled + trusted_github_repos on "
                                  "aws-iam-role/ci-* (stacks/catalog/aws-iam-role/ci.yaml); remove the hand-written "
                                  "trust")
                elif any(ATMOS_FUNCTION.search(trust_text(variables.get(key))) for key in ("assume_role_policy", "principals")):
                    errors.append(f"{where} builds its assume_role_policy or principals with an Atmos function, which "
                                  "can't be verified offline (it may resolve to a GitHub OIDC trust); write the "
                                  "trust literally, or trust GitHub only through github_oidc_provider_enabled + "
                                  "trusted_github_repos on aws-iam-role/ci-*")
                continue
            stage = ((instance.get("settings") or {}).get("context") or {}).get("stage")
            errors += ci_trust_errors(where, variables, stage, name)
    return errors


def trust_text(value: Any) -> str:
    """A trust variable as lowercase JSON text: a JSON string is parsed and re-dumped, so \\u escapes decode."""
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except ValueError:
            pass
    return json.dumps(value).lower() if value else ""


def names_github_trust(variables: dict) -> bool:
    """Whether the trust variables name the GitHub OIDC host, or read the provider component's outputs."""
    needles = (GITHUB_OIDC_HOST, GITHUB_PROVIDER_COMPONENT)
    return any(needle in trust_text(variables.get(key))
               for key in ("assume_role_policy", "principals", "assume_role_conditions") for needle in needles)


def role_name_errors(where: str, name: str, instance: dict) -> list[str]:
    """The role name must fit IAM's 64 characters on its own: id_length_limit never shortens it.

    cloudposse/iam-role/aws names the role module.role_name.id (use_fullname true) from a null-label
    that hard-codes id_length_limit 64, so a longer id is silently truncated and hashed; with
    use_fullname false the name is var.name, never truncated, and a longer one fails the apply.
    """
    role = ci_apply_role_arn.role_name(instance)
    if len(role) <= ci_apply_role_arn.MAX_ROLE_NAME:
        return []
    cap = ci_apply_role_arn.MAX_ROLE_NAME
    if not ci_apply_role_arn.uses_fullname(instance):
        return [f"{where} sets use_fullname false, so the role is named by vars.name {role!r} ({len(role)} characters), "
                f"over IAM's {cap} (id_length_limit does not shorten it): the apply would fail; "
                + ("drop the use_fullname override (vars.name is pinned)" if name in CI_INSTANCES
                   else "shorten vars.name")]
    consequence = ("the module would truncate it and append a hash, so it would no longer be the ARN CI and the "
                   "state backend derive (ci-apply-role-arn.py)" if name in CI_INSTANCES
                   else "the module would silently truncate it and append a hash")
    return [f"{where} resolves the role id {role!r} ({len(role)} characters), over IAM's {cap}: {consequence} "
            "(id_length_limit has no effect on it); shorten the lane name (settings.prefix)"
            + ("" if name in CI_INSTANCES else " or the instance's vars.name")]


def ci_trust_errors(where: str, variables: dict, stage: Optional[str], instance: str = "") -> list[str]:
    """One GitHub-trusted role's findings (instance: its instance name, which fixes its kind)."""
    expected = CI_INSTANCES.get(instance)
    plan = expected == CI_PLAN_NAME or variables.get("name") == CI_PLAN_NAME
    uploader = expected == UPLOADER_NAME or variables.get("name") == UPLOADER_NAME
    catalog = f"stacks/catalog/aws-iam-role/{'lambda-uploader' if uploader else 'ci'}.yaml"
    repos = variables.get("trusted_github_repos") or []
    errors = []
    if expected and variables.get("name") != expected:
        errors.append(f"{where} sets vars.name {variables.get('name')!r}: it must stay {expected!r} ({catalog}), "
                      "the name CI, the state backend and the docs derive the role's ARN from; drop the override")
    if expected and ci_apply_role_arn.flag(variables.get("github_oidc_provider_enabled"), "vars.github_oidc_provider_enabled") is not True:
        errors.append(f"{where} sets github_oidc_provider_enabled {variables.get('github_oidc_provider_enabled')!r}: "
                      f"its only trust is GitHub OIDC from trusted_github_repos ({catalog}); drop the override")
    if variables.get("principals"):
        errors.append(f"{where} sets principals {json.dumps(variables['principals'], sort_keys=True)}: a CI role's "
                      f"only trust is GitHub OIDC from trusted_github_repos ({catalog}); remove them")
    if not repos:
        errors.append(f"{where} enables GitHub OIDC trust with no trusted_github_repos entry: add the "
                      "\"<org>/<repo>:<branch>\" it trusts to the instance's vars.trusted_github_repos, or set "
                      "vars.enabled: false")
    if variables.get("permissions_boundary"):
        errors.append(f"{where} sets permissions_boundary {variables['permissions_boundary']!r}: a CI role's "
                      f"permissions are the catalog's allow-list ({catalog}), which this lint verifies; a boundary "
                      "would make the effective permissions differ from it (and can cap the apply role); remove it")
    if ci_apply_role_arn.flag(variables.get("instance_profile_enabled"), "vars.instance_profile_enabled") is True:
        errors.append(f"{where} sets instance_profile_enabled: true, which makes the role attachable to an EC2 "
                      f"instance; a CI role is assumed through GitHub OIDC only ({catalog}); remove it")
    if variables.get("max_session_duration") is not None:
        errors.append(f"{where} sets max_session_duration {variables['max_session_duration']!r}: CI roles keep the "
                      f"component default (3600s) so a leaked token lives no longer ({catalog}); remove it")
    if variables.get("assume_role_policy"):
        errors.append(f"{where} merges an assume_role_policy into its GitHub OIDC trust; the trust must come "
                      "from trusted_github_repos alone")
    for entry in repos:
        match = TRUSTED_REPO.fullmatch(str(entry))
        constraint = match.group(1) if match else None
        if not match or "*" in str(entry) or "?" in str(entry):
            errors.append(f"{where} trusts {entry!r}: an entry must be \"<org>/<repo>:<constraint>\" with no * "
                          "or ? (a constraint-less entry becomes repo:<org>/<repo>:*, StringLike)")
        elif plan and stage == PROD_STAGE and constraint != PROD_PLAN_BRANCH:
            errors.append(f"{where} trusts {entry!r}: a prod plan role trusts the {PROD_PLAN_BRANCH} branch only "
                          "(D3; settings.github.pull_request_plans_enabled false)")
        elif plan and not (BRANCH.fullmatch(constraint) or constraint == "pull_request"
                           or constraint.startswith("environment:")):
            errors.append(f"{where} trusts {entry!r}: a plan role trusts a branch, pull_request or an environment")
        elif not plan and (not BRANCH.fullmatch(constraint) or constraint == "pull_request"):
            errors.append(f"{where} trusts {entry!r}: a role other than {CI_PLAN_NAME} (apply, uploader) trusts "
                          "a pinned branch only, never pull_request, an environment or another claim")
    if ci_apply_role_arn.flag(variables.get("eks_oidc_provider_enabled"), "vars.eks_oidc_provider_enabled") is True:
        errors.append(f"{where} sets eks_oidc_provider_enabled: true, which merges an EKS IRSA trust into its "
                      "GitHub OIDC trust (a Kubernetes service account could assume it); remove it from the "
                      f"role's vars ({catalog})")
    if plan:
        errors += plan_permission_errors(where, variables)
    if uploader:
        errors += uploader_permission_errors(where, variables)
    return errors


def uploader_permission_errors(where: str, variables: dict) -> list[str]:
    """The uploader holds only its four package statements, in one policy_documents entry."""
    errors = []
    if variables.get("managed_policy_arns"):
        errors.append(f"{where} managed_policy_arns attaches {sorted(variables['managed_policy_arns'])}: the "
                      f"uploader, which an application repo's CI assumes, attaches no managed policy ({UPLOADER_FIX})")
    if variables.get("policy_statements"):
        errors.append(f"{where} sets policy_statements {sorted(variables['policy_statements'])}: the uploader's "
                      f"policy is its one policy_documents entry ({UPLOADER_FIX})")
    documents = variables.get("policy_documents") or []
    try:
        statements = [json.loads(document).get("Statement") for document in documents]
    except (TypeError, ValueError, AttributeError) as error:
        return errors + [f"{where} policy_documents is not a JSON policy ({error}) ({UPLOADER_FIX})"]
    region = variables.get("region")
    if len(statements) != 1 or not uploader_statements_ok(statements[0], region):
        errors.append(f"{where} policy_documents is outside the uploader's allow-list: it must be exactly one document with "
                      "PutLambdaPackages (s3:PutObject on <bucket>/* only with s3:if-none-match), ReadLambdaPackages "
                      "(s3:GetObject on <bucket>/*), ListLambdaPackages (s3:ListBucket on <bucket>) and "
                      "LambdaPackageEncryption (kms:GenerateDataKey/Encrypt/Decrypt on * by one alias, via "
                      f"s3.{region}.amazonaws.com only), one <...-lambda-artifacts-<account id>> bucket throughout, "
                      f"and no other statement ({UPLOADER_FIX})")
    return errors


def uploader_statements_ok(statements: Any, region: Any) -> bool:
    """The four statements the catalog renders, with one bucket ARN, one alias and this region's S3 endpoint."""
    # Intentionally restates the catalog's statement shape (owner OQ4, won't fix): an allow-list derived
    # from the catalog it checks would pass whatever the catalog said, and prove nothing.
    if not isinstance(statements, list):
        return False
    by_sid = {s.get("Sid"): s for s in statements if isinstance(s, dict)}
    if len(by_sid) != 4 or len(statements) != 4:
        return False
    put, read, listing, kms = (by_sid.get(sid) or {} for sid in (
        "PutLambdaPackages", "ReadLambdaPackages", "ListLambdaPackages", "LambdaPackageEncryption"))
    bucket = (listing.get("Resource") or [None])[0] if isinstance(listing.get("Resource"), list) else None
    if not isinstance(bucket, str) or not LAMBDA_BUCKET.fullmatch(bucket):
        return False
    shape = (
        (put, ["s3:PutObject"], [f"{bucket}/*"], {"Null": {"s3:if-none-match": "false"}}),
        (read, ["s3:GetObject"], [f"{bucket}/*"], None),
        (listing, ["s3:ListBucket"], [bucket], None),
    )
    for statement, actions, resources, condition in shape:
        expected = {"Sid": statement.get("Sid"), "Effect": "Allow", "Action": actions, "Resource": resources}
        if condition:
            expected["Condition"] = condition
        if statement != expected:
            return False
    condition = kms.get("Condition") or {}
    aliases = (condition.get("ForAnyValue:StringEquals") or {}).get("kms:ResourceAliases")
    via = (condition.get("StringEquals") or {}).get("kms:ViaService")
    return (
        set(kms) == {"Sid", "Effect", "Action", "Resource", "Condition"} and kms.get("Effect") == "Allow"
        and kms.get("Action") == ["kms:GenerateDataKey", "kms:Encrypt", "kms:Decrypt"] and kms.get("Resource") == "*"
        and set(condition) == {"ForAnyValue:StringEquals", "StringEquals"}
        and set(condition["ForAnyValue:StringEquals"]) == {"kms:ResourceAliases"}
        and set(condition["StringEquals"]) == {"kms:ViaService"}
        and isinstance(aliases, list) and len(aliases) == 1 and KMS_ALIAS.fullmatch(str(aliases[0])) is not None
        and via == [f"s3.{region}.amazonaws.com"] and VIA_S3.fullmatch(via[0]) is not None
    )


def plan_permission_errors(where: str, variables: dict) -> list[str]:
    """ci-plan holds only the allow-list: ReadOnlyAccess and the sts:AssumeRole on its stage read role."""
    errors = []
    fix = "stacks/catalog/aws-iam-role/ci.yaml renders exactly that; drop the override"
    extra = sorted(str(arn) for arn in variables.get("managed_policy_arns") or [] if arn != PLAN_READ_ONLY_POLICY)
    if extra:
        errors.append(f"{where} managed_policy_arns attaches {extra}: the plan role, which pull-request code "
                      f"assumes, may attach only {PLAN_READ_ONLY_POLICY} ({fix})")
    statements = variables.get("policy_statements") or {}
    for sid in sorted(set(statements) - {PLAN_STATE_STATEMENT}):
        errors.append(f"{where} policy_statements.{sid} is not allowed: the plan role's own policy holds only "
                      f"{PLAN_STATE_STATEMENT} ({fix})")
    if PLAN_STATE_STATEMENT in statements:
        errors += state_statement_errors(f"{where} policy_statements.{PLAN_STATE_STATEMENT}",
                                         statements[PLAN_STATE_STATEMENT] or {}, fix)
    if variables.get("policy_documents"):
        errors.append(f"{where} sets policy_documents: the plan role's own policy holds only policy_statements."
                      f"{PLAN_STATE_STATEMENT} ({fix})")
    return errors


def state_statement_errors(where: str, statement: dict, fix: str) -> list[str]:
    """The state read statement as the catalog renders it: Allow sts:AssumeRole on read roles, nothing more."""
    resources = statement.get("resources")
    resources = resources if isinstance(resources, list) else [resources]
    shape = {key: value for key, value in statement.items() if value is not None}
    if (set(shape) == {"effect", "actions", "resources"} and statement.get("effect") == "Allow"
            and statement.get("actions") == ["sts:AssumeRole"] and resources
            and all(STATE_READ_ROLE.fullmatch(str(arn)) for arn in resources)):
        return []
    return [f"{where} is {json.dumps(statement, sort_keys=True)}: it must be exactly effect Allow, actions "
            f"[\"sts:AssumeRole\"] and resources of the stage's state read role(s) (...-read-role) ({fix})"]


def check_trails(stacks: dict) -> list[str]:
    """aws-cloudtrail instances whose trail or trail key a routine change would destroy or replace."""
    errors = []
    for stack_name, stack in sorted(stacks.items()):
        for name, instance in sorted(((stack.get("components") or {}).get("terraform") or {}).items()):
            if instance.get("component") != TRAIL_COMPONENT or not is_deployable(instance):
                continue
            errors += trail_errors(f"{stack_name}: {name} ({TRAIL_COMPONENT})", instance.get("vars") or {},
                                   (((stack.get("components") or {}).get("terraform") or {}).get(VENDORED_ABSTRACT)
                                    or {}).get("vars"))
    return errors


def trail_errors(where: str, variables: dict, vendored: Optional[dict]) -> list[str]:
    """One trail's findings against its stack's resolved `vendored` abstract (the null-label shape)."""
    context = variables.get("context") or {}
    expected = (vendored or {}).get("context")
    if not isinstance(expected, dict):
        return [f"{where}: its stack has no resolved {VENDORED_ABSTRACT!r} abstract context to check the label against"]

    def effective(field: str) -> Any:
        # null-label: a non-null var wins, else the context's value.
        value = variables.get(field)
        return normalize(value if value is not None else context.get(field))

    errors = []
    if effective("enabled") is False:
        errors.append(
            f"{where} enabled is false (var or context): that schedules the trail KMS key's deletion and "
            "destroys the trail and its log group; set metadata.enabled false to stop deploying it instead (OQ-F)"
        )
    # null-label appends context.attributes to var.attributes.
    attributes = list(variables.get("attributes") or []) + list(context.get("attributes") or [])
    changed = [f"{field} {effective(field)!r} (vendored: {normalize(expected.get(field))!r})"
               for field in TRAIL_LABEL_FIELDS if effective(field) != normalize(expected.get(field))]
    if attributes:
        changed.append(f"attributes {attributes!r} (vendored: [])")
    if effective("name") != TRAIL_NAME:
        changed.append(f"name {effective('name')!r} (want {TRAIL_NAME!r})")
    want = "-".join(str(expected.get(f)) for f in ("tenant", "environment", "stage")) + f"-{TRAIL_NAME}"
    got = "-".join(str(effective(f)) for f in ("tenant", "environment", "stage", "name"))
    if changed or got != want:
        errors.append(
            f"{where} label differs from the vendored null-label shape ({'; '.join(changed) or 'id'}): "
            f"the trail, its log group and its key alias are sticky as {want!r} (this label gives {got!r}"
            f"{' before the changed fields' if changed else ''}); a new label replaces the trail"
        )
    return errors


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.splitlines()[2], file=sys.stderr)
        return 2
    described = json.load(sys.stdin)
    errors = ci_apply_role_arn.flag_errors(described) or (check(described, pathlib.Path(sys.argv[1])) + check_ci_trust(described)
                                       + check_trails(described))
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} prod protection problem(s)")
        return 1
    print(
        "every prod rds instance is environment prod, Multi-AZ, deletion-protected, keeps a final "
        f"snapshot and {MIN_RETENTION_DAYS}+ days of backups; every prod elasticache instance fails over "
        f"across AZs and keeps {MIN_RETENTION_DAYS}+ days of snapshots; every prod cognito pool is "
        "deletion-protected; every GitHub-trusted role trusts exact, constrained subjects (apply roles a "
        "pinned branch, prod plan roles master only) with no EKS trust, and every plan role holds only "
        "ReadOnlyAccess and its state read role; every trail keeps its key "
        "and its label"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
