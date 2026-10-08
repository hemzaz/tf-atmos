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
    GitHub OIDC provider, the Auto Scaling service-linked role); stage
    fixtures, never deployed and each standalone, are exempt;
  - two secretsmanager instances creating the same secret name
    (context_name/environment/path/name).
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
domain prefix (GLOBAL_KEYS, at any depth of vars) set twice.
Exits 1 on any collision.
"""
import collections
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fixtures  # noqa: E402

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
# region).
ACCOUNT_WIDE_COMPONENTS = frozenset({
    "alb", "awsconfig", "backup", "batch", "cloudtrail", "cost-optimization", "ec2", "ecs-service", "eks",
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
}
# Kinds from RAW_NAMES and SINGLETONS that are unique per account, not per
# region (IAM is global within an account).
ACCOUNT_WIDE = {"IAM role", "IAM policy", "IAM CI role prefix", *SINGLETONS.values()}
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
            by_component[str(instance.get("component"))].append((name, instance.get("vars") or {}))
        for component, members in sorted(by_component.items()):
            for index, (name_a, vars_a) in enumerate(members):
                for name_b, vars_b in members[index + 1:]:
                    why = same_names(vars_a, vars_b, component)
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


def check(stacks: dict) -> list[str]:
    return check_groups(stacks) + check_account(stacks) + check_instances(stacks) + check_global(stacks)


def main() -> int:
    errors = check(json.load(sys.stdin))
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} name collision(s) between stacks or instances that share an account and region")
        return 1
    print(
        "no two stacks of one account and region share a tags.Environment, no two instances there create "
        "the same name or singleton, no two regions of an account share a tags.Environment in IAM/S3 names, no two "
        "instances of a component in one stack set the same name, and no S3 bucket or Cognito domain name is "
        "set twice"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
