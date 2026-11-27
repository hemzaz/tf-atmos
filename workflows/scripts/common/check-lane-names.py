#!/usr/bin/env python3
"""Check that nothing sharing an account and region creates the same resource name.

Usage: check-lane-names.py < describe-stacks.json
(`atmos describe stacks --process-functions=false --format json`).

A lane (settings.context.name) deploys beside its stage stack in the same
account and region: fnx-ue1-dev-serverless beside fnx-ue1-dev. Its names carry
the lane, Cloud Posse null-label style: the full id is the stack name and the
environment-derived prefix, settings.prefix, is <region code>-<name>
(stacks/orgs/fnx/_defaults.yaml), which tags.Environment, and so every
component's <Environment>-<name> names, start with.

Stacks are grouped by account (settings.environment.account) and region
(vars.region); a stack with deployable instances but neither is an error, as
it cannot be checked. Within a group this fails:
  - two stacks whose deployable instances share a tags.Environment value;
  - two instances that create the same name from a key a component uses
    VERBATIM (RAW_NAMES: kms alias_name, ecs cluster_name, dynamodb
    table_name, ...), whatever its prefix. Only creating keys count: a key
    that names an existing resource (cluster_name in eks-addons, a lane's
    reference to its stage's cluster) is not compared (the CI roles and the
    Lambda uploader are the vendored aws-iam-role's, named by the lane-aware
    null-label id);
  - two instances that create the same account singleton (SINGLETONS: the
    GitHub OIDC provider (the vendored aws-github-oidc-provider), each
    service-linked role (MAP_SINGLETONS: one per
    aws-iam-service-linked-roles service_linked_roles service name), the
    multi-region CloudTrail trail, CloudTrail's global-service-event
    recording, AWS Config's global-resource recording, the IAM account alias
    and the S3 account public access block), whichever instance creates it:
    the vendored aws-cloudtrail (multi-region with global events unless set
    false, CP defaults) and aws-config (its global-resource collector, the
    instance whose global_resource_collector_region is its stack's region,
    or unset: REGION_SINGLETONS; the security account may also collect in
    eu-west-1 for the EU Config aggregator: REGION_SINGLETON_ALLOWANCES);
    stage fixtures, never deployed and each standalone, are exempt;
  - two secretsmanager instances creating the same secret name
    (context_name/environment/path/name).
The org security services (check-data-residency.py's ORG_SERVICES: the vendored
aws-guardduty, aws-security-hub, aws-inspector2) run one of Cloud Posse's three
steps by the account they deploy to: root (the management account, its
delegation), delegated-administrator (the security account, admin_delegated off:
the detector/hub; Inspector has none) and org-settings (the security account,
admin_delegated on). Across all stacks (fixtures exempt) this fails an instance
whose delegated_administrator_account_name is not <tenant>-security, or that
deploys to any other account (it would create nothing); two instances of one
service, step and region; and two aws-security-hub root steps that leave
organizations_resource_policy_enabled on (CP default): the policy is an
organization singleton; two Security Hub finding aggregators of one account; and an
organization_management_account_name other than its account_map's root account (an instance
naming its own account management is not a root step). Two steps of one service in one stack are not a
same-name pair (only step 1 names a resource) unless one sets create_sns_topic. Access Analyzer
(vendored access-analyzer): one analyzer per account, region and type (ORGANIZATION,
ORGANIZATION_UNUSED_ACCESS, and the house ACCOUNT one, E5c7b), one unused-access analyzer per
account and residency, one delegation in all; two of its instances in one stack creating different
analyzer types are not a same-name pair (each analyzer's name ends in its type).
Account-wide names (IAM, the account singletons) are also compared between
the regions of one account: fnx-ue1-prod and its DR stack fnx-ue2-prod share
the prod account, so they cannot create the same IAM role or both the GitHub
OIDC provider. Most IAM names are built from tags.Environment inside a
component (backup <Environment>-backup-service-role, rds
<Environment>-<identifier>-monitoring-role, ...), so two regions of one account
whose IAM- or S3-creating instances (ACCOUNT_WIDE_COMPONENTS: s3 and alb build
bucket names <Environment>-<name>-<account id>) share a tags.Environment fail too.
Within one stack, two deployable instances of one component build the same
<Environment>-<input> names when a primary name key both set (PRIMARY_NAMES:
name, identifier, function_name, ...) is equal: vpc/main and vpc/services
differ in name, and an incidental difference (availability_zones, db_name)
does not separate them. Instances sharing no primary key compare all their
name inputs (NAME_INPUT: *_name, *_prefix, domains, zones, ...) instead.
Across every stack (any account or region): an S3 bucket name or Cognito
domain prefix (GLOBAL_KEYS, at any depth of vars) set twice. Per account: an
enabled aws-iam-role instance that trusts the GitHub OIDC provider (the CI roles and
the Lambda uploader: github_oidc_provider_enabled, github_oidc_provider_arn) while no
stack of the account has an aws-github-oidc-provider instance, which deleting the
creating stack would leave.
Exits 1 on any collision.
"""
import collections
import importlib.util
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import backends  # noqa: E402
import fixtures  # noqa: E402

