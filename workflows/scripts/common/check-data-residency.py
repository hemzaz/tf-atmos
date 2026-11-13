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
    the one dependency list);
  - if a dns instance, turns on enable_query_logging for no zone: Route 53 public
    query logs (client IPs) go only to us-east-1 (components/terraform/dns/query-logging.tf);
    nor dnssec_enabled: its signing KMS key can only be in us-east-1 (owner decision B5:
    no key there for an EU stack). The same holds for its external_zones entries;
  - holds no public zone (dns zones, vendored aws-dns-primary domain_names and aws-dns-delegated
    zones) whose closest held ancestor zone a stack that is not GDPR-scoped holds, and names no
    such zone in external_zones: it would hang off, or write into, a US account (B5);
  - if a security-monitoring instance, leaves enable_alert_enrichment off: its Lambda posts
    each finding (source IPs, principals) to Slack and PagerDuty, outside AWS's EU regions;
  - sets none of GLOBAL_SERVICE_EMAIL_VARS: vars a global AWS service hosted in us-east-1
    would store as email subscribers (cost-optimization's budget and anomaly addresses,
    AWS Budgets and Cost Explorer). Notify an in-region SNS topic holding the subscriptions
    instead (cost-optimization billing_notifications_sns_enabled; owner decision 2026-10-12).
And no deployable instance of a stack that is not GDPR-scoped lists a GDPR-scoped stack in
dependencies.components or names an ARN in an eu- region in its vars: a US read replica
(replicate_source_db), Global Datastore secondary (global_replication_group_id) or state read
of an EU instance would copy EU data out (check-dependencies.py makes every cross-stack read a
listed dependency; a literal ARN needs none). Its *_region vars are not checked: US data
copied into the EU is fine. A Global Datastore id is not an ARN, so a GDPR-scoped stack's
elasticache primary (global_replication_group_id_suffix) is also matched by name: no instance
of a stack that is not GDPR-scoped may join it (set global_replication_group_id to a read of
the primary's, to a literal id ending in its suffix, or while depending on the primary).
EXEMPTIONS lists the (instance pattern, field) pairs that may name one region the rules
above forbid there.
Every deployable trail and recorder (metadata.component in LOG_ARCHIVES: the vendored
aws-cloudtrail and aws-config), in any stack, delivers to its residency's log archive: its
bucket environment and stage vars (CP remote-state; the house remote-state_override.tf
computes the bucket from them, owner OQ-E) name stage "audit" and, with the tenant, a stack
holding that bucket instance (cloudtrail-bucket, config-bucket) that is GDPR-scoped iff its
own stack is (fnx-ew1-audit, else fnx-ue1-audit), which it lists in dependencies.components.
No other vars key containing "bucket" may be set: a literal bucket name would bypass this.
A recorder outside its global_resource_collector_region takes the collector's role: it sets
iam_role_arn and not create_iam_role; a literal iam_role_arn is the ARN of the one enabled
collector of its account and collector region (its account_id, its null-label id + "-config"). A non-GDPR stack's Config aggregator (the aws-config
instance of the central_resource_collector_account in its collector region) lists in
delegated_accounts no account whose stacks are all GDPR-scoped (by settings.environment
.account_id; an id another account also carries, like the placeholder, cannot be told apart and
is skipped), nor leaves it unset (CP then aggregates the whole account_map) while one exists.
Scoped exemption (owner OQ-A/OQ-B, 2026-11-07): the shared accounts (root, audit, security)
record IAM and keep their one multi-region trail in their US home stack, so a GDPR-scoped
stack's aws-config may name, in vars.global_resource_collector_region, the region of the
collector a non-GDPR stack of its own account (settings.environment.account) holds; prod-eu,
whose stacks are all GDPR-scoped, may not. Not coded, as no stack var shows it: those trails
(US archive) also record the accounts' EU-region (eu-west-1, and for root and security the EU
DR region eu-central-1, E5c3b) control-plane events, and the US aggregator in fnx-ue1-security
(all regions, CP-hardcoded) aggregates their EU-region recorders. All of it
is core-account control-plane metadata, not EU personal data; a GDPR-scoped stack's own trail
or recorder still delivers only to the EU archive.
The org security services (ORG_SERVICES: the vendored aws-guardduty, aws-security-hub and
aws-inspector2; owner OQ-RES/OQ-SH, 2026-11-10) keep EU findings in the EU. A deployable
org-settings instance (admin_delegated on; the only step whose members are its account_map, CP
main.tf; not the root step, which deploys to the map's root_account_account_name and names it as
organization_management_account_name too) reads a static account_map (account_map_enabled false).
GDPR_ONLY_ACCOUNTS declares the accounts whose stacks are all GDPR-scoped (prod-eu); a stack set
deriving others fails. Outside the GDPR scope the map holds none of them (by <tenant>-<account>
key, and by ID unless shared: catalog/_base account-map-bypass-us), or, for Inspector,
member_association_excludes lists exactly their IDs; a GuardDuty org-settings there auto-enables
NEW or NONE (CP default NEW), as ALL enrolls every existing account whatever the map. Inside it the
map holds all of them and Inspector excludes none: the EU admin is theirs. Known limitation: Security
Hub's auto_enable and Inspector's auto_enable_* also enroll accounts that join the organization AFTER
its org-settings apply, so an all-GDPR account created later would be enrolled by a US admin; today
prod-eu exists first. A Security Hub that creates a finding
aggregator (outside the management account, admin_delegated off, finding_aggregator_enabled and
finding_aggregation_region its region, CP defaults true and us-east-1) is in a stack that is not
GDPR-scoped and sets finding_aggregator_linking_mode SPECIFIED_REGIONS with a non-empty
finding_aggregator_regions of non-eu regions only (ALL_REGIONS would pull in every EU region,
also one enabled later); a GDPR-scoped stack's never aggregates. Security Hub's account_scoped_control_suppressions (house
account-suppressions_house.tf) is set only in a GDPR-scoped stack, and each entry's account_names
is exactly its account_map's keys minus the all-GDPR ones: it never suppresses an all-GDPR account's
findings (their home region is the EU one). Their dependencies.components
(root <-> security) stay in one residency by the dependency rules above.
Fixture stacks are checked too (KNOWN_BROKEN_FIXTURES relaxes one). Exits 1 on any
violation.

