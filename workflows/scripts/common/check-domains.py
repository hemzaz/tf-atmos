#!/usr/bin/env python3
"""Check that every DNS name sits inside the Route 53 zone it is written to.

Reads `atmos describe stacks --process-functions=false --format json` on stdin.
For each enabled, non-abstract instance, by root module:
  - dns: records.<id>.zone_name must be a key of zones, and records.<id>.name
    must be that zone's name or a name below it;
  - acm: the domain_name and every subject_alternative_names entry of each
    DNS-validated certificate (a leading `*.` removed) must be the zone's name
    or below it: ACM's validation records for those names go into zone_id;
  - apigateway: domain_name, when domain_name and zone_id are both set (the
    custom domain's alias record goes into zone_id).
An acm/apigateway zone_id must be `!terraform.state <dns instance> [<stack>]
.zone_ids.<key>`. With --process-functions=false it stays symbolic, so it is
resolved by following it to that dns instance's zones.<key>.name. A literal
zone id cannot be resolved offline: it is reported as a warning, not checked.
A name written into a public zone must not also fall inside a more specific
public zone of the same stack (data.services.<domain> belongs to the
data.services zone, not to services.<domain>): once that zone is delegated,
the record in the parent zone is never answered.
Exits 1 on any violation.
"""
import importlib.util
import json
import pathlib
import re
import sys
from typing import Optional

_spec = importlib.util.spec_from_file_location(
    "check_dependencies", pathlib.Path(__file__).with_name("check-dependencies.py")
)
check_dependencies = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_dependencies)

ZONE_KEY = re.compile(r'^\.zone_ids(?:\.(?P<bare>[A-Za-z0-9_-]+)|\["(?P<quoted>[^"]+)"\])$')


def normalize(name: str) -> str:
    """Lower-case, no trailing dot, no leading wildcard label."""
    name = name.strip().lower().rstrip(".")
    return name[2:] if name.startswith("*.") else name


def in_zone(name: str, zone: str) -> bool:
    name, zone = normalize(name), normalize(zone)
    return name == zone or name.endswith("." + zone)


def zone_reference(value: str) -> Optional[tuple[str, Optional[str], str]]:
    """(dns instance, stack or None, expression) of a !terraform.state zone_id, else None."""
    if not isinstance(value, str) or not value.startswith(check_dependencies.FUNCTIONS):
        return None
    refs = list(check_dependencies.references(value))
    if not refs:
        return None
    component, stack = refs[0]
    tokens = value.split()[2:]
    if stack is not None:
        tokens = tokens[1:]
    return component, stack, " ".join(tokens).strip("'\"")


def resolve_zone(stacks: dict, stack_name: str, zone_id) -> tuple[Optional[dict], Optional[str]]:
    """(zone, None), or (None, why it cannot be resolved), or (None, None) for a literal id."""
    ref = zone_reference(zone_id)
    if ref is None:
        return None, None
    component, stack, expression = ref
    target_stack = stack or stack_name
    match = ZONE_KEY.match(expression)
    if match is None:
        return None, f"zone_id `{zone_id}` does not read .zone_ids.<key> of a dns instance"
    key = match.group("bare") or match.group("quoted")
    target = stacks.get(target_stack, {}).get("components", {}).get("terraform", {}).get(component)
    if target is None:
        return None, f"zone_id reads {component} in {target_stack}, which does not exist"
    if check_dependencies.module_name(component, target) != "dns":
        return None, f"zone_id reads {component}, which is not a dns instance"
    zone = ((target.get("vars") or {}).get("zones") or {}).get(key) or {}
    if not isinstance(zone.get("name"), str):
        return None, f"zone_id reads {component} .zone_ids.{key}, but {component} has no zone {key!r}"
    return zone, None


def is_public(zone: dict) -> bool:
    """A zone with no vpc_associations is public (the dns component's rule)."""
    return not zone.get("vpc_associations")