# check-data-residency.py's ORG_SERVICES and its account helpers, the one definition.
_spec = importlib.util.spec_from_file_location(
    "check_data_residency", os.path.join(os.path.dirname(os.path.abspath(__file__)), "check-data-residency.py")
)
residency = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(residency)
# The org services' delegated administrator: the security account (CP, owner E5c Design).
DELEGATED_ADMIN_ACCOUNT = "security"

SKIP_VARS = {"tags", "description"}
# vars keys that name an instance's resources (with tags.Environment).
NAME_INPUT = re.compile(
    r"(^|_)(name|names|identifier|prefix|cluster_id|alias|bucket|domain|domains|zones|function_name|queue_name|topic_name)(_|$)"
)
# vars keys that are an instance's own name: two instances of one component in
# one stack that set one of these to the same value build the same names,
# whatever else differs.
PRIMARY_NAMES = (
    "name",
    "identifier",
    "cluster_id",
    "cluster_name",
    "function_name",
    "table_name",
    "bucket_name",
    "queue_name",
    "topic_name",
    "alias_name",
)
# Not event_bus_name: eventbridge rule instances name the bus they attach to.
# (component, key) pairs of PRIMARY_NAMES that name ANOTHER resource there:
# alb-controller-ingress-group's cluster_name is the cluster it attaches to (its
# own name is group_name); lambda's alias_name (default "live") is scoped to
# its function.
NOT_PRIMARY = {("alb-controller-ingress-group", "cluster_name"), ("lambda", "alias_name")}
# Components whose IAM role or policy names, or S3 bucket names, are built from
# tags.Environment (or a name built from it): both are account-wide (S3 names
# are global and carry no region). Not iam (it creates nothing; E6a6 deletes it), backend
# (built from its bucket name) or apigateway-account (its role name carries the
# region). Nor the vendored aws-cloudtrail and aws-config: they name their IAM
# roles from the null-label id (vars.context), whose environment is the region
# code, not from tags.Environment.
ACCOUNT_WIDE_COMPONENTS = frozenset({
    "alb", "apigateway", "backup", "batch", "cost-optimization", "ec2", "ecs-service", "eks",
    "eks-addons", "external-secrets", "firehose", "github-runners", "glue", "lambda", "monitoring", "rds",
    "s3", "security-monitoring", "stepfunctions", "vpc",
})
# (component, key) -> resource: keys the component uses verbatim in an
# account- or region-unique name.
RAW_NAMES = {
    ("kms", "alias_name"): "KMS alias",
    ("kms", "name_prefix"): "KMS key name prefix",
    ("cognito", "name_prefix"): "Cognito user pool",
    ("network", "name_prefix"): "network name prefix",
    ("dynamodb", "table_name"): "DynamoDB table",
    ("ecs", "cluster_name"): "ECS cluster",
    ("waf", "metric_name"): "WAF metric",
    ("apigateway", "domain_name"): "API Gateway custom domain",
}
# (component, gate var, default) -> account singleton it creates when true.
SINGLETONS = {
    # The vendored provider (null-label enabled, which is_deployable already
    # reads): one per account (catalog/aws-github-oidc-provider/main).
    ("aws-github-oidc-provider", "enabled", True): "GitHub OIDC provider",
    # The vendored Cloud Posse trail defaults both to true (variables.tf). A
    # second trail recording IAM/STS events would duplicate (and bill) the
    # account's global-service events: a regional trail sets it false.
    ("aws-cloudtrail", "is_multi_region_trail", True): "multi-region CloudTrail trail",
    ("aws-cloudtrail", "include_global_service_events", True): "CloudTrail global-service-event recording",
    # aws-account-settings' account-wide settings: its account's first stack
    # sets them (catalog/aws-account-settings/main), the others turn them off
    # (main-standby).
    ("aws-account-settings", "account_alias_enabled", True): "IAM account alias",
    ("aws-account-settings", "s3_block_public_access_enabled", True): "S3 account public access block",
}
# (component, var) -> account singleton kind: the vendored
# aws-iam-service-linked-roles creates one role per vars.service_linked_roles
# entry, an account singleton per aws_service_name (one instance per account:
# catalog/aws-iam-service-linked-roles).
MAP_SINGLETONS = {
    ("aws-iam-service-linked-roles", "service_linked_roles"): "service-linked role",
}
# (component, var) -> account singleton it creates when var is its stack's
# vars.region (or unset): the vendored aws-config records global resource types
# (IAM) only in its global_resource_collector_region.
REGION_SINGLETONS = {
    ("aws-config", "global_resource_collector_region"): "AWS Config global-resource recording",
}
# (kind, account, region): a REGION_SINGLETONS kind an account may create a second time, in that
# region only (one per region still holds). Owner OQ-EA (a), 2026-11-10: Cloud Posse creates the
# Config aggregator only in the central account's collector region, so the security account's EU
# aggregator (fnx-ew1-security, catalog/aws-config/security-eu.yaml) needs its own collector there.
REGION_SINGLETON_ALLOWANCES = {
    ("AWS Config global-resource recording", "security", "eu-west-1"),
}
# Kinds from RAW_NAMES and SINGLETONS that are unique per account, not per
# region (IAM is global within an account).
ACCOUNT_WIDE = {
    "IAM role", "IAM policy",
    *SINGLETONS.values(), *MAP_SINGLETONS.values(), *REGION_SINGLETONS.values(),
}
# vars keys whose values are names global across accounts and regions.
GLOBAL_KEYS = {"bucket_name", "assets_bucket_name", "domain_prefix"}


