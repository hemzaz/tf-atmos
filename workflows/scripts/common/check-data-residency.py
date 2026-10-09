#!/usr/bin/env python3
"""Check that GDPR-scoped stacks keep their data, state and dependencies in the EU.

Reads `atmos describe stacks --process-functions=false --format json` on stdin.
EU personal data lives only in EU stacks (owner decision, B5). A stack is GDPR-scoped
when any deployable instance's vars.tags.Compliance contains "gdpr" (EU: "pci-sox-gdpr",
US: "pci-sox") or its vars.region is an eu- region. In a GDPR-scoped stack, every
deployable instance:
  - names only eu- regions: vars.region and every *_region/*_regions var, and the region
    of every ARN in vars (at any depth, through dicts and lists), settings.tfstate
    region/replica_region, the s3 backend.region and remote_state_backend.region, and
    providers.*.region. So a US stack tagged gdpr fails;
  - carries a Compliance tag containing "gdpr" (EU stacks carry pci-sox-gdpr);
  - lists in dependencies.components only GDPR-scoped stacks, and sets no
    settings.depends_on (unused here and retired by Atmos; dependencies.components is
    the one dependency list).
EXEMPTIONS lists the (instance pattern, field) pairs that may name one non-EU region.
Fixture stacks are checked too (KNOWN_BROKEN_FIXTURES relaxes one). Exits 1 on any
violation.

Out of scope: us-east-1 regions hard-coded inside component code (the apigateway
health-check alarm, dns query logging, cloudfront log delivery) are not stack config;
they are reviewed per component.
"""
import fnmatch
import json
import os
import re
import sys
from typing import Any, Iterator, NamedTuple

# The sibling module, also when this file is loaded by path (tests).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fixtures  # noqa: E402

CHECK = "check-data-residency"
GDPR = "gdpr"
EU_PREFIX = "eu-"
REGION = r"[a-z]{2}(?:-[a-z]+)+-\d+"
AWS_REGION = re.compile(rf"^{REGION}$")
REGION_KEY = re.compile(r"(^|_)regions?$")
# Every ARN in a string, also inside a JSON policy document passed as a string var.
# IAM, S3 and Route 53 ARNs have an empty region field, which this does not match.
ARN_REGION = re.compile(rf"(?<![A-Za-z0-9:/_-])arn:aws[a-z-]*:[a-z0-9-]+:({REGION}):")


class Exemption(NamedTuple):
    instance: str  # fnmatch pattern over the instance name (e.g. "apigateway/*")
    field: str  # the dotted path the region sits at (e.g. "vars.health_check_alarm_actions")
    region: str  # the one non-EU region allowed there
    reason: str


# Empty: no EU stack exists yet. The EU DR PR adds
# Exemption("apigateway/*", "vars.health_check_alarm_actions", "us-east-1", ...):
# Route 53 publishes health-check metrics only in us-east-1, so the health-check
# alarm (apigateway main.tf) and its SNS topic live there (metadata only, no
# personal data).
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


def tagged_gdpr(instance: dict) -> bool:
    return GDPR in str(((instance.get("vars") or {}).get("tags") or {}).get("Compliance") or "").lower()


def in_eu(instance: dict) -> bool:
    return str((instance.get("vars") or {}).get("region") or "").startswith(EU_PREFIX)


def gdpr_scoped(stack: dict) -> bool:
    return any(tagged_gdpr(i) or in_eu(i) for i in instances(stack).values())


def region_fields(value: Any, path: str, region_key: bool = False) -> Iterator[tuple[str, str]]:
    """(path, region) for every region under a *_region(s) key and every regional ARN in value.

    A list item reports at its list's path, so an exemption names the var.
    """
    if isinstance(value, dict):
        for key, item in value.items():
            yield from region_fields(item, f"{path}.{key}", bool(REGION_KEY.search(str(key))))
    elif isinstance(value, list):
        for item in value:
            yield from region_fields(item, path, region_key)
    elif isinstance(value, str):
        for arn in ARN_REGION.finditer(value):
            yield path, arn.group(1)
        if region_key and AWS_REGION.match(value):
            yield path, value


def regions(instance: dict) -> Iterator[tuple[str, str]]:
    yield from region_fields(instance.get("vars") or {}, "vars")
    tfstate = (instance.get("settings") or {}).get("tfstate") or {}
    for key in ("region", "replica_region"):
        if isinstance(tfstate.get(key), str):
            yield f"settings.tfstate.{key}", tfstate[key]
    for kind, field in (("backend_type", "backend"), ("remote_state_backend_type", "remote_state_backend")):
        region = (instance.get(field) or {}).get("region")
        if instance.get(kind) == "s3" and isinstance(region, str):
            yield f"{field}.s3.region", region
    for name, provider in sorted((instance.get("providers") or {}).items()):
        if isinstance(provider, dict) and isinstance(provider.get("region"), str):
            yield f"providers.{name}.region", provider["region"]


def exempt(name: str, field: str, region: str, exemptions: tuple) -> bool:
    return any(
        fnmatch.fnmatchcase(name, e.instance) and e.field == field and e.region == region for e in exemptions
    )


def check_instance(stack_name: str, name: str, instance: dict, scoped: set, exemptions: tuple) -> list[str]:
    errors = []
    where = f"{stack_name}: {name}"
    for field, region in regions(instance):
        if not region.startswith(EU_PREFIX) and not exempt(name, field, region, exemptions):
            errors.append(f"{where} {field} is {region!r}, outside the EU, in a GDPR-scoped stack")
    if not tagged_gdpr(instance):
        errors.append(f"{where} is in a GDPR-scoped stack but its tags.Compliance does not contain {GDPR!r}")
    if (instance.get("settings") or {}).get("depends_on"):
        errors.append(f"{where} sets settings.depends_on: list dependencies in dependencies.components")
    for dep in (instance.get("dependencies") or {}).get("components") or []:
        if not isinstance(dep, dict):
            errors.append(f"{where} dependencies.components entry {dep!r} is not a {{component, stack}} map")
            continue
        target = dep.get("stack") or stack_name
        if target not in scoped:
            errors.append(f"{where} depends on {dep.get('component')} in {target}, which is not GDPR-scoped")
    return errors


def check(stacks: dict, exemptions: tuple = EXEMPTIONS) -> list[str]:
    errors = []
    scoped = {name for name, stack in stacks.items() if gdpr_scoped(stack)}
    for stack_name in sorted(scoped):
        for name, instance in sorted(instances(stacks[stack_name]).items()):
            errors += check_instance(stack_name, name, instance, scoped, exemptions)
    return list(dict.fromkeys(errors))


def main() -> int:
    errors = fixtures.fatal(check(json.load(sys.stdin)), CHECK)
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} data residency problem(s)")
        return 1
    print(
        "every GDPR-scoped (gdpr-tagged or eu-) stack is tagged gdpr, names only eu- regions "
        "(vars and their ARNs, settings.tfstate, backends, providers) outside its exemptions "
        "and depends only on GDPR-scoped stacks"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