Out of scope: other us-east-1 regions hard-coded inside component code (the apigateway
health-check alarm and its topic, cloudfront log delivery) are not stack config; they are
reviewed per component.
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


# The api.<EU apex> failover pair (fnx-ew1-prod PRIMARY, fnx-ec1-prod SECONDARY), owner
# decision B5. Route 53 checks from at least 3 checker regions and eu-west-1 is the only EU
# one, so each check also calls from us-east-1 and ap-southeast-1 (probes of the API's stage
# root). The health checks, their alarms and the EventBridge rule, targets and role relaying
# each alarm to both EU regions sit in us-east-1 too, but no stack var names that region:
# the component fixes it (apigateway main.tf, health-check-alarm-relay.tf), so no exemption
# covers them, and an EU alarm action (health_check_alarm_actions, a us-east-1 topic) fails.
# The relay targets' retry policy (maximum_event_age_in_seconds = 3600) keeps alarm metadata in
# flight in us-east-1 for at most 1h, nothing persisted: within the owner's exemption.
_CHECKERS = "Route 53 health checks: 3 checker regions, eu-west-1 the only EU one; probes only (owner, B5)"
EXEMPTIONS: tuple = (
    Exemption("apigateway/main", "vars.health_check_regions", "us-east-1", _CHECKERS),
    Exemption("apigateway/main", "vars.health_check_regions", "ap-southeast-1", _CHECKERS),
)


class LogArchive(NamedTuple):
    bucket_component: str  # the bucket's metadata.component in the audit stack
    component_var: str  # vars naming the bucket instance, its environment, stage and tenant
    component_default: str
    environment_var: str
    stage_var: str
    tenant_var: Optional[str]  # None: the tenant comes from the context (vars.tenant)


# component -> the log archive its CP remote-state reads (variables.tf of each, vendored).
LOG_ARCHIVES: dict = {
    "aws-cloudtrail": LogArchive(
        "aws-cloudtrail-bucket", "cloudtrail_bucket_component_name", "cloudtrail-bucket",
        "cloudtrail_bucket_environment_name", "cloudtrail_bucket_stage_name", None,
    ),
    "aws-config": LogArchive(
        "aws-config-bucket", "config_bucket_component_name", "config-bucket",
        "config_bucket_env", "config_bucket_stage", "config_bucket_tenant",
    ),
}
AUDIT_STAGE = "audit"


US_PARENT = "an EU zone may not hang off, or write into, a zone in a US account"


# component -> vars a global service (hosted in us-east-1) stores as email subscribers.
GLOBAL_SERVICE_EMAIL_VARS: dict = {
    "cost-optimization": ("budget_notification_emails", "cost_anomaly_notification_email"),
}