def is_deployable(instance: dict) -> bool:
    return (
        backends.is_deployable(instance)
        and backends.ci_apply_role_arn.flag((instance.get("vars") or {}).get("enabled"), "vars.enabled") is not False
    )


def instances_of(stack: dict):
    for name, instance in sorted(((stack.get("components") or {}).get("terraform") or {}).items()):
        if is_deployable(instance):
            yield name, instance


def strings(value, path=()):
    """(path, string) for every string leaf of a vars value."""
    if isinstance(value, dict):
        for key, item in value.items():
            yield from strings(item, path + (str(key),))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from strings(item, path + (str(index),))
    elif isinstance(value, str):
        yield path, value


def secret_names(variables: dict) -> list[str]:
    """secretsmanager's full_path for each secrets entry (components/terraform/secretsmanager/main.tf)."""
    names = []
    for secret in (variables.get("secrets") or {}).values():
        if not isinstance(secret, dict):
            continue
        path = str(secret.get("path") or "").strip("/")
        parts = [variables.get("context_name"), variables.get("environment"), path, secret.get("name")]
        names.append("/".join(str(p) for p in parts if p))
    return names


def created(instance: dict, stage) -> list[tuple]:
    """(kind, value, where) for the account- and region-unique names an instance creates."""
    component, variables = instance.get("component"), instance.get("vars") or {}
    out = []
    for (comp, key), resource in RAW_NAMES.items():
        value = variables.get(key)
        if comp != component or not isinstance(value, str) or not value:
            continue
        out.append((resource, value, f"vars.{key}"))
    if stage != fixtures.FIXTURE_STAGE:
        for (comp, gate, default), resource in SINGLETONS.items():
            if comp == component and backends.ci_apply_role_arn.flag(variables.get(gate), f"vars.{gate}", default) is True:
                out.append((resource, "(one per account)", f"vars.{gate}"))
        for (comp, key), resource in MAP_SINGLETONS.items():
            entries = variables.get(key) if comp == component else None
            for entry_key, entry in sorted((entries or {}).items()):
                service = entry.get("aws_service_name") if isinstance(entry, dict) else None
                if service:
                    out.append((resource, service, f"vars.{key}.{entry_key}"))
        for (comp, key), resource in REGION_SINGLETONS.items():
            if comp == component and variables.get(key, variables.get("region")) == variables.get("region"):
                out.append((resource, "(one per account)", f"vars.{key}"))
    if component == "secretsmanager":
        out += [("secret", secret, "vars.secrets") for secret in secret_names(variables)]
    return out


