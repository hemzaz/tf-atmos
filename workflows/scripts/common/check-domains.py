#!/usr/bin/env python3
"""Check that every DNS name sits inside the Route 53 zone it is written to.

Reads `atmos describe stacks --process-functions=false --format json` on stdin.
For each enabled, non-abstract instance, by root module:
  - dns: records.<id>.zone_name must be a key of zones, and records.<id>.name
    must be that zone's name or a name below it;
  - acm: the domain_name and every subject_alternative_names entry of each
    DNS-validated certificate (a leading `*.` removed) must be the zone's name
    or below it: ACM's validation records for those names go into zone_id. A
    certificate with process_domain_validation_options false writes no record:
    each of its names (x and *.x share one) must instead be carried by a
    processed DNS certificate of an acm instance in its dependencies.components,
    in the same account (settings.environment.account), whose record it waits on;
    an instance on either side with no account is an error (fail closed);
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
Vendored zones are public zones too: aws-dns-primary domain_names (roots, never below a
stack zone) and aws-dns-delegated <subdomain>.<zone_name> (unless private), which writes its
own NS record into zone_name: a deployable public zone of some stack and, in its own stack,
its closest parent. A zone_id may read an aws-dns-delegated .default_dns_zone_id (its first
zone), and a dns record's zone_name may be an external_zones key (by name or such a zone_id).
A public zone name is held once per stack, and an aws-dns-delegated zone by one stack.
CloudWatch Logs allows 10 account-scoped resource policies per region and account: per
account (settings.environment.account) and region, the ones the house components create
(a query-logging dns instance: one in us-east-1 for its own zones, one for its DNS-account
zones; a logging waf with manage_log_resource_policy: one in its region, us-east-1 for
CLOUDFRONT; an unset bool takes its Terraform default, true) stay within LOG_POLICY_LIMIT. A
DNS-account policy counts in the account dns_account_assume_role_arn's id names (via
settings.account_map.full_account_map or settings.environment.account_id: an unknown id fails,
an id several names share counts in each), or in the instance's own account with no role.
Fixture stacks are never deployed and not counted.
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


# Cloud Posse's vendored DNS components (components/terraform/<kind>).
PRIMARY, DELEGATED = "aws-dns-primary", "aws-dns-delegated"


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


def flag_on(value) -> bool:
    """Whether Terraform reads value as a true bool (check-data-residency's rule)."""
    return value is not None and value is not False and str(value).strip().lower() != "false"


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


def state_reference(stacks: dict, stack_name: str, value, output: str, module: str, keyed: bool = True):
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
    key = r'(?:\.(?P<bare>[A-Za-z0-9_-]+)|\["(?P<quoted>[^"]+)"\])' if keyed else ""
    match = re.match(rf"^\.{output}{key}$", expression)
    if match is None:
        return f"`{value}` does not read .{output}{'.<key>' if keyed else ''} of a {module} instance"
    target_stack = stack or stack_name
    target = stacks.get(target_stack, {}).get("components", {}).get("terraform", {}).get(component)
    if target is None:
        return f"`{value}` reads {component} in {target_stack}, which does not exist"
    if not check_dependencies.is_deployable(target):
        return f"`{value}` reads {component}, which is abstract or disabled"
    if check_dependencies.module_name(component, target) != module:
        return f"`{value}` reads {component}, which is not a {module} instance"
    return component, target, (match.group("bare") or match.group("quoted")) if keyed else None


def resolve_zone(stacks: dict, stack_name: str, zone_id) -> tuple[Optional[dict], Optional[str]]:
    """(zone, None), or (None, why it cannot be resolved), or (None, None) for a literal id."""
    ref = state_reference(stacks, stack_name, zone_id, "default_dns_zone_id", DELEGATED, keyed=False)
    if isinstance(ref, str) and "does not read" not in ref:
        return None, ref
    if isinstance(ref, tuple):
        first = next(iter(cp_zones(ref[0], ref[1], private=True)), None)
        if first is None:
            return None, f"reads {ref[0]} .default_dns_zone_id, but {ref[0]} has no zone_config entry"
        if not is_public(first.config):
            return None, f"reads {ref[0]} .default_dns_zone_id, a private zone (dns_private_zone_enabled)"
        return first.config, None
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


def cp_zones(name: str, instance: dict, private: bool = False) -> list[Zone]:
    """The zones of an aws-dns-primary or aws-dns-delegated instance (its private ones only with private)."""
    module, variables = check_dependencies.module_name(name, instance), instance.get("vars") or {}
    if module == PRIMARY:
        return [Zone(name, d, d, {"name": d, "kind": PRIMARY}) for d in variables.get("domain_names") or [] if isinstance(d, str)]
    is_private = flag_on(variables.get("dns_private_zone_enabled"))
    if module != DELEGATED or (is_private and not private):
        return []
    return [
        Zone(name, z["subdomain"], f"{z['subdomain']}.{z['zone_name']}", {
            "name": f"{z['subdomain']}.{z['zone_name']}", "kind": DELEGATED, "zone_name": z["zone_name"],
            "vpc_associations": ["private"] if is_private else [],
            "writes_ns": variables.get("create_root_delegation") is None or flag_on(variables["create_root_delegation"]),
        })
        for z in variables.get("zone_config") or []
        if isinstance(z, dict) and isinstance(z.get("subdomain"), str) and isinstance(z.get("zone_name"), str)
    ]


def public_zones(instances: dict) -> list[Zone]:
    """Every public zone of the stack's deployable dns, aws-dns-primary and aws-dns-delegated instances."""
    return [
        Zone(name, key, zone["name"], zone)
        for name, instance in sorted(instances.items())
        if check_dependencies.is_deployable(instance) and check_dependencies.module_name(name, instance) == "dns"
        for key, zone in sorted(dicts((instance.get("vars") or {}).get("zones")).items())
        if isinstance(zone.get("name"), str) and is_public(zone)
    ] + [z for name, i in sorted(instances.items()) if check_dependencies.is_deployable(i) for z in cp_zones(name, i)]


def record_zone(stacks: dict, stack_name: str, variables: dict, key, everywhere=None) -> tuple[Optional[dict], Optional[str]]:
    """The zone a dns record's zone_name names (zones, else external_zones), or (None, why)."""
    own = dicts(variables.get("zones")).get(key) or {}
    if isinstance(own.get("name"), str):
        return own, None
    external = dicts(variables.get("external_zones")).get(key)
    if external is None:
        return None, f"zone_name {key!r} is not a key of zones or external_zones"
    if isinstance(external.get("name"), str):
        if everywhere is not None and normalize(external["name"]) not in everywhere:
            return None, f"external_zones.{key}.name {external['name']} is no deployable public zone of any stack"
        return {"name": external["name"]}, None
    zone, problem = resolve_zone(stacks, stack_name, external.get("zone_id"))
    if zone is not None:
        return zone, None
    return None, f"external_zones.{key}.zone_id {problem or 'is a literal zone id: its records are not checked'}"


def parent_of(name: str, zones: list[Zone]) -> Optional[Zone]:
    """The most specific public zone strictly above name, if any."""
    above = [z for z in zones if normalize(z.name) != normalize(name) and in_zone(name, z.name)]
    return max(above, key=lambda z: len(normalize(z.name)), default=None)


def placement_error(name: str, zone: dict, zones: list[Zone], ns: bool = False) -> Optional[str]:
    """Why name does not belong in zone, or None.

    ns: an NS or DS record, which may sit at a subzone's apex in its parent (the delegation and,
    with DNSSEC, its DS record).
    """
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


def dns_errors(stacks: dict, stack_name: str, where: str, variables: dict, zones: list[Zone], everywhere: set) -> tuple[list, list]:
    """(errors, warnings) of a dns instance's records."""
    errors, warnings = [], []
    for record_id, record in sorted(dicts(variables.get("records")).items()):
        name, zone_key = record.get("name"), record.get("zone_name")
        if not isinstance(name, str):
            continue
        zone, problem = record_zone(stacks, stack_name, variables, zone_key, everywhere)
        if zone is None:
            literal = problem and problem.endswith("not checked")
            (warnings if literal else errors).append(f"{where} record {record_id}: {problem}")
            continue
        problem = placement_error(name, zone, zones, ns=str(record.get("type", "")).upper() in ("NS", "DS"))
        if problem:
            errors.append(f"{where} record {record_id} (zone {zone_key}): {problem}")
    return errors, warnings


def cp_delegation_error(zone: Zone, parent: Optional[Zone], everywhere: set) -> Optional[str]:
    """Why a vendored zone is not delegated as its kind delegates, or None."""
    if zone.config["kind"] == PRIMARY:
        return None if parent is None else f"an {PRIMARY} zone is a root, but sits below {parent.name} ({parent.label})"
    target = zone.config["zone_name"]
    if not zone.config["writes_ns"]:
        return None if parent is None else f"is below {parent.name} ({parent.label}) but sets create_root_delegation: false"
    if normalize(target) not in everywhere:
        return f"writes its NS record into zone_name {target}, which no deployable public zone of any stack holds"
    if parent is not None and normalize(parent.name) != normalize(target):
        return f"writes its NS record into {target}, but its closest parent zone in the stack is {parent.name} ({parent.label})"
    return None


def delegation_errors(stacks: dict, stack_name: str, zones: list[Zone], everywhere: set = frozenset()) -> list[str]:
    """Every public zone below another public zone of the stack is delegated from it."""
    instances = stacks[stack_name].get("components", {}).get("terraform", {})
    errors = []
    for zone in zones:
        parent = parent_of(zone.name, zones)
        where = f"{stack_name}: {zone.label} ({zone.name})"
        if "kind" in zone.config:
            problem = cp_delegation_error(zone, parent, everywhere)
            errors += [f"{where} {problem}"] if problem else []
            continue
        declared = zone.config.get("parent_zone")
        if parent is None:
            if declared is not None:
                errors.append(f"{where}: parent_zone {declared!r} but no public zone of the stack is above it")
            continue
        if declared is not None:
            if (parent.instance, parent.key) != (zone.instance, declared):
                errors.append(f"{where}: parent_zone {declared!r}, but its parent zone is {parent.name} ({parent.label})")
            continue
        # The NS record may sit in any dns instance whose record zone is the parent zone
        # (its own zones.<key>, or an external_zones entry naming a vendored zone).
        found = []
        for writer, spec in sorted(instances.items()):
            if not check_dependencies.is_deployable(spec) or check_dependencies.module_name(writer, spec) != "dns":
                continue
            variables = spec.get("vars") or {}
            for record_id, record in sorted(dicts(variables.get("records")).items()):
                if str(record.get("type", "")).upper() != "NS" or not isinstance(record.get("name"), str):
                    continue
                target, _ = record_zone(stacks, stack_name, variables, record.get("zone_name"))
                if target and normalize(target["name"]) == normalize(parent.name) and normalize(record["name"]) == normalize(zone.name):
                    found.append((f"{writer} {record_id}", record.get("records")))
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
                    f"{where}: NS record {record_id} must read `{want}` (got {values!r})"
                )
    return errors