# The vendored Cloud Posse org security services (E5c). Each acts by the account it deploys to
# (main.tf locals): the management account delegates (root step), the delegated administrator
# creates the detector/hub (admin_delegated false; Inspector has none) and the org settings
# (admin_delegated true) over its account_map's other accounts.
ORG_SERVICES = ("aws-guardduty", "aws-security-hub", "aws-inspector2")
# The accounts whose stacks are all GDPR-scoped (owner B5: EU prod), declared once: check-first-deploy-inputs
# builds the US map variant from it, and org_service_errors fails when the stacks derive another set.
GDPR_ONLY_ACCOUNTS = ("prod-eu",)
GUARDDUTY_AUTO_ENABLE_DEFAULT = "NEW"  # aws-guardduty variables.tf auto_enable_organization_members


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


def region_fields(value: Any, path: str, region_key: bool = False, keys: bool = True) -> Iterator[tuple[str, str]]:
    """(path, region) for every region under a *_region(s) key and every regional ARN in value.

    keys=False reports ARN regions only. A list item reports at its list's path, so an
    exemption names the var.
    """
    if isinstance(value, dict):
        for key, item in value.items():
            yield from region_fields(item, f"{path}.{key}", keys and bool(REGION_KEY.search(str(key))), keys)
    elif isinstance(value, list):
        for item in value:
            yield from region_fields(item, path, region_key, keys)
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


def flag_on(value: Any) -> bool:
    """Whether Terraform would read value as a true bool: anything but null, false or "false".

    A quoted YAML "true" (or "True", or 1) becomes true for optional(bool), so only the
    values that are certainly off count as off.
    """
    return value is not None and value is not False and str(value).strip().lower() != "false"


def query_logging_errors(where: str, zones: Any, field: str = "zones") -> list[str]:
    """A dns instance's zones (or external_zones) that turn on Route 53 query logging (us-east-1 only)."""
    if zones is None:
        return []
    if not isinstance(zones, dict):
        return [f"{where} vars.{field} is {type(zones).__name__}, not a map: its query logging cannot be checked"]
    label = "zone " if field == "zones" else f"{field}."
    return [
        f"{where} {label}{key} sets enable_query_logging: Route 53 query logs are only "
        "written to us-east-1, outside the EU"
        for key, zone in sorted(zones.items())
        if isinstance(zone, dict) and flag_on(zone.get("enable_query_logging"))
    ]


def held_zones(name: str, instance: dict) -> list[str]:
    """The public zone names a dns, aws-dns-primary or aws-dns-delegated instance holds (normalized)."""
    component, variables = (instance.get("metadata") or {}).get("component") or name, instance.get("vars") or {}
    names = []
    if component == "dns" and isinstance(variables.get("zones"), dict):
        names = [z.get("name") for z in variables["zones"].values() if isinstance(z, dict) and not z.get("vpc_associations")]
    elif component == "aws-dns-primary":
        names = list(variables.get("domain_names") or [])
    elif component == "aws-dns-delegated" and not flag_on(variables.get("dns_private_zone_enabled")):
        names = [f"{z.get('subdomain')}.{z.get('zone_name')}" for z in variables.get("zone_config") or [] if isinstance(z, dict)]
    return [n.lower().rstrip(".") for n in names if isinstance(n, str)]


def zone_holders(stacks: dict) -> dict:
    """Public zone name -> the stacks whose deployable instances hold it."""
    holders: dict = {}
    for stack_name, stack in stacks.items():
        for name, instance in instances(stack).items():
            for zone in held_zones(name, instance):
                holders.setdefault(zone, set()).add(stack_name)
    return holders


def zone_errors(where: str, name: str, instance: dict, scoped: set, holders: dict) -> list[str]:
    """An EU zone whose closest held ancestor, or an EU external_zones name, a non-GDPR stack holds.

    The EU zone then resolves only through, and is delegated from, a US account (B5).
    """
    errors = []
    for zone in held_zones(name, instance):
        labels = zone.split(".")
        ancestor = next((".".join(labels[i:]) for i in range(1, len(labels)) if ".".join(labels[i:]) in holders), None)
        for holder in sorted(holders.get(ancestor, set()) - scoped):
            errors.append(f"{where} zone {zone} sits below {ancestor}, held in {holder}, which is not GDPR-scoped: {US_PARENT}")
    externals = (instance.get("vars") or {}).get("external_zones")
    for key, external in sorted((externals if isinstance(externals, dict) else {}).items()):
        target = str((external or {}).get("name") or "").lower().rstrip(".") if isinstance(external, dict) else ""
        for holder in sorted(holders.get(target, set()) - scoped):
            errors.append(f"{where} external_zones.{key} names {target}, held in {holder}, which is not GDPR-scoped: {US_PARENT}")
    return errors