def group_of(stack: dict):
    for _, instance in instances_of(stack):
        account = ((instance.get("settings") or {}).get("environment") or {}).get("account")
        region = (instance.get("vars") or {}).get("region")
        if account and region:
            return account, region
    return None


def check_groups(stacks: dict) -> list[str]:
    groups, errors = collections.defaultdict(list), []
    for stack_name, stack in sorted(stacks.items()):
        group = group_of(stack)
        if group:
            groups[group].append(stack_name)
        elif next(instances_of(stack), None):
            errors.append(
                f"{stack_name}: no deployable instance sets both settings.environment.account and vars.region, "
                "so its names cannot be checked against the other stacks of its account and region"
            )
    for group, members in sorted(groups.items()):
        where_group = f"account {group[0]}, {group[1]}"
        environments, owners = {}, {}
        for stack_name in sorted(members):
            reported = set()
            for name, instance in instances_of(stacks[stack_name]):
                environment = ((instance.get("vars") or {}).get("tags") or {}).get("Environment")
                if environment:
                    first = environments.setdefault(environment, (stack_name, name))
                    if first[0] != stack_name and environment not in reported:
                        reported.add(environment)
                        errors.append(
                            f"{stack_name}: {name} and {first[0]}: {first[1]} both use tags.Environment "
                            f"{environment!r} in {where_group}: a lane's names must carry its name (settings.prefix)"
                        )
                stage = ((instance.get("settings") or {}).get("context") or {}).get("stage")
                for kind, value, key in created(instance, stage):
                    here = f"{stack_name}: {name} {key}"
                    first = owners.setdefault((kind, value), here)
                    if first != here:
                        errors.append(
                            f"{here} and {first} both create the {kind} {value!r} in {where_group}: "
                            "build it from settings.prefix or the full id ({{ .atmos_stack }})"
                        )
    return errors


def check_account(stacks: dict) -> list[str]:
    """ACCOUNT_WIDE names created in two regions of one account (same-region pairs are
    check_groups')."""
    owners, errors = {}, []
    for stack_name in sorted(stacks):
        group = group_of(stacks[stack_name])
        if not group:
            continue
        account, region = group
        for name, instance in instances_of(stacks[stack_name]):
            stage = ((instance.get("settings") or {}).get("context") or {}).get("stage")
            for kind, value, key in created(instance, stage):
                if kind not in ACCOUNT_WIDE or (kind, account, region) in REGION_SINGLETON_ALLOWANCES:
                    continue
                here = (f"{stack_name}: {name} {key}", region)
                first = owners.setdefault((account, kind, value), here)
                if first[1] != region:
                    errors.append(
                        f"{here[0]} ({region}) and {first[0]} ({first[1]}) both create the {kind} {value!r} "
                        f"in account {account}: IAM names are account-wide, so another region's must carry "
                        "its region code (settings.prefix), and a singleton belongs to one stack"
                    )
    return errors + check_account_environments(stacks)


def check_account_environments(stacks: dict) -> list[str]:
    """ACCOUNT_WIDE_COMPONENTS instances in two regions of one account that share a tags.Environment."""
    owners, errors = {}, []
    for stack_name in sorted(stacks):
        group = group_of(stacks[stack_name])
        if not group:
            continue
        account, region = group
        reported = set()
        for name, instance in instances_of(stacks[stack_name]):
            environment = ((instance.get("vars") or {}).get("tags") or {}).get("Environment")
            if instance.get("component") not in ACCOUNT_WIDE_COMPONENTS or not environment:
                continue
            first = owners.setdefault((account, environment), (stack_name, name, region))
            if first[2] != region and (first[0], environment) not in reported:
                reported.add((first[0], environment))
                errors.append(
                    f"{stack_name}: {name} ({region}) and {first[0]}: {first[1]} ({first[2]}) both use "
                    f"tags.Environment {environment!r} in account {account}: the IAM/S3 names built from it are "
                    "account-wide, so another region's must carry its region code (settings.prefix)"
                )
    return errors


