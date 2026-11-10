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
    VERBATIM (RAW_NAMES: kms alias_name, iam policy_name, ecs cluster_name,
    dynamodb table_name, ...), whatever its prefix. Only creating keys count:
    a key that names an existing resource (cluster_name in eks-addons, a
    lane's reference to its stage's cluster) is not compared, and a gated key
    counts only while its instance creates the resource (iam policy_name
    with create_cross_account_role);
  - two instances that create the same account singleton (SINGLETONS: the
    GitHub OIDC provider, the Auto Scaling service-linked role, the
    multi-region CloudTrail trail, CloudTrail's global-service-event
    recording, AWS Config's global-resource recording, the IAM account alias
    and the S3 account public access block), whichever instance creates it:
    the vendored aws-cloudtrail (multi-region with global events unless set
    false, CP defaults) and aws-config (its global-resource collector, the
    instance whose global_resource_collector_region is its stack's region,
    or unset: REGION_SINGLETONS);
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
organization singleton. Two steps of one service in one stack are not a
same-name pair (only step 1 names a resource) unless one sets create_sns_topic.
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
iam instance that trusts the GitHub OIDC provider (github_oidc_provider_arn,
not creating it) while no stack of the account creates one, which deleting the
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
# are global and carry no region). Not iam (its names are RAW_NAMES), backend
# (built from its bucket name) or apigateway-account (its role name carries the
# region). Nor the vendored aws-cloudtrail and aws-config: they name their IAM
# roles from the null-label id (vars.context), whose environment is the region
# code, not from tags.Environment.
ACCOUNT_WIDE_COMPONENTS = frozenset({
    "alb", "apigateway", "backup", "batch", "cost-optimization", "ec2", "ecs-service", "eks",
    "eks-addons", "external-secrets", "firehose", "github-runners", "glue", "lambda", "monitoring", "rds",
    "s3", "security-monitoring", "stepfunctions", "vpc",
})
# (component, key) -> (resource, gate): keys the component uses verbatim in an
# account- or region-unique name. A gate (var, default) must be true for the
# instance to create it.
RAW_NAMES = {
    ("kms", "alias_name"): ("KMS alias", None),
    ("kms", "name_prefix"): ("KMS key name prefix", None),
    ("cognito", "name_prefix"): ("Cognito user pool", None),
    ("network", "name_prefix"): ("network name prefix", None),
    ("iam", "cross_account_role_name"): ("IAM role", ("create_cross_account_role", True)),
    ("iam", "policy_name"): ("IAM policy", ("create_cross_account_role", True)),
    ("iam", "ci_role_name_prefix"): ("IAM CI role prefix", ("github_oidc_enabled", False)),
    ("dynamodb", "table_name"): ("DynamoDB table", None),
    ("ecs", "cluster_name"): ("ECS cluster", None),
    ("waf", "metric_name"): ("WAF metric", None),
    ("apigateway", "domain_name"): ("API Gateway custom domain", None),
}
# (component, gate var, default) -> account singleton it creates when true.
SINGLETONS = {
    ("iam", "github_oidc_create_provider", False): "GitHub OIDC provider",
    ("iam", "enable_autoscaling_service_linked_role", False): "Auto Scaling service-linked role",
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
# (component, var) -> account singleton it creates when var is its stack's
# vars.region (or unset): the vendored aws-config records global resource types
# (IAM) only in its global_resource_collector_region.
REGION_SINGLETONS = {
    ("aws-config", "global_resource_collector_region"): "AWS Config global-resource recording",
}
# Kinds from RAW_NAMES and SINGLETONS that are unique per account, not per
# region (IAM is global within an account).
ACCOUNT_WIDE = {"IAM role", "IAM policy", "IAM CI role prefix", *SINGLETONS.values(), *REGION_SINGLETONS.values()}
# vars keys whose values are names global across accounts and regions.
GLOBAL_KEYS = {"bucket_name", "assets_bucket_name", "domain_prefix"}


def is_deployable(instance: dict) -> bool:
    metadata = instance.get("metadata") or {}
    return (
        metadata.get("type") != "abstract"
        and metadata.get("enabled", True) is not False
        and (instance.get("vars") or {}).get("enabled") is not False
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
    for (comp, key), (resource, gate) in RAW_NAMES.items():
        value = variables.get(key)
        if comp != component or not isinstance(value, str) or not value:
            continue
        if gate and variables.get(gate[0], gate[1]) is not True:
            continue
        out.append((resource, value, f"vars.{key}"))
    if stage != fixtures.FIXTURE_STAGE:
        for (comp, gate, default), resource in SINGLETONS.items():
            if comp == component and variables.get(gate, default) is True:
                out.append((resource, "(one per account)", f"vars.{gate}"))
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
                if kind not in ACCOUNT_WIDE:
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
                    if org_steps_differ(instance_a, instance_b):
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
    """iam instances that trust an existing GitHub OIDC provider (github_oidc_provider_arn,
    github_oidc_create_provider false) in an account where no stack creates one."""
    creators, trusting = set(), []
    for stack_name in sorted(stacks):
        for name, instance in instances_of(stacks[stack_name]):
            settings, variables = instance.get("settings") or {}, instance.get("vars") or {}
            account = (settings.get("environment") or {}).get("account")
            stage = (settings.get("context") or {}).get("stage")
            if instance.get("component") != "iam" or not account or stage == fixtures.FIXTURE_STAGE:
                continue
            if variables.get("github_oidc_create_provider", False) is True:
                creators.add(account)
            elif variables.get("github_oidc_provider_arn"):
                trusting.append((account, f"{stack_name}: {name}"))
    return [
        f"{where} trusts the account's GitHub OIDC provider (github_oidc_provider_arn) but no stack of account "
        f"{account} creates it: one stack per account sets github_oidc_create_provider: true"
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


def check_org_services(stacks: dict) -> list[str]:
    """ORG_SERVICES account singletons: one root (management account), delegated-administrator and
    org-settings (security account) per service and region, and one Security Hub Organizations
    resource policy (an organization singleton) in all."""
    errors, owners, policies = [], collections.defaultdict(list), []
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
    for (component, step, region), wheres in sorted(owners.items()):
        if len(wheres) > 1:
            errors.append(f"{' and '.join(wheres)} are all the {component} {step} step in {region}: one per service "
                          "and region (the delegation, detector/hub and org settings are account singletons)")
    if len(policies) > 1:
        errors.append(f"{' and '.join(policies)} all create the Security Hub Organizations resource policy, an "
                      "organization singleton: set organizations_resource_policy_enabled false in all but one")
    return errors


def check(stacks: dict) -> list[str]:
    return (
        check_groups(stacks) + check_account(stacks) + check_instances(stacks) + check_global(stacks)
        + check_trusted_providers(stacks) + check_org_services(stacks)
    )


def main() -> int:
    errors = check(json.load(sys.stdin))
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