def check_instance(
    stack_name: str, name: str, instance: dict, scoped: set, exemptions: tuple, holders: Optional[dict] = None,
    collectors: frozenset = frozenset(),
) -> list[str]:
    errors = []
    where = f"{stack_name}: {name}"
    home = (account_of(instance), (instance.get("vars") or {}).get("global_resource_collector_region"))
    for field, region in regions(instance):
        if field == "vars.global_resource_collector_region" and component_of(name, instance) == "aws-config" \
                and home in collectors:
            continue  # OQ-A: a shared account's collector is in its US home stack
        if not region.startswith(EU_PREFIX) and not exempt(name, field, region, exemptions):
            errors.append(f"{where} {field} is {region!r}, outside the EU, in a GDPR-scoped stack")
    if not tagged_gdpr(instance):
        errors.append(f"{where} is in a GDPR-scoped stack but its tags.Compliance does not contain {GDPR!r}")
    if (instance.get("settings") or {}).get("depends_on"):
        errors.append(f"{where} sets settings.depends_on: list dependencies in dependencies.components")
    component = (instance.get("metadata") or {}).get("component") or name
    if component == "dns":
        errors += query_logging_errors(where, (instance.get("vars") or {}).get("zones"))
        errors += query_logging_errors(where, (instance.get("vars") or {}).get("external_zones"), "external_zones")
        if flag_on((instance.get("vars") or {}).get("dnssec_enabled")):
            errors.append(
                f"{where} sets dnssec_enabled: Route 53 signs only with a KMS key in us-east-1, "
                "outside the EU"
            )
    errors += zone_errors(where, name, instance, scoped, holders or {})
    if component == "security-monitoring" and flag_on((instance.get("vars") or {}).get("enable_alert_enrichment")):
        errors.append(
            f"{where} sets enable_alert_enrichment: its Lambda sends findings to Slack/PagerDuty, "
            "outside the EU"
        )
    for var in GLOBAL_SERVICE_EMAIL_VARS.get(component, ()):
        if (instance.get("vars") or {}).get(var):
            errors.append(
                f"{where} sets vars.{var}: a global service in us-east-1 would store those email "
                "addresses; notify an in-region SNS topic instead"
            )
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
    holders, collectors = zone_holders(stacks), us_collectors(stacks, scoped)
    for stack_name in sorted(scoped):
        for name, instance in sorted(instances(stacks[stack_name]).items()):
            errors += check_instance(stack_name, name, instance, scoped, exemptions, holders, collectors)
    for stack_name in sorted(set(stacks) - scoped):
        for name, instance in sorted(instances(stacks[stack_name]).items()):
            errors += outside_reader_errors(stack_name, name, instance, scoped, exemptions)
    errors += global_datastore_errors(stacks, scoped)
    errors += log_archive_errors(stacks, scoped)
    errors += org_service_errors(stacks, scoped)
    return list(dict.fromkeys(errors))


def state_read(value: Any, reader_stack: str) -> Optional[tuple[str, str, str]]:
    """(component, stack, expression) of an unprocessed !terraform.state/!terraform.output string, or None."""
    if not isinstance(value, str):
        return None
    tokens = value.split(None, 3)
    if len(tokens) < 3 or tokens[0] not in ("!terraform.state", "!terraform.output"):
        return None
    if len(tokens) == 3:
        return tokens[1], reader_stack, tokens[2].strip("'\"")
    return tokens[1], tokens[2], tokens[3].strip("'\"")


def joins_group(stack_name: str, instance: dict, primary: tuple[str, str], suffix: str) -> bool:
    """Whether instance (in stack_name) joins primary's Global Datastore as a secondary.

    It sets vars.global_replication_group_id and either reads the primary's
    global_replication_group_id, names the group literally (AWS forms the id as
    "<prefix>-<suffix>"), or lists the primary in dependencies.components.
    """
    gid = (instance.get("vars") or {}).get("global_replication_group_id")
    if gid in (None, ""):
        return False
    read = state_read(gid, stack_name)
    if read is not None:
        component, stack, expression = read
        if (stack, component) == primary and "global_replication_group_id" in expression:
            return True
    elif isinstance(gid, str) and (gid == suffix or gid.endswith(f"-{suffix}")):
        return True
    return any(
        isinstance(dep, dict) and (dep.get("stack") or stack_name, dep.get("component")) == primary
        for dep in (instance.get("dependencies") or {}).get("components") or []
    )