def name_inputs(variables: dict) -> dict:
    return {k: v for k, v in variables.items() if NAME_INPUT.search(k) and k not in SKIP_VARS}


def same_names(a: dict, b: dict, component=None):
    """Why two instances' vars of one component build the same names, or None."""
    shared = [key for key in PRIMARY_NAMES if key in a and key in b and (component, key) not in NOT_PRIMARY]
    for key in shared:
        if a[key] and a[key] == b[key]:
            return f"the same {key} {json.dumps(a[key])}"
    if shared:
        return None
    inputs = name_inputs(a)
    if inputs != name_inputs(b):
        return None
    return f"the same name inputs {json.dumps(inputs, sort_keys=True) if inputs else '(none)'}"


def check_instances(stacks: dict) -> list[str]:
    """Instances of one component in one stack that build the same names."""
    errors = []
    for stack_name, stack in sorted(stacks.items()):
        by_component = collections.defaultdict(list)
        for name, instance in instances_of(stack):
            by_component[str(instance.get("component"))].append((name, instance))
        for component, members in sorted(by_component.items()):
            for index, (name_a, instance_a) in enumerate(members):
                for name_b, instance_b in members[index + 1:]:
                    if org_steps_differ(instance_a, instance_b) or analyzer_kinds_differ(instance_a, instance_b):
                        continue
                    why = same_names(instance_a.get("vars") or {}, instance_b.get("vars") or {}, component)
                    if why:
                        errors.append(
                            f"{stack_name}: {name_a}, {name_b} ({component}) set {why}, so they build the "
                            "same resource names: give each its own name"
                        )
    return errors


def check_global(stacks: dict) -> list[str]:
    errors, owners = [], {}
    for stack_name in sorted(stacks):
        for name, instance in instances_of(stacks[stack_name]):
            for path, text in strings(instance.get("vars") or {}):
                if path and path[-1] in GLOBAL_KEYS and text:
                    here = f"{stack_name}: {name} vars.{'.'.join(path)}"
                    first = owners.setdefault(text, here)
                    if first != here:
                        errors.append(
                            f"{here} and {first} both use the global name {text!r}: "
                            "build it from the full id ({{ .atmos_stack }})"
                        )
    return errors


def check_trusted_providers(stacks: dict) -> list[str]:
    """Enabled aws-iam-role instances that trust the account's GitHub OIDC provider (github_oidc_provider_enabled,
    github_oidc_provider_arn) in an account where no stack has an aws-github-oidc-provider instance to create it."""
    creators, trusting = set(), []
    for stack_name in sorted(stacks):
        for name, instance in instances_of(stacks[stack_name]):
            settings, variables = instance.get("settings") or {}, instance.get("vars") or {}
            account = (settings.get("environment") or {}).get("account")
            stage = (settings.get("context") or {}).get("stage")
            if not account or stage == fixtures.FIXTURE_STAGE:
                continue
            if instance.get("component") == "aws-github-oidc-provider":
                creators.add(account)
            elif (
                instance.get("component") == "aws-iam-role"
                and residency.flag_on(variables.get("github_oidc_provider_enabled"))
                and residency.flag_on(variables.get("enabled", True))
                and variables.get("github_oidc_provider_arn")
            ):
                trusting.append((account, f"{stack_name}: {name}"))
    return [
        f"{where} trusts the account's GitHub OIDC provider (github_oidc_provider_arn) but no stack of account "
        f"{account} creates it: the account's first stack imports catalog/aws-github-oidc-provider/main"
        for account, where in trusting
        if account not in creators
    ]


