#!/usr/bin/env python3
"""Check that stacks sharing an account and region share no resource name.

Usage: check-lane-names.py < describe-stacks.json
(`atmos describe stacks --process-functions=false --format json`).

A lane (settings.context.name) deploys beside its stage stack in the same
account and region: fnx-ue1-dev-serverless beside fnx-ue1-dev. Its names carry
the lane, Cloud Posse null-label style: the full id is the stack name and the
environment-derived prefix, settings.prefix, is <region code>-<name>
(stacks/orgs/fnx/_defaults.yaml), which tags.Environment, and so every
component's names, start with. For the stacks of one tenant, region code and
stage, this fails:
  - two stacks whose deployable instances share a tags.Environment value
    (components name their resources <Environment>-<name>);
  - a vars string that two stacks both set and that starts with the region
    code or the stage's full id (<code>-..., <tenant>-<code>-<stage>...), the
    form of every name the stacks build themselves;
  - a secretsmanager secret name (context_name/environment/path/name) that two
    stacks both create.
And, across every stack (any account or region), names that are global in AWS:
  - an S3 bucket_name or a Cognito domain_prefix (vars keys GLOBAL_KEYS, at any
    depth) that two stacks both set.
Exits 1 on any collision.
"""
import collections
import json
import sys

SKIP_VARS = {"tags", "description"}
# vars keys whose values are names global across accounts and regions.
GLOBAL_KEYS = {"bucket_name", "domain_prefix"}


def is_deployable(instance: dict) -> bool:
    metadata = instance.get("metadata") or {}
    return metadata.get("type") != "abstract" and metadata.get("enabled", True) is not False


def context(instance: dict) -> dict:
    return (instance.get("settings") or {}).get("context") or {}


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


def names_of(stack: dict) -> dict:
    """{kind: {name: where}} for the names a stack's deployable instances create."""
    names = collections.defaultdict(dict)
    for name, instance in sorted(((stack.get("components") or {}).get("terraform") or {}).items()):
        if not is_deployable(instance):
            continue
        ctx = context(instance)
        variables = instance.get("vars") or {}
        environment = (variables.get("tags") or {}).get("Environment")
        if environment:
            names["tags.Environment"].setdefault(environment, name)
        prefixes = tuple(
            p for p in (f"{ctx.get('environment')}-", f"{ctx.get('tenant')}-{ctx.get('environment')}-{ctx.get('stage')}")
            if "None" not in p
        )
        for key, value in variables.items():
            if key in SKIP_VARS:
                continue
            for path, text in strings(value, (key,)):
                if prefixes and text.startswith(prefixes) and " " not in text:
                    names["name"].setdefault(text, f"{name} vars.{'.'.join(path)}")
        if instance.get("component") == "secretsmanager":
            for secret in secret_names(variables):
                names["secret"].setdefault(secret, name)
    return names


def global_names(stack: dict) -> dict:
    """{name: where} for the account- and region-global names a stack's deployable instances set."""
    names = {}
    for name, instance in sorted(((stack.get("components") or {}).get("terraform") or {}).items()):
        if not is_deployable(instance):
            continue
        for path, text in strings(instance.get("vars") or {}):
            if path and path[-1] in GLOBAL_KEYS and text:
                names.setdefault(text, f"{name} vars.{'.'.join(path)}")
    return names


def check_global(stacks: dict) -> list[str]:
    errors, owners = [], {}
    for stack_name in sorted(stacks):
        for value, where in sorted(global_names(stacks[stack_name]).items()):
            first = owners.setdefault(value, (stack_name, where))
            if first[0] != stack_name:
                errors.append(
                    f"{stack_name}: {where} and {first[0]}: {first[1]} both use the global name {value!r}: "
                    "build it from the full id ({{ .atmos_stack }})"
                )
    return errors


def check(stacks: dict) -> list[str]:
    groups = collections.defaultdict(list)
    for stack_name, stack in stacks.items():
        instances = (stack.get("components") or {}).get("terraform") or {}
        ctx = next((context(i) for i in instances.values() if is_deployable(i) and context(i)), None)
        if ctx:
            groups[(ctx.get("tenant"), ctx.get("environment"), ctx.get("stage"))].append(stack_name)
    errors = []
    for group, members in sorted(groups.items(), key=lambda item: tuple(map(str, item[0]))):
        owners = {}
        for stack_name in sorted(members):
            for kind, names in sorted(names_of(stacks[stack_name]).items()):
                for value, where in sorted(names.items()):
                    first = owners.setdefault((kind, value), (stack_name, where))
                    if first[0] != stack_name:
                        errors.append(
                            f"{stack_name}: {where} and {first[0]}: {first[1]} both use {kind} {value!r} "
                            f"in {'-'.join(map(str, group))}: a lane's names must carry its name (settings.prefix)"
                        )
    return errors + check_global(stacks)


def main() -> int:
    errors = check(json.load(sys.stdin))
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} name collision(s) between stacks of one account and region")
        return 1
    print("no two stacks of one tenant, region and stage share a tags.Environment, a name they build or a secret name, and no two stacks share an S3 bucket or Cognito domain name")
    return 0


if __name__ == "__main__":
    sys.exit(main())