def is_dns(cert: dict) -> bool:
    return (cert.get("validation_method") or "DNS") == "DNS"


def processes(cert: dict) -> bool:
    """Whether an acm certificate writes its own validation records (the module's default: true)."""
    return cert.get("process_domain_validation_options") is not False


def cert_names(cert: dict) -> list[str]:
    return [n for n in [cert.get("domain_name")] + list(cert.get("subject_alternative_names") or []) if isinstance(n, str)]


def account_of(instance: dict):
    return ((instance.get("settings") or {}).get("environment") or {}).get("account")


def borrowed_validation_errors(stacks: dict, stack_name: str, instance: dict) -> list[str]:
    """Why a DNS certificate with process_domain_validation_options false has no record to wait on.

    Each of its names must be carried by a processed DNS certificate of an acm
    instance listed in this instance's dependencies.components, in the same
    account: ACM gives x and *.x the same validation CNAME, the same in every
    certificate of one account, so that instance's record validates it.
    Otherwise the apply waits 45 minutes for a record nobody writes.
    """
    unprocessed = [
        (key, cert) for key, cert in sorted(dicts((instance.get("vars") or {}).get("dns_domains")).items())
        if is_dns(cert) and not processes(cert)
    ]
    if not unprocessed:
        return []
    account = account_of(instance)
    owners, errors = {}, []
    # Fail closed: without both accounts the same-account rule cannot be shown to hold
    # (None == None would pass two instances that name no account).
    if not account:
        errors.append(
            "has no settings.environment.account: an unprocessed certificate's records come from a same-account "
            "acm instance, which cannot be checked without it"
        )
    for dep in (instance.get("dependencies") or {}).get("components") or []:
        if not isinstance(dep, dict) or not isinstance(dep.get("component"), str):
            continue
        dep_stack = dep.get("stack") or stack_name
        target = stacks.get(dep_stack, {}).get("components", {}).get("terraform", {}).get(dep["component"])
        if target is None or not check_dependencies.is_deployable(target):
            continue
        if check_dependencies.module_name(dep["component"], target) != "acm":
            continue
        label = f"{dep_stack} {dep['component']}"
        if not account_of(target):
            errors.append(
                f"depends on {label}, which has no settings.environment.account: ACM validation records are per "
                "account, so its records cannot be shown to validate these certificates"
            )
            continue
        if not account:
            continue  # reported above; carries nothing
        if account_of(target) != account:
            errors.append(
                f"depends on {label}, in account {account_of(target)!r}, not {account!r}: "
                "ACM validation records are per account, so its records cannot validate these certificates"
            )
            continue
        for cert in dicts((target.get("vars") or {}).get("dns_domains")).values():
            if is_dns(cert) and processes(cert):
                for n in cert_names(cert):
                    owners.setdefault(normalize(n), label)
    for key, cert in unprocessed:
        for n in cert_names(cert):
            if normalize(n) not in owners:
                errors.append(
                    f"certificate {key} sets process_domain_validation_options: false, but no processed DNS "
                    f"certificate of an acm instance in its dependencies.components (same account) carries "
                    f"{n} or its *./base twin, so nothing writes its validation record"
                )
    return errors