def org_service_step(instance: dict):
    """(step, error): which of Cloud Posse's three steps an ORG_SERVICES instance runs (main.tf locals)."""
    variables = instance.get("vars") or {}
    tenant, own = residency.tenant_of(instance), residency.own_account(instance)
    admin = variables.get("delegated_administrator_account_name", "core-security")
    management = residency.management_account(instance)
    if not own or not management:
        return None, "sets no settings.environment.account, tenant or management account name: its step cannot be told"
    if not isinstance(variables.get("admin_delegated", False), bool):
        return None, (f"sets admin_delegated {variables['admin_delegated']!r}, not a bool: deploy-full-stack's "
                      "security-org layer selects step 3 by .vars.admin_delegated == true")
    if admin != f"{tenant}-{DELEGATED_ADMIN_ACCOUNT}":
        return None, (f"names delegated administrator {admin!r}: the org services' delegated administrator is "
                      f"{tenant}-{DELEGATED_ADMIN_ACCOUNT}")
    if management != residency.map_root_account(instance):
        return None, (f"names management account {management!r}, not its account_map's root account "
                      f"{residency.map_root_account(instance)!r}: the management account is the root account")
    if own == management:
        return "root", None
    if own != admin:
        return None, (f"is in account {own}, neither the management account ({management}) nor the delegated "
                      f"administrator ({admin}): it creates nothing there")
    if residency.flag_on(variables.get("admin_delegated")):
        return "org-settings", None
    if instance.get("component") == "aws-inspector2":
        return None, "is an aws-inspector2 instance with admin_delegated off: Inspector has no step 1, only org-settings"
    return "delegated-administrator", None


def org_steps_differ(a: dict, b: dict) -> bool:
    """Two ORG_SERVICES instances of one stack running different steps: only step 1 names a resource
    (the detector/hub module), unless create_sns_topic adds the module-level topic to both."""
    if a.get("component") not in residency.ORG_SERVICES or any(
            residency.flag_on((i.get("vars") or {}).get("create_sns_topic")) for i in (a, b)):
        return False
    step_a, step_b = org_service_step(a)[0], org_service_step(b)[0]
    return bool(step_a and step_b and step_a != step_b)


# access-analyzer's analyzer flags and the type each creates (CP main.tf, house account-analyzer_house.tf).
ANALYZER_KINDS = (
    ("accessanalyzer_organization_enabled", "ORGANIZATION"),
    ("accessanalyzer_organization_unused_access_enabled", "ORGANIZATION_UNUSED_ACCESS"),
    ("accessanalyzer_account_enabled", "ACCOUNT"),
)


def analyzer_kinds(instance: dict) -> set:
    variables = instance.get("vars") or {}
    return {kind for flag, kind in ANALYZER_KINDS if residency.flag_on(variables.get(flag))}


def analyzer_kinds_differ(a: dict, b: dict) -> bool:
    """Two access-analyzer instances of one stack creating different analyzer types: each analyzer's name ends in
    its type (<id>-organization, -organization-unused-access, -account), so they share no name (E5c7b: an
    account's ACCOUNT analyzer beside the root step or the delegated administrator's)."""
    if a.get("component") != "access-analyzer" or b.get("component") != "access-analyzer":
        return False
    kinds_a, kinds_b = analyzer_kinds(a), analyzer_kinds(b)
    return bool(kinds_a | kinds_b) and not kinds_a & kinds_b


def check_org_services(stacks: dict) -> list[str]:
    """ORG_SERVICES account singletons: one root (management account), delegated-administrator and
    org-settings (security account) per service and region, and one Security Hub Organizations
    resource policy (an organization singleton) in all."""
    errors, owners, policies, aggregators = [], collections.defaultdict(list), [], collections.defaultdict(list)
    for stack_name in sorted(stacks):
        for name, instance in instances_of(stacks[stack_name]):
            component = instance.get("component")
            stage = ((instance.get("settings") or {}).get("context") or {}).get("stage")
            if component not in residency.ORG_SERVICES or stage == fixtures.FIXTURE_STAGE:
                continue
            where = f"{stack_name}: {name}"
            step, error = org_service_step(instance)
            if error:
                errors.append(f"{where} {error}")
                continue
            owners[(component, step, (instance.get("vars") or {}).get("region"))].append(where)
            if component == "aws-security-hub" and step == "root" and residency.flag_on(
                    (instance.get("vars") or {}).get("organizations_resource_policy_enabled", True)):
                policies.append(where)
            if component == "aws-security-hub" and residency.creates_aggregator(instance):
                aggregators[residency.own_account(instance)].append(where)
    for account, wheres in sorted(aggregators.items()):
        if len(wheres) > 1:
            errors.append(f"{' and '.join(wheres)} all create a Security Hub finding aggregator for {account}: one "
                          "aggregation region per administrator (OQ-SH: us-east-1 aggregates us-east-2)")
    for (component, step, region), wheres in sorted(owners.items()):
        if len(wheres) > 1:
            errors.append(f"{' and '.join(wheres)} are all the {component} {step} step in {region}: one per service "
                          "and region (the delegation, detector/hub and org settings are account singletons)")
    if len(policies) > 1:
        errors.append(f"{' and '.join(policies)} all create the Security Hub Organizations resource policy, an "
                      "organization singleton: set organizations_resource_policy_enabled false in all but one")
    return errors