def global_datastore_errors(stacks: dict, scoped: set) -> list[str]:
    """A GDPR-scoped stack's Global Datastore primary joined by an instance of a stack that is not.

    A literal global_replication_group_id is not an ARN, so the outside-reader rule cannot see it:
    the group is matched by its suffix (global_replication_group_id_suffix) instead.
    """
    errors = []
    for primary_stack in sorted(scoped):
        for name, instance in sorted(instances(stacks[primary_stack]).items()):
            if ((instance.get("metadata") or {}).get("component") or name) != "elasticache":
                continue
            suffix = (instance.get("vars") or {}).get("global_replication_group_id_suffix")
            if not isinstance(suffix, str) or not suffix.strip():
                continue
            for stack_name in sorted(set(stacks) - scoped):
                for joiner, spec in sorted(instances(stacks[stack_name]).items()):
                    if joins_group(stack_name, spec, (primary_stack, name), suffix):
                        errors.append(
                            f"{stack_name}: {joiner} joins {primary_stack} {name}'s Global Datastore ({suffix}) "
                            "outside the GDPR scope: EU cache data may not be replicated outside the EU"
                        )
    return errors


def log_archive_errors(stacks: dict, scoped: set) -> list[str]:
    """A trail or recorder (LOG_ARCHIVES) that names a literal bucket, or an archive outside its residency."""
    errors = []
    for stack_name in sorted(stacks):
        for name, instance in sorted(instances(stacks[stack_name]).items()):
            archive = LOG_ARCHIVES.get(component_of(name, instance))
            if archive is None:
                continue
            errors += archive_errors(stacks, scoped, stack_name, name, instance, archive)
    return errors + aggregator_errors(stacks, scoped) + collector_role_errors(stacks)


def null_label_id(instance: dict) -> str:
    """The instance's null-label id (default label order and delimiter): its vars override vars.context."""
    variables = instance.get("vars") or {}
    context = variables.get("context") or {}
    parts = [variables.get(key) or context.get(key) for key in ("namespace", "tenant", "environment", "stage", "name")]
    parts += list(variables.get("attributes") or context.get("attributes") or [])
    return "-".join(str(part) for part in parts if part)


def collector_role_errors(stacks: dict) -> list[str]:
    """A recorder naming its collector's role by a literal ARN (aws-config/main-core-region) names that role.

    The role is Cloud Posse's: the collector instance's null-label id plus the "config" attribute
    (cloudposse/config aws_config_label), in the collector's account. Only an account with one
    enabled collector in that region is compared: none or two are other findings (us_collectors
    above, check-lane-names.py's singleton).
    """
    collectors: dict = {}
    for stack_name, stack in stacks.items():
        for name, instance in instances(stack).items():
            variables = instance.get("vars") or {}
            if component_of(name, instance) == "aws-config" and account_of(instance) \
                    and flag_on(variables.get("enabled", True)) and variables.get("region") \
                    and variables.get("global_resource_collector_region") == variables.get("region"):
                collectors.setdefault((account_of(instance), variables["region"]), []).append(instance)
    errors = []
    for stack_name in sorted(stacks):
        for name, instance in sorted(instances(stacks[stack_name]).items()):
            arn = (instance.get("vars") or {}).get("iam_role_arn")
            if component_of(name, instance) != "aws-config" or not isinstance(arn, str) or not arn.startswith("arn:"):
                continue
            home = collectors.get((account_of(instance), (instance.get("vars") or {}).get("global_resource_collector_region")))
            if not home or len(home) != 1:
                continue
            account_id = ((home[0].get("settings") or {}).get("environment") or {}).get("account_id")
            role = f"iam::{account_id}:role/{null_label_id(home[0])}-config"
            if not re.fullmatch(rf"arn:aws[a-z-]*:{re.escape(role)}", arn):
                errors.append(f"{stack_name}: {name} vars.iam_role_arn is {arn!r}, not its collector's role "
                              f"arn:aws:{role}")
    return errors


def component_of(name: str, instance: dict) -> str:
    return instance.get("component") or (instance.get("metadata") or {}).get("component") or name


def account_of(instance: dict) -> Optional[str]:
    return ((instance.get("settings") or {}).get("environment") or {}).get("account")


def us_collectors(stacks: dict, scoped: set) -> frozenset:
    """(account, region) of every aws-config global-resource collector in a stack that is not GDPR-scoped.

    A recorder with vars.enabled false creates nothing, and one with no settings.environment.account
    names no account, so neither is a collector a GDPR-scoped stack may lean on.
    """
    return frozenset(
        (account_of(instance), variables.get("region"))
        for stack_name in set(stacks) - scoped
        for name, instance in instances(stacks[stack_name]).items()
        for variables in [instance.get("vars") or {}]
        if component_of(name, instance) == "aws-config"
        and account_of(instance)
        and flag_on(variables.get("enabled", True))
        and variables.get("global_resource_collector_region") == variables.get("region")
    )