def zoned_names(module: str, variables: dict) -> list[tuple[str, str]]:
    """(what, name) pairs this instance writes into its zone_id."""
    if module == "acm":
        names = []
        for key, cert in sorted(dicts(variables.get("dns_domains")).items()):
            if not is_dns(cert) or not processes(cert):
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


def duplicate_errors(stacks: dict) -> list[str]:
    """A public zone name held twice in one stack, or an aws-dns-delegated zone by two real stacks.

    Two authoritative zones for one name answer differently, and two aws-dns-delegated
    instances overwrite each other's NS record in the parent (root_ns allow_overwrite).
    """
    errors, delegated = [], {}
    for stack_name, stack in sorted(stacks.items()):
        instances = stack.get("components", {}).get("terraform", {})
        held: dict = {}
        for zone in public_zones(instances):
            held.setdefault(normalize(zone.name), []).append(zone.label)
            stage = ((instances[zone.instance].get("settings") or {}).get("context") or {}).get("stage")
            if zone.config.get("kind") == DELEGATED and stage != check_dependencies.fixtures.FIXTURE_STAGE:
                delegated.setdefault(normalize(zone.name), set()).add(stack_name)
        errors += [f"{stack_name}: public zone {name} is held twice: {', '.join(labels)}" for name, labels in held.items() if len(labels) > 1]
    errors += [
        f"{min(owners)}: aws-dns-delegated zone {name} is held by stacks {', '.join(sorted(owners))}: their NS records overwrite each other"
        for name, owners in sorted(delegated.items()) if len(owners) > 1
    ]
    return errors


