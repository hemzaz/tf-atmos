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
(vars.region). Within a group this fails:
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
OIDC provider.
Within one stack, two deployable instances of one component that set the same
name inputs (NAME_INPUT: name, identifier, *_name, *_prefix, domains, zones,
...) build the same <Environment>-<input> names, so they must differ in one
(vpc/main and vpc/services differ in name).
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
    groups = collections.defaultdict(list)
    for stack_name, stack in stacks.items():
        group = group_of(stack)
        if group:
            groups[group].append(stack_name)
    errors = []
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
    return errors


def check_instances(stacks: dict) -> list[str]:
    """Instances of one component in one stack with the same name inputs."""
    errors = []
    for stack_name, stack in sorted(stacks.items()):
        by_inputs = collections.defaultdict(list)
        for name, instance in instances_of(stack):
            variables = instance.get("vars") or {}
            inputs = json.dumps(
                {k: v for k, v in variables.items() if NAME_INPUT.search(k) and k not in SKIP_VARS},
                sort_keys=True,
            )
            by_inputs[(instance.get("component"), inputs)].append(name)
        for (component, inputs), names in sorted(by_inputs.items(), key=lambda item: (str(item[0][0]), item[0][1])):
            if len(names) > 1:
                errors.append(
                    f"{stack_name}: {', '.join(names)} ({component}) set the same name inputs "
                    f"{inputs if inputs != '{}' else '(none)'}, so they build the same resource names: "
                    "give each its own name"
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
        "the same name or singleton, no two instances of a component in one stack set the same name inputs, "
        "and no S3 bucket or Cognito domain name is set twice"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