def public_zones(instances: dict) -> list[tuple[str, str]]:
    """(label, zone name) of every public zone of the stack's deployable dns instances."""
    return [
        (f"{name} zone {key}", zone["name"])
        for name, instance in sorted(instances.items())
        if check_dependencies.is_deployable(instance) and check_dependencies.module_name(name, instance) == "dns"
        for key, zone in sorted(((instance.get("vars") or {}).get("zones") or {}).items())
        if isinstance(zone, dict) and isinstance(zone.get("name"), str) and is_public(zone)
    ]


def placement_error(name: str, zone: dict, zones: list[tuple[str, str]]) -> Optional[str]:
    """Why name does not belong in zone, or None."""
    if not in_zone(name, zone["name"]):
        return f"{name} is not in its zone ({zone['name']})"
    if not is_public(zone):
        return None
    for label, other in zones:
        closer = normalize(other) != normalize(zone["name"]) and in_zone(other, zone["name"])
        if closer and in_zone(name, other):
            return f"{name} is in {zone['name']} but belongs to the more specific public zone {other} ({label})"
    return None


def dns_errors(where: str, variables: dict, zones: list[tuple[str, str]]) -> list[str]:
    errors = []
    own = variables.get("zones") or {}
    for record_id, record in sorted((variables.get("records") or {}).items()):
        name, zone_key = record.get("name"), record.get("zone_name")
        if not isinstance(name, str):
            continue
        zone = own.get(zone_key) or {}
        if not isinstance(zone.get("name"), str):
            errors.append(f"{where} record {record_id}: zone_name {zone_key!r} is not a key of zones")
            continue
        problem = placement_error(name, zone, zones)
        if problem:
            errors.append(f"{where} record {record_id} (zone {zone_key}): {problem}")
    return errors


def zoned_names(module: str, variables: dict) -> list[tuple[str, str]]:
    """(what, name) pairs this instance writes into its zone_id."""
    if module == "acm":
        names = []
        for key, cert in sorted((variables.get("dns_domains") or {}).items()):
            if (cert.get("validation_method") or "DNS") != "DNS":
                continue
            for name in [cert.get("domain_name")] + list(cert.get("subject_alternative_names") or []):
                if isinstance(name, str):
                    names.append((f"certificate {key}", name))
        return names
    if module == "apigateway" and isinstance(variables.get("domain_name"), str):
        return [("domain_name", variables["domain_name"])]
    return []


def check(stacks: dict) -> tuple[list[str], list[str]]:
    """(errors, warnings)."""
    errors, warnings = [], []
    for stack_name, stack in sorted(stacks.items()):
        instances = stack.get("components", {}).get("terraform", {})
        zones = public_zones(instances)
        for name, instance in sorted(instances.items()):
            if not check_dependencies.is_deployable(instance):
                continue
            module = check_dependencies.module_name(name, instance)
            variables = instance.get("vars") or {}
            where = f"{stack_name}: {name}"
            if module == "dns":
                errors += dns_errors(where, variables, zones)
                continue
            names = zoned_names(module, variables)
            zone_id = variables.get("zone_id")
            if not names or zone_id in (None, ""):
                continue
            zone, problem = resolve_zone(stacks, stack_name, zone_id)
            if problem:
                errors.append(f"{where}: {problem}")
            elif zone is None:
                warnings.append(f"{where}: zone_id {zone_id!r} is a literal zone id; its names are not checked")
            else:
                for what, domain in names:
                    problem = placement_error(domain, zone, zones)
                    if problem:
                        errors.append(f"{where} {what}: {problem}")
    return errors, warnings


def main() -> int:
    errors, warnings = check(json.load(sys.stdin))
    for warning in warnings:
        print(f"WARN {warning}")
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} domain problem(s)")
        return 1
    print("every dns record, acm domain/SAN and apigateway custom domain is inside the zone it is written to")
    return 0


if __name__ == "__main__":
    sys.exit(main())