# CloudWatch Logs account-scoped resource policies per region and account (a hard quota).
LOG_POLICY_LIMIT = 10
QUERY_LOG_REGION = "us-east-1"  # Route 53 only publishes query logs there (dns query-logging.tf)


def default_on(variables: dict, key: str) -> bool:
    """A bool variable whose Terraform default is true: unset counts as on."""
    return variables.get(key) is None or flag_on(variables[key])


def account_names(stacks: dict) -> dict:
    """Account id -> the account names it stands for (settings.account_map and settings.environment)."""
    names: dict = {}
    for stack in stacks.values():
        for instance in stack.get("components", {}).get("terraform", {}).values():
            settings = instance.get("settings") or {}
            pairs = dict((settings.get("account_map") or {}).get("full_account_map") or {})
            env = settings.get("environment") or {}
            if env.get("account") and env.get("account_id"):
                pairs[env["account"]] = env["account_id"]
            for account, account_id in pairs.items():
                names.setdefault(str(account_id), set()).add(str(account))
    return names


def dns_accounts(role: str, account: str, accounts: dict) -> tuple[list[str], list[str]]:
    """(account names the dns module's aws.dns_account provider lands in, problems).

    With no role the provider uses this instance's own credentials, so its own account. An id
    several names share (the placeholder account map) counts in each, which never undercounts;
    an id no stack names cannot be counted, so it is a problem.
    """
    if not role:
        return [account], []
    parts = role.split(":")
    account_id = parts[4] if len(parts) >= 6 else ""
    names = sorted(accounts.get(account_id, ()))
    if names:
        return names, []
    return [], [
        f"dns_account_assume_role_arn {role!r} names account id {account_id or '(none)'}, which no stack's "
        "settings.account_map.full_account_map or settings.environment.account_id holds, so its CloudWatch "
        "Logs resource policy cannot be counted against an account"
    ]