def gdpr_only_accounts(stacks: dict, scoped: set) -> tuple[list, set]:
    """(accounts whose stacks are all GDPR-scoped, their IDs that no other account also carries)."""
    ids: dict = {}  # account -> ({ids outside the GDPR scope}, {ids inside})
    for stack_name, stack in stacks.items():
        for instance in instances(stack).values():
            env = (instance.get("settings") or {}).get("environment") or {}
            if env.get("account"):
                ids.setdefault(env["account"], (set(), set()))[stack_name in scoped].add(str(env.get("account_id")))
    eu = sorted(a for a, (outside, inside) in ids.items() if inside and not outside)
    shared = set().union(set(), *(o | i for a, (o, i) in ids.items() if a not in eu))
    return eu, set().union(set(), *(ids[a][1] for a in eu)) - shared


def aggregator_errors(stacks: dict, scoped: set) -> list[str]:
    """A non-GDPR stack's Config aggregator over an account whose stacks are all GDPR-scoped (owner OQ-B)."""
    eu, eu_ids = gdpr_only_accounts(stacks, scoped)
    errors = []
    for stack_name in sorted(set(stacks) - scoped):
        for name, instance in sorted(instances(stacks[stack_name]).items()):
            variables, where = instance.get("vars") or {}, f"{stack_name}: {name}"
            central = f"{variables.get('tenant')}-{account_of(instance)}"
            if component_of(name, instance) != "aws-config" or variables.get("central_resource_collector_account") != central \
                    or variables.get("global_resource_collector_region") != variables.get("region"):
                continue
            if variables.get("delegated_accounts") is None and eu:
                errors.append(f"{where} leaves delegated_accounts unset, so it aggregates every account, including "
                              f"{', '.join(eu)}, whose stacks are all GDPR-scoped")
            errors += [
                f"{where} delegated_accounts lists {account_id}, an account whose stacks are all GDPR-scoped: "
                "its Config data may not be aggregated outside the EU"
                for account_id in sorted({str(a) for a in variables.get("delegated_accounts") or []} & eu_ids)
            ]
    return errors


def tenant_of(instance: dict) -> Optional[str]:
    variables = instance.get("vars") or {}
    return variables.get("tenant") or (variables.get("context") or {}).get("tenant") \
        or ((instance.get("settings") or {}).get("context") or {}).get("tenant")


def map_root_account(instance: dict) -> Optional[str]:
    """The management account: the account map's root_account_account_name (else <tenant>-root)."""
    root = ((instance.get("vars") or {}).get("account_map") or {}).get("root_account_account_name")
    return root or (f"{tenant_of(instance)}-root" if tenant_of(instance) else None)


def management_account(instance: dict) -> Optional[str]:
    """An org service instance's management account name (CP main.tf: the var, else the map's root account)."""
    return (instance.get("vars") or {}).get("organization_management_account_name") or map_root_account(instance)


def is_management(instance: dict) -> bool:
    """Whether the instance runs the root step: it deploys to the map's root account, which it also names as
    management (an instance naming its own account management is judged as the step it really is)."""
    return own_account(instance) is not None and own_account(instance) == map_root_account(instance) \
        == management_account(instance)


def own_account(instance: dict) -> Optional[str]:
    """The <tenant>-<account> account_map key of the account the instance deploys to."""
    tenant, account = tenant_of(instance), account_of(instance)
    return f"{tenant}-{account}" if tenant and account else None


def creates_aggregator(instance: dict) -> bool:
    """Whether an aws-security-hub instance creates a finding aggregator (CP main.tf, step 1)."""
    variables = instance.get("vars") or {}
    return not is_management(instance) \
        and flag_on(variables.get("enabled", True)) and not flag_on(variables.get("admin_delegated")) \
        and flag_on(variables.get("finding_aggregator_enabled", True)) \
        and variables.get("finding_aggregation_region", "us-east-1") == variables.get("region")


def aggregator_region_errors(where: str, variables: dict) -> list[str]:
    """A non-GDPR stack's Security Hub aggregator must link only named non-eu regions (owner OQ-SH)."""
    mode, linked = variables.get("finding_aggregator_linking_mode", "ALL_REGIONS"), variables.get("finding_aggregator_regions")
    if mode != "SPECIFIED_REGIONS":
        return [f"{where} aggregates findings with finding_aggregator_linking_mode {mode!r}: set SPECIFIED_REGIONS "
                "with non-eu finding_aggregator_regions, or it pulls in EU regions' findings"]
    if not isinstance(linked, list) or not linked or not all(isinstance(r, str) and AWS_REGION.match(r) for r in linked):
        return [f"{where} finding_aggregator_regions is {linked!r}: SPECIFIED_REGIONS needs a non-empty list of regions"]
    return [f"{where} finding_aggregator_regions links {region!r}: EU findings may not be aggregated outside the EU"
            for region in linked if region.startswith(EU_PREFIX)]


