#!/usr/bin/env python3
"""Check that no hosted-runner workflow targets an instance that needs a private EKS API.

Usage: check-cluster-api-ci.py <components/terraform dir> < describe-stacks.json
(`atmos describe stacks --process-functions=false --format json`).

A component whose Terraform configures a kubernetes, helm or kubectl provider
talks to the EKS API server. In a stack whose eks instances all keep
cluster_endpoint_public_access off (its default), a GitHub-hosted runner cannot
reach that server, so every deployable instance of such a component must
either set settings.github.actions_enabled: false (CI skips it and an operator
applies it from inside the VPC; docs/OPERATIONS.md, "In-cluster components")
or settings.github.runner: in-vpc (CI runs it on the self-hosted runners in the
VPC). settings.github.runner, when set, is hosted or in-vpc.

An in-vpc instance runs on the runners labelled settings.github.runner_label,
by default the stack's full id, its name <tenant>-<environment>-<stage>[-<name>]
(the github-runners catalog's runner_labels is {{ .atmos_stack }}). The stack must
have a deployable github-runners instance whose runner_labels hold that label,
and every eks instance the in-cluster instance depends on must admit that
runner pool (`!terraform.state <pool> .security_group_id` in its
allowed_security_group_ids): an ERROR otherwise. A pool in another vpc is
checked for peering and NACLs like a bastion (below).

That operator is an eks map_additional_iam_roles role with system:masters (a
cluster-scoped AmazonEKSClusterAdminPolicy access entry, set in each stack's
components/globals.yaml). In such a stack, every one of those roles must also be
trusted by the stage's state write role (backend/main access_roles.write for
dev/staging, .prod_write for prod), or it cannot write the state: an ERROR, as
is a missing deployable backend/main (nothing to check against). An eks
instance with no such role leaves nobody able to apply the in-cluster instances
that depend on it: one WARN per stack, while the owner has not supplied the real
ARNs (an access entry for a placeholder role would fail eks/main's apply).

The operator reaches a private endpoint through the bastion's SSM port-forward,
so such an eks instance (private endpoint, in-cluster instances depending on
it) must admit it on TCP 443: an empty allowed_security_group_ids and
allowed_cidr_blocks leaves no network path, an ERROR. A non-empty
allowed_cidr_blocks is a smoke check only: nothing checks that its CIDRs hold
the bastion. For each allowed_security_group_ids entry read from an ec2 or
github-runners instance (`!terraform.state <instance> .security_group_id`) whose vpc is not
the cluster's (the vpc its subnet_ids are read from), the stack must also have
a deployable network instance peering the two vpcs, and each vpc's
private_network_acl_peer_cidr_blocks must hold the other's
ipv4_primary_cidr_block (unless manage_network_acls is false): an ERROR
otherwise. Literal security group IDs and cross-stack reads are not followed.

Exits 1 on any ERROR; WARN lines never fail.
"""
import json
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import fixtures  # noqa: E402

CLUSTER_PROVIDER = re.compile(r'^\s*provider\s+"(kubernetes|helm|kubectl)"', re.MULTILINE)
RUNNER_COMPONENT = "github-runners"
RUNNER_MODES = ("hosted", "in-vpc")
# Instances whose security group may be an operator or CI path into a cluster.
ADMITTED_SOURCE_COMPONENTS = ("ec2", RUNNER_COMPONENT)


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
            runner = github.get("runner")
            if runner is not None and runner not in RUNNER_MODES:
                errors.append(f"{stack_name}: {name} settings.github.runner is {runner!r}, not one of {', '.join(RUNNER_MODES)}")
            elif github.get("actions_enabled") is not False and runner != "in-vpc":
                errors.append(
                    f"{stack_name}: {name} ({instance.get('component')}) needs the private EKS API "
                    "but sets neither settings.github.actions_enabled: false nor settings.github.runner: in-vpc"
                )
    return errors


def runner_label(stack_name: str, instance: dict) -> str:
    """The label an in-vpc instance's CI jobs ask for: settings.github.runner_label, else the full id (the stack name)."""
    settings = instance.get("settings") or {}
    return (settings.get("github") or {}).get("runner_label") or stack_name


