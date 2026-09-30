#!/usr/bin/env python3
"""Check that no hosted-runner workflow targets an instance that needs a private EKS API.

Usage: check-cluster-api-ci.py <components/terraform dir> < describe-stacks.json
(`atmos describe stacks --process-functions=false --format json`).

A component whose Terraform configures a kubernetes, helm or kubectl provider
talks to the EKS API server. In a stack whose eks instances all keep
cluster_endpoint_public_access off (its default), a GitHub-hosted runner cannot
reach that server, so every deployable instance of such a component must set
settings.github.actions_enabled: false: terraform-ci.yml, terraform-cd.yml and
drift-detection.yml then skip it and an operator applies it from inside the VPC
(docs/OPERATIONS.md, "In-cluster components").

That operator is an eks map_additional_iam_roles role with system:masters (a
cluster-scoped AmazonEKSClusterAdminPolicy access entry, set in each stack's
components/globals.yaml). In such a stack, every one of those roles must also be
trusted by the stage's state write role (backend/main access_roles.write for
dev/staging, .prod_write for prod), or it cannot write the state: an ERROR. An
eks instance with no such role leaves nobody able to apply the in-cluster
components: a WARN only, while the owner has not supplied the real ARNs (an
access entry for a placeholder role would fail eks/main's apply).

Exits 1 on any ERROR; WARN lines never fail.
"""
import json
import pathlib
import re
import sys

CLUSTER_PROVIDER = re.compile(r'^\s*provider\s+"(kubernetes|helm|kubectl)"', re.MULTILINE)


def cluster_components(components_dir: pathlib.Path) -> set[str]:
    """Component directories whose .tf files configure a cluster-API provider."""
    return {
        tf.parent.name
        for tf in components_dir.glob("*/*.tf")
        if CLUSTER_PROVIDER.search(tf.read_text(encoding="utf-8"))
    }


def is_deployable(instance: dict) -> bool:
    metadata = instance.get("metadata") or {}
    return metadata.get("type") != "abstract" and metadata.get("enabled", True) is not False


def is_public(value) -> bool:
    # A Go template (dev's "{{ .settings.environment.eks_public_access }}")
    # renders to a string.
    return value is True or str(value).strip().lower() == "true"


def deployable_instances(stack: dict) -> dict:
    return {
        name: instance
        for name, instance in ((stack.get("components") or {}).get("terraform") or {}).items()
        if is_deployable(instance or {})
    }


def is_private(instances: dict) -> bool:
    return any(
        instance.get("component") == "eks"
        and not is_public((instance.get("vars") or {}).get("cluster_endpoint_public_access"))
        for instance in instances.values()
    )


def check(stacks: dict, cluster: set[str]) -> list[str]:
    errors = []
    for stack_name, stack in sorted(stacks.items()):
        instances = deployable_instances(stack)
        if not is_private(instances):
            continue
        for name, instance in sorted(instances.items()):
            if instance.get("component") not in cluster:
                continue
            github = (instance.get("settings") or {}).get("github") or {}
            if github.get("actions_enabled") is not False:
                errors.append(
                    f"{stack_name}: {name} ({instance.get('component')}) needs the private EKS API "
                    "but does not set settings.github.actions_enabled: false"
                )
    return errors


def admin_role_arns(eks_instance: dict) -> list[str]:
    """The eks instance's map_additional_iam_roles that get cluster admin."""
    return [
        role.get("rolearn")
        for role in (eks_instance.get("vars") or {}).get("map_additional_iam_roles") or []
        if "system:masters" in (role.get("groups") or [])
    ]


def backend_write_principals(stacks: dict) -> "dict | None":
    """access_roles key -> allowed_principal_arns of the one backend instance; None if absent."""
    for stack in stacks.values():
        for instance in deployable_instances(stack).values():
            if instance.get("component") == "backend":
                roles = (instance.get("vars") or {}).get("access_roles") or {}
                return {key: set(role.get("allowed_principal_arns") or []) for key, role in roles.items()}
    return None


def check_operators(stacks: dict, cluster: set[str]) -> tuple[list[str], list[str]]:
    """(errors, warnings) about who can apply the in-cluster components of private stacks."""
    errors, warnings = [], []
    backend = backend_write_principals(stacks)
    for stack_name, stack in sorted(stacks.items()):
        instances = deployable_instances(stack)
        if not is_private(instances):
            continue
        in_cluster = sorted(name for name, i in instances.items() if i.get("component") in cluster)
        if not in_cluster:
            continue
        for name, instance in sorted(instances.items()):
            if instance.get("component") != "eks":
                continue
            arns = admin_role_arns(instance)
            if not arns:
                warnings.append(
                    f"{stack_name}: {name} has no map_additional_iam_roles entry with system:masters, "
                    f"so no operator can apply {', '.join(in_cluster)} (set it in the stack's "
                    "components/globals.yaml)"
                )
                continue
            if backend is None:
                continue
            stage = ((instance.get("settings") or {}).get("context") or {}).get("stage")
            key = "prod_write" if stage == "prod" else "write"
            for arn in arns:
                if arn not in backend.get(key, set()):
                    errors.append(
                        f"{stack_name}: {name} admin role {arn} is not in backend/main "
                        f"access_roles.{key} allowed_principal_arns, so it cannot write this "
                        "stack's state"
                    )
    return errors, warnings


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    cluster = cluster_components(pathlib.Path(sys.argv[1]))
    stacks = json.load(sys.stdin)
    errors = check(stacks, cluster)
    operator_errors, warnings = check_operators(stacks, cluster)
    for warning in warnings:
        print(f"WARN {warning}")
    for error in errors + operator_errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} in-cluster instance(s) still run on hosted runners")
    if operator_errors:
        print(f"{len(operator_errors)} cluster admin role(s) cannot write their stack's state")
    if errors or operator_errors:
        return 1
    print(
        f"every instance of {', '.join(sorted(cluster))} in a stack with a private EKS endpoint "
        "has settings.github.actions_enabled: false, and every cluster admin role there can "
        "write its stack's state"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