def member_map_errors(where: str, component: str, variables: dict, tenant: str, eu_ids: set, gdpr: bool) -> list[str]:
    """An org-settings instance's members: outside the GDPR scope no all-GDPR account (Inspector: excluded by
    exactly their IDs); inside it every all-GDPR account (the EU admin is theirs)."""
    if flag_on(variables.get("account_map_enabled", False)):
        return [f"{where} sets account_map_enabled: its members come from the account-map state and cannot be checked; "
                "use the static account_map (catalog/_base account-map-bypass, or -us outside the EU)"]
    full = (variables.get("account_map") or {}).get("full_account_map") or {}
    excludes = {str(i) for i in variables.get("member_association_excludes") or []}
    eu_keys = {f"{tenant}-{a}" for a in GDPR_ONLY_ACCOUNTS}
    held = {key: str(account_id) for key, account_id in full.items() if key in eu_keys or str(account_id) in eu_ids}
    if gdpr:
        errors = [f"{where} account_map.full_account_map lacks {key}, an account whose stacks are all GDPR-scoped: "
                  "its EU admin must make it a member (use the full map)" for key in sorted(eu_keys - set(full))]
        if component == "aws-inspector2":
            errors += [f"{where} member_association_excludes lists {key} ({account_id}): its EU admin must make it a member"
                       for key, account_id in sorted(held.items()) if account_id in excludes]
        return errors
    if component == "aws-inspector2":
        if excludes != set(held.values()):
            return [f"{where} member_association_excludes is {sorted(excludes)}: exclude exactly the IDs of the accounts "
                    f"whose stacks are all GDPR-scoped ({sorted(set(held.values()))}), no other member"]
        return []
    return [f"{where} account_map.full_account_map holds {key} ({account_id}), an account whose stacks are all "
            "GDPR-scoped: it would be a member outside the EU; drop it from the map" for key, account_id in sorted(held.items())]


def auto_enable_errors(where: str, component: str, variables: dict) -> list[str]:
    """A non-GDPR GuardDuty org-settings that auto-enables existing accounts (ALL) enrolls the all-GDPR ones too."""
    mode = variables.get("auto_enable_organization_members", GUARDDUTY_AUTO_ENABLE_DEFAULT)
    if component != "aws-guardduty" or mode in ("NEW", "NONE"):
        return []
    return [f"{where} sets auto_enable_organization_members {mode!r}: outside the EU only NEW or NONE (ALL enrolls every "
            "existing account, the all-GDPR ones included, whatever the account_map)"]


def suppression_errors(where: str, variables: dict, tenant: str, gdpr: bool) -> list[str]:
    """aws-security-hub account_scoped_control_suppressions (account-suppressions_house.tf): only an EU admin's, and
    each entry suppresses exactly the shared accounts (the map minus the all-GDPR ones), never an all-GDPR one."""
    suppressions = variables.get("account_scoped_control_suppressions") or {}
    if not suppressions:
        return []
    if not gdpr:
        return [f"{where} sets account_scoped_control_suppressions outside the GDPR scope: they exist to keep an EU "
                "administrator from suppressing the all-GDPR accounts' home-region findings; a US region suppresses "
                "with disabled_control_finding_reasons"]
    eu_keys = {f"{tenant}-{a}" for a in GDPR_ONLY_ACCOUNTS}
    shared = set((variables.get("account_map") or {}).get("full_account_map") or {}) - eu_keys
    errors = []
    for key, entry in sorted(suppressions.items()):
        names = {str(n) for n in (entry or {}).get("account_names") or []}
        errors += [f"{where} account_scoped_control_suppressions.{key} names {name}, an account whose stacks are all "
                   "GDPR-scoped: its findings in its own home region must stay" for name in sorted(names & eu_keys)]
        if names - eu_keys != shared:
            errors.append(f"{where} account_scoped_control_suppressions.{key} account_names {sorted(names - eu_keys)} "
                          f"are not the shared accounts (the account map minus {sorted(eu_keys)}: {sorted(shared)})")
    return errors


