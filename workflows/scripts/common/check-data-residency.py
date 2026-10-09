#!/usr/bin/env python3
"""Check that GDPR-scoped stacks keep their data, state and dependencies in the EU.

Reads `atmos describe stacks --process-functions=false --format json` on stdin.
EU personal data lives only in EU stacks (owner decision, B5). A stack is GDPR-scoped
when any deployable instance's vars.tags.Compliance contains "gdpr" (EU: "pci-sox-gdpr",
US: "pci-sox"). Every deployable instance of one names only eu- regions (vars.region and
every *_region/*_regions var at any depth, settings.tfstate.region/replica_region, the
s3 backend.region; so a US stack tagged gdpr fails), and every settings.depends_on and
dependencies.components entry points at a GDPR-scoped stack. EXEMPTIONS lists the
(instance pattern, field) pairs that may name one non-EU region. Fixture stacks are
checked too (KNOWN_BROKEN_FIXTURES relaxes one). Exits 1 on any violation.
"""
import fnmatch
import json
import os
import re
import sys
from typing import Any, Iterator, NamedTuple, Optional

# The sibling module, also when this file is loaded by path (tests).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fixtures  # noqa: E402

CHECK = "check-data-residency"
GDPR = "gdpr"
EU_PREFIX = "eu-"
AWS_REGION = re.compile(r"^[a-z]{2}(-[a-z]+)+-\d$")
REGION_KEY = re.compile(r"(^|_)regions?$")
CONTEXT_KEYS = ("namespace", "tenant", "environment", "stage", "name")


class Exemption(NamedTuple):
    instance: str  # fnmatch pattern over the instance name (e.g. "sns/r53-health-*")
    field: str  # the dotted path the region sits at (e.g. "vars.region")
    region: str  # the one non-EU region allowed there
    reason: str


# Empty: no EU stack exists yet. The EU DR PR adds its Route 53 health-check
# alarm topic: Route 53 publishes health-check metrics only in us-east-1, so the
# alarm and its SNS topic must live there (metadata only, no personal data).
EXEMPTIONS: tuple = ()


def is_deployable(instance: dict) -> bool:
    metadata = instance.get("metadata") or {}
    return metadata.get("type") != "abstract" and metadata.get("enabled", True) is not False


def instances(stack: dict) -> dict:
    return {
        name: instance
        for name, instance in ((stack.get("components") or {}).get("terraform") or {}).items()
        if is_deployable(instance or {})
    }


def gdpr_scoped(stack: dict) -> bool:
    return any(
        GDPR in str(((instance.get("vars") or {}).get("tags") or {}).get("Compliance") or "").lower()
        for instance in instances(stack).values()
    )


def region_fields(value: Any, path: str) -> Iterator[tuple[str, str]]:
    """(path, region) for every AWS region under a *_region/*_regions key of value, at any depth."""
    if not isinstance(value, dict):
        return
    for key, item in value.items():
        where = f"{path}.{key}"
        if REGION_KEY.search(str(key)):
            for region in item if isinstance(item, list) else [item]:
                if isinstance(region, str) and AWS_REGION.match(region):
                    yield where, region
        yield from region_fields(item, where)


def regions(instance: dict) -> Iterator[tuple[str, str]]:
    yield from region_fields(instance.get("vars") or {}, "vars")
    tfstate = (instance.get("settings") or {}).get("tfstate") or {}
    for key in ("region", "replica_region"):
        if isinstance(tfstate.get(key), str):
            yield f"settings.tfstate.{key}", tfstate[key]
    if instance.get("backend_type") == "s3":
        region = (instance.get("backend") or {}).get("region")
        if isinstance(region, str):
            yield "backend.s3.region", region


def exempt(name: str, field: str, region: str, exemptions: tuple) -> bool:
    return any(
        fnmatch.fnmatchcase(name, e.instance) and e.field == field and e.region == region for e in exemptions
    )


def context_of(stack: dict) -> dict:
    for instance in instances(stack).values():
        context = (instance.get("settings") or {}).get("context") or {}
        if context:
            return {key: context.get(key) for key in CONTEXT_KEYS}
    return {}


def dependencies(stack_name: str, instance: dict, contexts: dict) -> Iterator[tuple[str, Optional[str]]]:
    """(component, target stack or None when unresolvable) for every dependency entry."""
    depends_on = (instance.get("settings") or {}).get("depends_on") or {}
    entries = list(depends_on.values() if isinstance(depends_on, dict) else depends_on)
    entries += (instance.get("dependencies") or {}).get("components") or []
    for dep in entries:
        if not isinstance(dep, dict):
            continue
        if dep.get("stack"):
            yield dep.get("component"), dep["stack"]
        elif any(dep.get(key) for key in CONTEXT_KEYS):
            wanted = {**contexts.get(stack_name, {}), **{k: dep[k] for k in CONTEXT_KEYS if dep.get(k)}}
            yield dep.get("component"), next((s for s, c in contexts.items() if c == wanted), None)
        else:
            yield dep.get("component"), stack_name


def check(stacks: dict, exemptions: tuple = EXEMPTIONS) -> list[str]:
    errors = []
    scoped = {name for name, stack in stacks.items() if gdpr_scoped(stack)}
    contexts = {name: context_of(stack) for name, stack in stacks.items()}
    for stack_name in sorted(scoped):
        for name, instance in sorted(instances(stacks[stack_name]).items()):
            where = f"{stack_name}: {name}"
            for field, region in regions(instance):
                if not region.startswith(EU_PREFIX) and not exempt(name, field, region, exemptions):
                    errors.append(f"{where} {field} is {region!r}, outside the EU, in a GDPR-scoped stack")
            for component, target in dependencies(stack_name, instance, contexts):
                if target is None:
                    errors.append(f"{where} depends on {component}, whose stack does not resolve")
                elif target not in scoped:
                    errors.append(f"{where} depends on {component} in {target}, which is not GDPR-scoped")
    return list(dict.fromkeys(errors))


def main() -> int:
    errors = fixtures.fatal(check(json.load(sys.stdin)), CHECK)
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} data residency problem(s)")
        return 1
    print(
        "every GDPR-scoped stack names only eu- regions (vars, settings.tfstate, s3 backend) outside "
        "its exemptions and depends only on GDPR-scoped stacks"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