def check_access_analyzers(stacks: dict) -> list[str]:
    """IAM Access Analyzer (vendored access-analyzer, E5c7) singletons: one analyzer per (account, region, type),
    ACCOUNT included (E5c7b, house account-analyzer_house.tf; deliberately also check-data-residency.py's
    account_analyzer_errors rule, which checks it as residency completeness, this one as a name collision),
    one unused-access analyzer (global) per account and residency, and the delegation
    (organizations_delegated_administrator_enabled) once in all, in the management account."""
    errors, analyzers, unused, delegations = [], collections.defaultdict(list), collections.defaultdict(list), []
    for stack_name in sorted(stacks):
        for name, instance in instances_of(stacks[stack_name]):
            stage = ((instance.get("settings") or {}).get("context") or {}).get("stage")
            variables = instance.get("vars") or {}
            if instance.get("component") != "access-analyzer" or stage == fixtures.FIXTURE_STAGE \
                    or not residency.flag_on(variables.get("enabled", True)):
                continue
            where, account, region = f"{stack_name}: {name}", residency.own_account(instance), variables.get("region")
            for kind in sorted(analyzer_kinds(instance)):
                analyzers[(account, region, kind)].append(where)
            if residency.flag_on(variables.get("accessanalyzer_organization_unused_access_enabled")):
                unused[(account, str(region).startswith(residency.EU_PREFIX))].append(where)
            if residency.flag_on(variables.get("organizations_delegated_administrator_enabled")):
                delegations.append(where)
                if account != residency.map_root_account(instance):
                    errors.append(f"{where} sets organizations_delegated_administrator_enabled in {account}, not the "
                                  f"management account ({residency.map_root_account(instance)}): only the root step "
                                  "delegates Access Analyzer (a delegated administrator's instance keeps it false)")
    for (account, region, kind), wheres in sorted(analyzers.items()):
        if len(wheres) > 1:
            errors.append(f"{' and '.join(wheres)} all create the {kind} analyzer of {account} in {region}: one per "
                          "account, region and type")
    for (account, eu), wheres in sorted(unused.items()):
        if len(wheres) > 1:
            errors.append(f"{' and '.join(wheres)} all create an unused-access analyzer of {account} in the "
                          f"{'EU' if eu else 'US'} residency: it is global (IAM), one per residency")
    if len(delegations) > 1:
        errors.append(f"{' and '.join(delegations)} all delegate Access Analyzer (an organization singleton, global): "
                      "set organizations_delegated_administrator_enabled in one root stack only")
    return errors


def check(stacks: dict) -> list[str]:
    return (
        check_groups(stacks) + check_account(stacks) + check_instances(stacks) + check_global(stacks)
        + check_trusted_providers(stacks) + check_org_services(stacks) + check_access_analyzers(stacks)
    )


def main() -> int:
    stacks = json.load(sys.stdin)
    errors = backends.ci_apply_role_arn.flag_errors(stacks) or check(stacks)
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} name collision(s) between stacks or instances that share an account and region")
        return 1
    print(
        "no two stacks of one account and region share a tags.Environment, no two instances there create "
        "the same name or singleton, every trusted GitHub OIDC provider has a creator, no two regions of an account share a tags.Environment in IAM/S3 names, no two "
        "instances of a component in one stack set the same name, and no S3 bucket or Cognito domain name is "
        "set twice"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