def log_policies(
    stack_name: str, name: str, instance: dict, accounts: dict
) -> tuple[list[tuple[str, str]], list[str]]:
    """((account, region) of each account-scoped CloudWatch Logs resource policy an instance creates, problems).

    accounts is account_names(stacks).
    """
    module, variables = check_dependencies.module_name(name, instance), instance.get("vars") or {}
    account = str(((instance.get("settings") or {}).get("environment") or {}).get("account") or stack_name)
    if module == "waf":
        # waf main.tf: manage_log_resource_policy = enabled && enable_logging && manage_log_resource_policy
        logs = all(default_on(variables, key) for key in ("enabled", "enable_logging", "manage_log_resource_policy"))
        region = QUERY_LOG_REGION if str(variables.get("scope", "")).upper() == "CLOUDFRONT" else str(variables.get("region"))
        return ([(account, region)] if logs else []), []
    if module != "dns":
        return [], []
    # Public zones the dns module moves to aws.dns_account (multi_account_dns_delegation), and
    # external_zones with dns_account: their policy is in the DNS account.
    moved = flag_on(variables.get("multi_account_dns_delegation"))
    places = {
        moved for zone in dicts(variables.get("zones")).values()
        if flag_on(zone.get("enable_query_logging")) and is_public(zone)
    } | {
        flag_on(zone.get("dns_account")) for zone in dicts(variables.get("external_zones")).values()
        if flag_on(zone.get("enable_query_logging"))
    }
    found = [(account, QUERY_LOG_REGION)] if False in places else []
    if True not in places:
        return found, []
    remote, problems = dns_accounts(str(variables.get("dns_account_assume_role_arn") or ""), account, accounts)
    # The DNS-account policy is its own resource even when that account is this one, so both count.
    return found + [(other, QUERY_LOG_REGION) for other in remote], problems


def log_policy_errors(stacks: dict) -> list[str]:
    """Accounts and regions whose house-created CloudWatch Logs resource policies exceed the quota."""
    held: dict = {}
    errors, accounts = [], account_names(stacks)
    for stack_name, stack in sorted(stacks.items()):
        for name, instance in sorted(stack.get("components", {}).get("terraform", {}).items()):
            stage = ((instance.get("settings") or {}).get("context") or {}).get("stage")
            if not check_dependencies.is_deployable(instance) or stage == check_dependencies.fixtures.FIXTURE_STAGE:
                continue
            places, problems = log_policies(stack_name, name, instance, accounts)
            errors += [f"{stack_name}: {name}: {problem}" for problem in problems]
            for place in places:
                held.setdefault(place, []).append(f"{stack_name} {name}")
    return errors + [
        f"account {account} region {region}: {len(owners)} CloudWatch Logs resource policies "
        f"(quota {LOG_POLICY_LIMIT} per region and account): {', '.join(owners)}"
        for (account, region), owners in sorted(held.items()) if len(owners) > LOG_POLICY_LIMIT
    ]


def check(stacks: dict) -> tuple[list[str], list[str]]:
    """(errors, warnings)."""
    errors, warnings = [], []
    everywhere = {
        normalize(z.name) for stack in stacks.values() for z in public_zones(stack.get("components", {}).get("terraform", {}))
    }
    errors += duplicate_errors(stacks) + log_policy_errors(stacks)
    for stack_name, stack in sorted(stacks.items()):
        instances = stack.get("components", {}).get("terraform", {})
        zones = public_zones(instances)
        errors += delegation_errors(stacks, stack_name, zones, everywhere)
        for name, instance in sorted(instances.items()):
            if not check_dependencies.is_deployable(instance):
                continue
            module = check_dependencies.module_name(name, instance)
            variables = instance.get("vars") or {}
            where = f"{stack_name}: {name}"
            if module == "dns":
                found, warned = dns_errors(stacks, stack_name, where, variables, zones, everywhere)
                errors, warnings = errors + found, warnings + warned
                continue
            if module == "apigateway":
                problem, warning = certificate_problem(stacks, stack_name, variables)
                if problem:
                    errors.append(f"{where}: {problem}")
                if warning:
                    warnings.append(f"{where}: {warning}")
            if module == "acm":
                errors += [f"{where}: {e}" for e in borrowed_validation_errors(stacks, stack_name, instance)]
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
        "every public subzone is delegated from its parent zone, every apigateway certificate covers its domain, "
        "every acm certificate that writes no validation record depends on a same-account one that does, "
        f"and no account and region holds more than {LOG_POLICY_LIMIT} house CloudWatch Logs resource policies"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