def check_runner_paths(stacks: dict, cluster: set[str]) -> list[str]:
    """In-vpc in-cluster instances whose label has no runner pool, or whose clusters do not admit it."""
    errors = []
    for stack_name, stack in sorted(stacks.items()):
        instances = deployable_instances(stack)
        if not is_private(instances):
            continue
        for name, instance in sorted(instances.items()):
            github = (instance.get("settings") or {}).get("github") or {}
            if instance.get("component") not in cluster or github.get("runner") != "in-vpc":
                continue
            label = runner_label(stack_name, instance)
            pools = sorted(
                pool for pool, i in instances.items()
                if i.get("component") == RUNNER_COMPONENT and label in ((i.get("vars") or {}).get("runner_labels") or [])
            )
            if not pools:
                errors.append(
                    f"{stack_name}: {name} runs on in-vpc runners labelled {label!r}, but no deployable "
                    f"{RUNNER_COMPONENT} instance registers that label"
                )
                continue
            for dep in (instance.get("dependencies") or {}).get("components") or []:
                eks = instances.get(dep.get("component")) if not dep.get("stack") else None
                if not eks or eks.get("component") != "eks":
                    continue
                admitted = {state_source(sg) for sg in (eks.get("vars") or {}).get("allowed_security_group_ids") or []}
                if not admitted.intersection(pools):
                    errors.append(
                        f"{stack_name}: {name} runs on the {label!r} runners ({', '.join(pools)}), but "
                        f"{dep['component']} does not admit them (add `!terraform.state {pools[0]} "
                        ".security_group_id` to its allowed_security_group_ids)"
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
    """access_roles key -> allowed_principal_arns of the deployable backend/main; None if absent."""
    for stack in stacks.values():
        instance = deployable_instances(stack).get("backend/main")
        if instance is not None and instance.get("component") == "backend":
            roles = (instance.get("vars") or {}).get("access_roles") or {}
            return {key: set(role.get("allowed_principal_arns") or []) for key, role in roles.items()}
    return None


def cluster_dependents(instances: dict, cluster: set[str]) -> dict[str, list[str]]:
    """eks instance -> the in-cluster instances whose dependencies.components name it."""
    dependents = {name: [] for name, i in instances.items() if i.get("component") == "eks"}
    for name, instance in sorted(instances.items()):
        if instance.get("component") not in cluster:
            continue
        for dep in (instance.get("dependencies") or {}).get("components") or []:
            if not dep.get("stack") and dep.get("component") in dependents:
                dependents[dep["component"]].append(name)
    return dependents


def check_operators(stacks: dict, cluster: set[str]) -> tuple[list[str], list[str]]:
    """(errors, warnings) about who can apply the in-cluster components of private stacks."""
    errors, warnings = [], []
    backend = backend_write_principals(stacks)
    for stack_name, stack in sorted(stacks.items()):
        instances = deployable_instances(stack)
        if not is_private(instances):
            continue
        if not any(i.get("component") in cluster for i in instances.values()):
            continue
        if backend is None:
            errors.append(
                f"{stack_name}: no deployable backend/main instance found, so its cluster admin "
                "roles cannot be checked against the state write roles"
            )
        unmanaged = []
        for name, dependents in sorted(cluster_dependents(instances, cluster).items()):
            instance = instances[name]
            arns = admin_role_arns(instance)
            if not arns:
                if dependents:
                    unmanaged.append(f"{name} ({', '.join(dependents)})")
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
        if unmanaged:
            warnings.append(
                f"{stack_name}: no map_additional_iam_roles entry with system:masters on "
                f"{'; '.join(unmanaged)}, so nobody can apply those in-cluster instances (set it "
                "in the stack's components/globals.yaml)"
            )
    return errors, warnings


STATE_READ = re.compile(r"^!terraform\.state\s+(\S+)\s+(\S+)\s*$")


def state_source(value) -> "str | None":
    """The same-stack instance a `!terraform.state <instance> <output>` read names, else None."""
    match = STATE_READ.match(value) if isinstance(value, str) else None
    return match.group(1) if match else None


def is_peered(instances: dict, vpc_a: str, vpc_b: str) -> bool:
    """A deployable network instance peers the two vpc instances (either direction)."""
    for instance in instances.values():
        v = instance.get("vars") or {}
        if instance.get("component") != "network" or v.get("create_vpc_peering") is False:
            continue
        ends = {state_source(v.get("requester_vpc_id")), state_source(v.get("accepter_vpc_id"))}
        if ends == {vpc_a, vpc_b}:
            return True
    return False


def nacl_gaps(instances: dict, vpc_a: str, vpc_b: str) -> list[str]:
    """Each vpc whose private NACL does not admit the other's CIDR."""
    gaps = []
    for vpc, peer in ((vpc_a, vpc_b), (vpc_b, vpc_a)):
        v = (instances.get(vpc) or {}).get("vars") or {}
        if v.get("manage_network_acls") is False:
            continue
        peer_cidr = ((instances.get(peer) or {}).get("vars") or {}).get("ipv4_primary_cidr_block")
        if peer_cidr not in (v.get("private_network_acl_peer_cidr_blocks") or []):
            gaps.append(f"{vpc} private_network_acl_peer_cidr_blocks lacks {peer} ({peer_cidr})")
    return gaps


def cross_vpc_errors(stack_name: str, instances: dict, name: str, eks_vars: dict) -> list[str]:
    """A bastion or runner pool in another vpc needs a peering and both vpcs' NACLs to admit each other."""
    errors = []
    cluster_vpc = state_source(eks_vars.get("subnet_ids"))
    for sg in eks_vars.get("allowed_security_group_ids") or []:
        source = state_source(sg)
        source_vars = (instances.get(source) or {}).get("vars") or {}
        if cluster_vpc is None or (instances.get(source) or {}).get("component") not in ADMITTED_SOURCE_COMPONENTS:
            continue
        source_vpc = state_source(source_vars.get("vpc_id")) or state_source(source_vars.get("subnet"))
        if source_vpc is None or source_vpc == cluster_vpc:
            continue
        where = f"{stack_name}: {name} (in {cluster_vpc}) admits {source} (in {source_vpc})"
        if not is_peered(instances, cluster_vpc, source_vpc):
            errors.append(f"{where}, but no network instance peers {cluster_vpc} and {source_vpc}")
        for gap in nacl_gaps(instances, cluster_vpc, source_vpc):
            errors.append(f"{where}, but {gap}, so the private NACLs drop the traffic")
    return errors


def check_network_paths(stacks: dict, cluster: set[str]) -> list[str]:
    """Private eks instances with in-cluster dependents but no network path for the operator."""
    errors = []
    for stack_name, stack in sorted(stacks.items()):
        instances = deployable_instances(stack)
        if not is_private(instances):
            continue
        for name, dependents in sorted(cluster_dependents(instances, cluster).items()):
            eks_vars = instances[name].get("vars") or {}
            if not dependents or is_public(eks_vars.get("cluster_endpoint_public_access")):
                continue
            if not (eks_vars.get("allowed_security_group_ids") or eks_vars.get("allowed_cidr_blocks")):
                errors.append(
                    f"{stack_name}: {name} has a private endpoint and in-cluster instances "
                    f"({', '.join(dependents)}) but empty allowed_security_group_ids and "
                    "allowed_cidr_blocks, so no operator can reach its API (allow the bastion's "
                    "security group)"
                )
                continue
            errors.extend(cross_vpc_errors(stack_name, instances, name, eks_vars))
    return errors


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    cluster = cluster_components(pathlib.Path(sys.argv[1]))
    stacks = json.load(sys.stdin)
    errors = fixtures.fatal(check(stacks, cluster), "check-cluster-api-ci")
    operator_errors, warnings = check_operators(stacks, cluster)
    operator_errors = fixtures.fatal(operator_errors, "check-cluster-api-ci")
    network_errors = fixtures.fatal(
        check_network_paths(stacks, cluster) + check_runner_paths(stacks, cluster), "check-cluster-api-ci"
    )
    for warning in warnings:
        print(f"WARN {warning}")
    for error in errors + operator_errors + network_errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} in-cluster instance(s) still run on hosted runners")
    if operator_errors:
        print(f"{len(operator_errors)} cluster admin role(s) cannot write their stack's state")
    if network_errors:
        print(f"{len(network_errors)} private cluster path(s) missing: an operator's or the in-vpc runners'")
    if errors or operator_errors or network_errors:
        return 1
    print(
        f"every instance of {', '.join(sorted(cluster))} in a stack with a private EKS endpoint "
        "runs on in-vpc runners or sets settings.github.actions_enabled: false, every cluster admin "
        "role there can write its stack's state, and every private cluster they use admits an "
        "operator path and the in-vpc runners its instances run on"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
