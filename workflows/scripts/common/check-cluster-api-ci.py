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
(docs/OPERATIONS.md, "In-cluster components"). Exits 1 on any violation.
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


def check(stacks: dict, cluster: set[str]) -> list[str]:
    errors = []
    for stack_name, stack in sorted(stacks.items()):
        instances = {
            name: instance
            for name, instance in ((stack.get("components") or {}).get("terraform") or {}).items()
            if is_deployable(instance or {})
        }
        private = any(
            instance.get("component") == "eks"
            and not is_public((instance.get("vars") or {}).get("cluster_endpoint_public_access"))
            for instance in instances.values()
        )
        if not private:
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


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    cluster = cluster_components(pathlib.Path(sys.argv[1]))
    errors = check(json.load(sys.stdin), cluster)
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} in-cluster instance(s) still run on hosted runners")
        return 1
    print(
        f"every instance of {', '.join(sorted(cluster))} in a stack with a private EKS endpoint "
        "has settings.github.actions_enabled: false"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
