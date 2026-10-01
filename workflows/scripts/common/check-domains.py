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
    custom domain's alias record goes into zone_id); and when certificate_arn
    reads `!terraform.state <acm instance> .certificate_arns.<key>`, that
    certificate's domain_name or a SAN must cover domain_name (exactly, or as a
    `*.` wildcard of exactly one label). A literal certificate_arn cannot be
    followed offline: it is reported as a warning, not checked.
An acm/apigateway zone_id must be `!terraform.state <dns instance> [<stack>]
.zone_ids.<key>`. With --process-functions=false it stays symbolic, so it is
resolved by following it to that deployable dns instance's zones.<key>.name.
A literal zone id cannot be resolved offline: it is reported as a warning, not
checked.
A name written into a public zone must not also fall inside a more specific
public zone of the same stack (data.services.<domain> belongs to the
data.services zone, not to services.<domain>): once that zone is delegated,
the record in the parent zone is never answered.
Every public zone below another public zone of the same stack must be
delegated from it: either zones.<key>.parent_zone names that parent zone in the
same dns instance, or the parent zone has an NS record for the zone's name
whose records read `!terraform.state <child dns instance> .zone_name_servers.<key>`.
A stack's top-level public zone is delegated from outside the stack (manual).
Exits 1 on any violation.
"""
import importlib.util
import json
import pathlib
import re
import sys
from typing import NamedTuple, Optional

_spec = importlib.util.spec_from_file_location(
    "check_dependencies", pathlib.Path(__file__).with_name("check-dependencies.py")
)
check_dependencies = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_dependencies)


class Zone(NamedTuple):
    instance: str
    key: str
    name: str
    config: dict

    @property
    def label(self) -> str:
        return f"{self.instance} zone {self.key}"


def dicts(value) -> dict:
    """The dict entries of a map (null or malformed entries skipped)."""
    return {k: v for k, v in (value or {}).items() if isinstance(v, dict)} if isinstance(value, dict) else {}


def normalize(name: str) -> str:
    """Lower-case, no trailing dot, no leading wildcard label."""
    name = name.strip().lower().rstrip(".")
    return name[2:] if name.startswith("*.") else name


def in_zone(name: str, zone: str) -> bool:
    name, zone = normalize(name), normalize(zone)
    return name == zone or name.endswith("." + zone)


def covers(pattern: str, name: str) -> bool:
    """Whether a certificate name covers name: exactly, or `*.` for exactly one label."""
    pattern, name = pattern.strip().lower().rstrip("."), name.strip().lower().rstrip(".")
    if pattern == name:
        return True
    if not pattern.startswith("*."):
        return False
    label, _, rest = name.partition(".")
    return bool(label) and label != "*" and rest == pattern[2:]


def state_reference(stacks: dict, stack_name: str, value, output: str, module: str):
    """Follow `!terraform.state <instance> [<stack>] .<output>.<key>` to (instance name, target, key).

    None for a value that is not a state reference; a str when it cannot be followed.
    """
    if not isinstance(value, str) or not value.startswith(check_dependencies.FUNCTIONS):
        return None
    refs = list(check_dependencies.references(value))
    if not refs:
        return f"`{value}` is not a !terraform.state reference this check understands"
    component, stack = refs[0]
    tokens = value.split()[2:]
    if stack is not None:
        tokens = tokens[1:]
    expression = " ".join(tokens).strip("'\"")
    match = re.match(rf'^\.{output}(?:\.(?P<bare>[A-Za-z0-9_-]+)|\["(?P<quoted>[^"]+)"\])$', expression)
    if match is None:
        return f"`{value}` does not read .{output}.<key> of a {module} instance"
    target_stack = stack or stack_name
    target = stacks.get(target_stack, {}).get("components", {}).get("terraform", {}).get(component)
    if target is None:
        return f"`{value}` reads {component} in {target_stack}, which does not exist"
    if not check_dependencies.is_deployable(target):
        return f"`{value}` reads {component}, which is abstract or disabled"
    if check_dependencies.module_name(component, target) != module:
        return f"`{value}` reads {component}, which is not a {module} instance"
    return component, target, match.group("bare") or match.group("quoted")


def resolve_zone(stacks: dict, stack_name: str, zone_id) -> tuple[Optional[dict], Optional[str]]:
    """(zone, None), or (None, why it cannot be resolved), or (None, None) for a literal id."""
    ref = state_reference(stacks, stack_name, zone_id, "zone_ids", "dns")
    if ref is None or isinstance(ref, str):
        return None, ref
    component, target, key = ref
    zone = dicts((target.get("vars") or {}).get("zones")).get(key) or {}
    if not isinstance(zone.get("name"), str):
        return None, f"reads {component} .zone_ids.{key}, but {component} has no zone {key!r}"
    return zone, None


def is_public(zone: dict) -> bool:
    """A zone with no vpc_associations is public (the dns component's rule)."""
    return not zone.get("vpc_associations")


def public_zones(instances: dict) -> list[Zone]:
    """Every public zone of the stack's deployable dns instances."""
    return [
        Zone(name, key, zone["name"], zone)
        for name, instance in sorted(instances.items())
        if check_dependencies.is_deployable(instance) and check_dependencies.module_name(name, instance) == "dns"
        for key, zone in sorted(dicts((instance.get("vars") or {}).get("zones")).items())
        if isinstance(zone.get("name"), str) and is_public(zone)
    ]


def parent_of(name: str, zones: list[Zone]) -> Optional[Zone]:
    """The most specific public zone strictly above name, if any."""
    above = [z for z in zones if normalize(z.name) != normalize(name) and in_zone(name, z.name)]
    return max(above, key=lambda z: len(normalize(z.name)), default=None)


def placement_error(name: str, zone: dict, zones: list[Zone], ns: bool = False) -> Optional[str]:
    """Why name does not belong in zone, or None. ns: an NS record, which may delegate a subzone's apex."""
    if not in_zone(name, zone["name"]):
        return f"{name} is not in its zone ({zone['name']})"
    if not is_public(zone):
        return None
    for other in zones:
        closer = normalize(other.name) != normalize(zone["name"]) and in_zone(other.name, zone["name"])
        delegation = ns and normalize(name) == normalize(other.name)
        if closer and in_zone(name, other.name) and not delegation:
            return f"{name} is in {zone['name']} but belongs to the more specific public zone {other.name} ({other.label})"
    return None


def dns_errors(where: str, variables: dict, zones: list[Zone]) -> list[str]:
    errors = []
    own = dicts(variables.get("zones"))
    for record_id, record in sorted(dicts(variables.get("records")).items()):
        name, zone_key = record.get("name"), record.get("zone_name")
        if not isinstance(name, str):
            continue
        zone = own.get(zone_key) or {}
        if not isinstance(zone.get("name"), str):
            errors.append(f"{where} record {record_id}: zone_name {zone_key!r} is not a key of zones")
            continue
        problem = placement_error(name, zone, zones, ns=str(record.get("type", "")).upper() == "NS")
        if problem:
            errors.append(f"{where} record {record_id} (zone {zone_key}): {problem}")
    return errors


def delegation_errors(stacks: dict, stack_name: str, zones: list[Zone]) -> list[str]:
    """Every public zone below another public zone of the stack is delegated from it."""
    instances = stacks[stack_name].get("components", {}).get("terraform", {})
    errors = []
    for zone in zones:
        parent = parent_of(zone.name, zones)
        where = f"{stack_name}: {zone.label} ({zone.name})"
        declared = zone.config.get("parent_zone")
        if parent is None:
            if declared is not None:
                errors.append(f"{where}: parent_zone {declared!r} but no public zone of the stack is above it")
            continue
        if declared is not None:
            if (parent.instance, parent.key) != (zone.instance, declared):
                errors.append(f"{where}: parent_zone {declared!r}, but its parent zone is {parent.name} ({parent.label})")
            continue
        found = []
        records = dicts(((instances.get(parent.instance) or {}).get("vars") or {}).get("records"))
        for record_id, record in sorted(records.items()):
            if (
                record.get("zone_name") == parent.key
                and str(record.get("type", "")).upper() == "NS"
                and isinstance(record.get("name"), str)
                and normalize(record["name"]) == normalize(zone.name)
            ):
                found.append((record_id, record.get("records")))
        want = f"!terraform.state {zone.instance} .zone_name_servers.{zone.key}"
        if not found:
            same = f", or set zones.{zone.key}.parent_zone: {parent.key}" if parent.instance == zone.instance else ""
            errors.append(
                f"{where} is not delegated from its parent zone {parent.name} ({parent.label}): "
                f"add an NS record there whose records are `{want}`{same}"
            )
            continue
        for record_id, values in found:
            ref = state_reference(stacks, stack_name, values, "zone_name_servers", "dns")
            if not isinstance(ref, tuple) or (ref[0], ref[2]) != (zone.instance, zone.key):
                errors.append(
                    f"{where}: NS record {parent.instance} {record_id} must read `{want}` (got {values!r})"
                )
    return errors


def zoned_names(module: str, variables: dict) -> list[tuple[str, str]]:
    """(what, name) pairs this instance writes into its zone_id."""
    if module == "acm":
        names = []
        for key, cert in sorted(dicts(variables.get("dns_domains")).items()):
            if (cert.get("validation_method") or "DNS") != "DNS":
                continue
            for name in [cert.get("domain_name")] + list(cert.get("subject_alternative_names") or []):
                if isinstance(name, str):
                    names.append((f"certificate {key}", name))
        return names
    if module == "apigateway" and isinstance(variables.get("domain_name"), str):
        return [("domain_name", variables["domain_name"])]
    return []


def certificate_problem(stacks: dict, stack_name: str, variables: dict) -> tuple[Optional[str], Optional[str]]:
    """(why an apigateway's certificate_arn does not cover its domain_name, or None; a warning, or None)."""
    domain = variables.get("domain_name")
    if not isinstance(domain, str):
        return None, None
    arn = variables.get("certificate_arn")
    ref = state_reference(stacks, stack_name, arn, "certificate_arns", "acm")
    if ref is None:
        if isinstance(arn, str) and arn.strip():
            return None, f"certificate_arn {arn!r} is a literal certificate ARN; domain_name {domain} is not checked against it"
        return None, None
    if isinstance(ref, str):
        return f"certificate_arn {ref}", None
    return certificate_error(ref, domain), None


def certificate_error(ref: tuple, domain: str) -> Optional[str]:
    """Why the acm certificate ref reads does not cover domain, or None."""
    component, target, key = ref
    cert = dicts((target.get("vars") or {}).get("dns_domains")).get(key)
    if cert is None:
        return f"certificate_arn reads {component} .certificate_arns.{key}, but {component} has no certificate {key!r}"
    names = [n for n in [cert.get("domain_name")] + list(cert.get("subject_alternative_names") or []) if isinstance(n, str)]
    if not any(covers(n, domain) for n in names):
        return f"certificate {component} {key} ({', '.join(names)}) does not cover domain_name {domain}"
    return None


def check(stacks: dict) -> tuple[list[str], list[str]]:
    """(errors, warnings)."""
    errors, warnings = [], []
    for stack_name, stack in sorted(stacks.items()):
        instances = stack.get("components", {}).get("terraform", {})
        zones = public_zones(instances)
        errors += delegation_errors(stacks, stack_name, zones)
        for name, instance in sorted(instances.items()):
            if not check_dependencies.is_deployable(instance):
                continue
            module = check_dependencies.module_name(name, instance)
            variables = instance.get("vars") or {}
            where = f"{stack_name}: {name}"
            if module == "dns":
                errors += dns_errors(where, variables, zones)
                continue
            if module == "apigateway":
                problem, warning = certificate_problem(stacks, stack_name, variables)
                if problem:
                    errors.append(f"{where}: {problem}")
                if warning:
                    warnings.append(f"{where}: {warning}")
            names = zoned_names(module, variables)
            zone_id = variables.get("zone_id")
            if not names or zone_id in (None, ""):
                continue
            zone, problem = resolve_zone(stacks, stack_name, zone_id)
            if problem:
                errors.append(f"{where}: zone_id {problem}")
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
    errors = check_dependencies.fixtures.fatal(errors, "check-domains")
    for warning in warnings:
        print(f"WARN {warning}")
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"{len(errors)} domain problem(s)")
        return 1
    print(
        "every dns record, acm domain/SAN and apigateway custom domain is inside the zone it is written to, "
        "every public subzone is delegated from its parent zone, and every apigateway certificate covers its domain"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