def org_service_errors(stacks: dict, scoped: set) -> list[str]:
    """ORG_SERVICES members and Security Hub aggregation kept in their residency (owner OQ-RES/OQ-SH)."""
    eu, eu_ids = gdpr_only_accounts(stacks, scoped)
    errors, seen = [], False
    for stack_name in sorted(stacks):
        for name, instance in sorted(instances(stacks[stack_name]).items()):
            component, variables = component_of(name, instance), instance.get("vars") or {}
            if component not in ORG_SERVICES or not flag_on(variables.get("enabled", True)):
                continue
            where, seen = f"{stack_name}: {name}", True
            if component == "aws-security-hub" and creates_aggregator(instance):
                if stack_name in scoped:
                    errors.append(f"{where} creates a Security Hub finding aggregator in a GDPR-scoped stack: EU hubs "
                                  "are not aggregated (set finding_aggregator_enabled false)")
                else:
                    errors += aggregator_region_errors(where, variables)
            if component == "aws-security-hub":
                errors += suppression_errors(where, variables, str(tenant_of(instance)), stack_name in scoped)
            if not is_management(instance) and flag_on(variables.get("admin_delegated")):
                errors += member_map_errors(where, component, variables, str(tenant_of(instance)), eu_ids,
                                            stack_name in scoped)
                if stack_name not in scoped:
                    errors += auto_enable_errors(where, component, variables)
    if seen and eu and set(eu) != set(GDPR_ONLY_ACCOUNTS):
        errors.append(f"the accounts whose stacks are all GDPR-scoped are {eu}, not GDPR_ONLY_ACCOUNTS "
                      f"{list(GDPR_ONLY_ACCOUNTS)}: update the declaration (check-data-residency.py)")
    return errors


def archive_errors(stacks: dict, scoped: set, stack_name: str, name: str, instance: dict, archive: LogArchive) -> list[str]:
    where, variables = f"{stack_name}: {name}", instance.get("vars") or {}
    wiring = {archive.component_var, archive.environment_var, archive.stage_var, archive.tenant_var}
    errors = [
        f"{where} sets vars.{key}: the log archive bucket is computed from {archive.environment_var} and "
        f"{archive.stage_var} (remote-state_override.tf), never named"
        for key in sorted(variables)
        if "bucket" in key and key not in wiring
    ]
    component = variables.get(archive.component_var) or archive.component_default
    environment, stage = variables.get(archive.environment_var), variables.get(archive.stage_var)
    tenant = ((variables.get(archive.tenant_var) if archive.tenant_var else None) or variables.get("tenant")
              or (variables.get("context") or {}).get("tenant"))
    if archive.bucket_component == "aws-config-bucket" and variables.get("global_resource_collector_region") != \
            variables.get("region") and (not variables.get("iam_role_arn") or flag_on(variables.get("create_iam_role"))):
        errors.append(f"{where} records outside its global_resource_collector_region, so it sets iam_role_arn to the "
                      "collector's role and not create_iam_role")
    if not all(isinstance(v, str) and v for v in (tenant, environment, stage)):
        return errors + [f"{where} sets no tenant, vars.{archive.environment_var} or vars.{archive.stage_var}: "
                         "its log archive stack cannot be checked"]
    if stage != AUDIT_STAGE:
        errors.append(f"{where} vars.{archive.stage_var} is {stage!r}: the log archive is in stage {AUDIT_STAGE!r}")
    target = f"{tenant}-{environment}-{stage}"
    bucket = instances(stacks.get(target) or {}).get(component)
    if bucket is None or ((bucket.get("metadata") or {}).get("component") or component) != archive.bucket_component:
        errors.append(f"{where} delivers to {component} in {target}, which holds no {archive.bucket_component} "
                      f"instance {component}")
    residency = "GDPR-scoped" if stack_name in scoped else "not GDPR-scoped"
    if (target in scoped) != (stack_name in scoped):
        errors.append(f"{where} delivers to {target}, but its stack is {residency}: a trail or recorder delivers "
                      "to its residency's archive (EU iff GDPR-scoped)")
    if not any(
        isinstance(dep, dict) and dep.get("component") == component and (dep.get("stack") or stack_name) == target
        for dep in (instance.get("dependencies") or {}).get("components") or []
    ):
        errors.append(f"{where} does not list {{component: {component}, stack: {target}}} in dependencies.components")
    return errors


def outside_reader_errors(stack_name: str, name: str, instance: dict, scoped: set, exemptions: tuple) -> list[str]:
    """A non-GDPR stack's reads of EU data: dependencies on GDPR-scoped stacks and literal eu- ARNs
    (replicas, Global Datastore secondaries, state reads)."""
    where = f"{stack_name}: {name}"
    errors = [
        f"{where} depends on {dep.get('component')} in {dep['stack']}, which is GDPR-scoped: "
        "EU data may not be read outside the EU"
        for dep in (instance.get("dependencies") or {}).get("components") or []
        if isinstance(dep, dict) and dep.get("stack") in scoped
    ]
    for field, region in region_fields(instance.get("vars") or {}, "vars", keys=False):
        if region.startswith(EU_PREFIX) and not exempt(name, field, region, exemptions):
            errors.append(f"{where} {field} names an ARN in {region!r}: EU data may not be read outside the EU")
    return errors


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
        "and depends only on GDPR-scoped stacks, and no other stack depends on one or names an eu- ARN"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
