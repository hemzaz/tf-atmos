#!/usr/bin/env python3
"""Print a DR primary's failover facts as JSON, derived from the stacks' config.

The disaster-recovery workflows (workflows/disaster-recovery.yaml) render their
runbooks from these, so no stack, region or resource name is hard-coded there:

  STACK              the facts of DR primary STACK (dr-failover, dr-failback)
                     as one JSON object; exit 1 with the reason when STACK is
                     not a DR primary
  --check STACK      the same check, printing nothing on success
  --dr-region STACK  the DR region dr-status reports for STACK (below)
  --lint             read `atmos describe stacks --process-functions=false
                     --format json` on stdin and fail (exit 1) when a DR
                     primary's budget misses a standby, its DR region
                     disagrees with its standby or key, its backups are
                     not copied to the DR region, or the eks-backend-services
                     failover flavor or an rds promoted flavor drifts from
                     main-standby (below); lint runs it

A DR primary is a stack that another stack names in settings.dr.standby_of
(fnx-ue2-prod for fnx-ue1-prod, fnx-ec1-prod for fnx-ew1-prod). Names follow
the components' "<tags.Environment>-<name>" convention (rds identifier,
elasticache cluster_id, eks name, lambda function_name, monitoring name), and
the standby's KMS alias is the primary kms/main's replica_alias_names entry for
the standby's region. The Global Datastore is named by the primary elasticache's
global_replication_group_id_suffix only: AWS prefixes it with an
account-specific string, so the runbook looks the full id up by that suffix.

An EU (eu-*) primary's standby, backup copies and state replica must be in an
eu-* region too (GDPR: EU data, state and backups never leave the EU; the lint
check-data-residency.py enforces the same on the stacks): a runbook that would
move them elsewhere is refused here.

A standby shares its primary's account and has no budget of its own (owner
decision), so a DR primary has an enabled, non-abstract cost-optimization
instance and every such instance lists each standby's settings.prefix (its
Environment tag) in budget_additional_environment_tags (--lint).

A DR primary names its DR region in settings.dr.region, which the prod catalog
files template its replicas from (catalog/kms/main-prod,
catalog/secretsmanager/{app,infra}-prod, catalog/backup/main-prod). --lint
fails a primary whose settings.dr.region is not its standby's region, that
has no enabled, non-abstract kms/main or whose kms/main replica_regions is not
[settings.dr.region], whose
replica_alias_names has no settings.dr.region entry equal to the standby's
settings.prefix + "-main" (the alias the standby reaches the replica by), or
that has no enabled, non-abstract backup/main with enable_cross_region_backup
and replica_region == settings.dr.region (rds/data recovers from those copies:
owner decision 2026-10-07); a standby with no vars.region or settings.prefix;
and a stack that sets settings.dr.region with no standby. The runbook modes
(STACK, --check, --dr-region) stay tolerant of a missing backup copy.

Failover step 6 switches a standby's import of
stacks/catalog/eks-backend-services/main-standby.yaml to
main-standby-failover.yaml (docs/OPERATIONS.md, "Disaster recovery"). --lint
loads both files (yq, the !terraform.* tags kept) and fails unless the
failover file is main-standby.yaml with only metadata.enabled,
vars.database_name and vars.cluster_secret_store_name changed and no
vars.database_secret_arn (step 6 sets it in the stack file), in its imports
and its eks-backend-services/main block, with enabled true there and false in
main-standby and cluster_secret_store_name aws-secretsmanager; its vars.database_name is the db_name
of every DR primary's and every standby's rds/main (the promoted database
keeps its primary's); and every standby's external-secrets/main sets
create_default_cluster_secret_store: true (aws-secretsmanager is the default
store that creates, components/terraform/external-secrets/outputs.tf).

Reconciliation step 1 switches a standby's import of
stacks/catalog/rds/main-standby.yaml to main-standby-promoted.yaml, and
failback step 6 switches it back (docs/OPERATIONS.md, "Disaster recovery"):
both pairs share the files, so no step edits them for one stack. No stack
imports a promoted file while its pair is warm, so a describe never shows one:
--lint loads each stacks/catalog/rds/*-promoted.yaml and the file it is named
after (yq, the !terraform.* tags kept) and fails unless the base's rds/main
is a replica (a vars.replicate_source_db read, a real !terraform.state tag
and not a quoted look-alike string, and a dependencies.components
entry for rds/main with a stack) and the promoted file is the base without
exactly that read and that entry, in its imports and its rds/main block.
main-standby-promoted.yaml must exist.

The DR region (--dr-region) is the stack's settings.dr.region when it sets one
(a DR primary), else its backup/main replica_region when it copies
cross-region (enable_cross_region_backup), else its standby's region when it
is a DR primary, else its own region when it is a standby; empty when none
applies.
"""
import argparse
import copy
import json
import pathlib
import subprocess
import sys

# The instances read; describe stacks returns a stack when it has any of them.
COMPONENTS = (
    "vpc/main", "backup/main", "kms/main", "rds/main", "elasticache/main", "eks/main",
    "apigateway/main", "monitoring/main", "lambda/cognito-user-migration", "backend/main",
)
# Each side of a pair needs these to fail over (the standby has no kms/main:
# it runs on the primary key's replica).
PRIMARY_NEEDS = ("kms/main", "rds/main", "elasticache/main", "eks/main", "apigateway/main")
STANDBY_NEEDS = ("rds/main", "elasticache/main", "eks/main", "lambda/cognito-user-migration")
# The failover flavor of eks-backend-services/main (failover_findings): the paths it may change.
REPO = pathlib.Path(__file__).resolve().parents[3]
STANDBY_FILE = "stacks/catalog/eks-backend-services/main-standby.yaml"
FAILOVER_FILE = "stacks/catalog/eks-backend-services/main-standby-failover.yaml"
FAILOVER_INSTANCE = "eks-backend-services/main"
FAILOVER_CHANGES = (("metadata", "enabled"), ("vars", "database_name"),
                    ("vars", "cluster_secret_store_name"), ("vars", "database_secret_arn"))
# The promoted flavor of a standby's rds/main (promoted_findings): the base without the replica link.
RDS_STANDBY_FILE = "stacks/catalog/rds/main-standby.yaml"
RDS_PROMOTED_FILE = "stacks/catalog/rds/main-standby-promoted.yaml"
RDS_PROMOTED_GLOB = "stacks/catalog/rds/*-promoted.yaml"
RDS_INSTANCE = "rds/main"
# The default ClusterSecretStore external-secrets/main creates (components/terraform/external-secrets/outputs.tf).
DEFAULT_STORE = "aws-secretsmanager"
# yq drops a scalar's custom tag in JSON; keep !terraform.* reads as READ_MARK + "<tag> <value>". The
# marker (U+0001, raw in the yq expression: yq has no string escapes) keeps a quoted look-alike string,
# which Atmos passes on as text, from equalling a real read; a finding shows a read as '\x01!terraform...'.
READ_MARK = "\x01"
TAGGED_READS = f'(.. | select(tag | test("^!terraform"))) |= ("{READ_MARK}" + tag + " " + .)'


def instances(config: dict) -> dict:
    return ((config or {}).get("components") or {}).get("terraform") or {}


def setting(config: dict, *path):
    """The first instance's settings value at path (every instance inherits the same settings)."""
    for spec in instances(config).values():
        value = (spec or {}).get("settings") or {}
        for key in path:
            value = (value or {}).get(key) if isinstance(value, dict) else None
        if value is not None:
            return value
    return None


def region(config: dict):
    for spec in instances(config).values():
        found = ((spec or {}).get("vars") or {}).get("region")
        if found:
            return found
    return None


def standby_of_stack(stacks: dict, primary: str):
    """The stack whose settings.dr.standby_of is `primary`; ValueError for more than one."""
    found = sorted(name for name, config in stacks.items() if setting(config, "dr", "standby_of") == primary)
    if len(found) > 1:
        raise ValueError(f"{primary!r} has more than one DR standby ({', '.join(found)}): one is supported")
    return found[0] if found else None


def primaries(stacks: dict) -> list:
    return sorted({setting(config, "dr", "standby_of") for config in stacks.values()} - {None})


def enabled(spec: dict) -> bool:
    return ((spec or {}).get("metadata") or {}).get("enabled") is not False


def concrete(spec) -> bool:
    """Whether instance `spec` exists, is enabled and is not abstract (an abstract deploys nothing)."""
    return bool(spec) and enabled(spec) and (spec.get("metadata") or {}).get("type") != "abstract"


def is_read(value) -> bool:
    """Whether `value` is a real !terraform.state read as load_catalog returns it, not a quoted look-alike."""
    return isinstance(value, str) and value.startswith(READ_MARK + "!terraform.state ")


def environment(spec: dict, where: str) -> str:
    """The instance's tags.Environment (validated non-empty by the components); ValueError when unset."""
    value = (((spec or {}).get("vars") or {}).get("tags") or {}).get("Environment")
    if not value:
        raise ValueError(f"{where}: vars.tags.Environment is not set, so its resource names cannot be derived")
    return value


def name(spec: dict, key: str, where: str) -> str:
    """'<tags.Environment>-<vars[key]>', the components' resource name; ValueError when either is unset.

    The stacks set every name var the runbook reads (rds identifier, elasticache
    cluster_id, eks name, lambda function_name, monitoring name); one that relies
    on a module default is refused rather than guessed.
    """
    value = (spec.get("vars") or {}).get(key)
    if not value:
        raise ValueError(f"{where}: vars.{key} is not set in the stack; set it explicitly (the runbook names the resource from it)")
    return f"{environment(spec, where)}-{value}"


def global_datastore_suffix(spec: dict, where: str) -> str:
    """The primary cache's Global Datastore id suffix; ValueError when it creates none."""
    value = (spec.get("vars") or {}).get("global_replication_group_id_suffix")
    if not value:
        raise ValueError(f"{where}: vars.global_replication_group_id_suffix is not set, so there is no Global Datastore to fail over")
    return value


def backup_replica(spec, where: str) -> tuple:
    """(vault, region) of backup/main's cross-region copy, or (None, None)."""
    if not spec or not enabled(spec):
        return None, None
    variables = spec.get("vars") or {}
    if variables.get("enable_cross_region_backup") is not True:
        return None, None
    tag_name = (variables.get("tags") or {}).get("Name", "backup")
    return f"{environment(spec, where)}-{tag_name}-replica", variables.get("replica_region")


def state(stacks: dict, config: dict) -> dict:
    """The stack's state bucket and whether its backend replicates it (backend/main in settings.tfstate.stack).

    ValueError when backend/main replicates to another region than the stack's
    settings.tfstate.replica_region (TFSTATE_SOURCE=replica would read a bucket that is not there).
    """
    tfstate = setting(config, "tfstate") or {}
    backend = instances(stacks.get(tfstate.get("stack")) or {}).get("backend/main") or {}
    replicated = enabled(backend) and (backend.get("vars") or {}).get("s3_replication_enabled") is True
    backend_replica = (backend.get("vars") or {}).get("replica_region")
    if replicated and backend_replica != tfstate.get("replica_region"):
        raise ValueError(
            f"{tfstate.get('stack')} backend/main replicates {tfstate.get('bucket')} to {backend_replica}, "
            f"but settings.tfstate.replica_region is {tfstate.get('replica_region')}: make them equal"
        )
    return {
        "bucket": tfstate.get("bucket"),
        "region": tfstate.get("region"),
        "backend_stack": tfstate.get("stack"),
        "replicated": replicated,
        "replica_bucket": f"{tfstate.get('bucket')}-replica" if replicated else None,
        "replica_region": tfstate.get("replica_region") if replicated else None,
    }


def health_check(primary: dict, stacks: dict, pair: tuple) -> dict:
    """Where the primary's us-east-1 health check alarm goes: SNS actions, or relayed to the pair's regions."""
    variables = primary.get("vars") or {}
    relay_regions = variables.get("health_check_alarm_relay_regions") or []
    if relay_regions:
        topics = []
        for stack_name in pair:
            config = stacks[stack_name]
            monitoring = instances(config).get("monitoring/main")
            if region(config) in relay_regions and monitoring and enabled(monitoring):
                topics.append(f"{name(monitoring, 'name', f'{stack_name} monitoring/main')}-alarms")
        return {"relayed": True, "topics": topics}
    actions = variables.get("health_check_alarm_actions") or []
    return {"relayed": False, "topics": [arn.rsplit(":", 1)[-1] for arn in actions]}


def check_residency(facts: dict) -> None:
    """ValueError when an EU primary's runbook would name a non-EU data region."""
    if not facts["primary_region"].startswith("eu-"):
        return
    regions = {
        "standby": facts["standby_region"],
        "backup copy": facts["backup_replica_region"],
        "state bucket": facts["state"]["region"],
        "state replica": facts["state"]["replica_region"],
    }
    outside = {what: where for what, where in regions.items() if where and not where.startswith("eu-")}
    if outside:
        raise ValueError(
            f"{facts['primary']!r} is an EU stack but its "
            + ", ".join(f"{what} is in {where}" for what, where in outside.items())
            + ": GDPR keeps EU data, state and backups in the EU (check-data-residency.py)"
        )


def pair_facts(stacks: dict, primary_name: str) -> dict:
    """The failover facts of DR primary `primary_name`; ValueError when it is not one."""
    if primary_name not in stacks:
        raise ValueError(f"Unknown stack {primary_name!r}")
    standby_name = standby_of_stack(stacks, primary_name)
    if standby_name is None:
        raise ValueError(
            f"{primary_name}: this runbook covers a DR primary and its standby only ("
            + ", ".join(f"{p} -> {standby_of_stack(stacks, p)}" for p in primaries(stacks))
            + f"); no stack sets settings.dr.standby_of: {primary_name}. See docs/OPERATIONS.md, Disaster recovery."
        )
    primary, standby = instances(stacks[primary_name]), instances(stacks[standby_name])
    missing = [f"{primary_name} {c}" for c in PRIMARY_NEEDS if c not in primary]
    missing += [f"{standby_name} {c}" for c in STANDBY_NEEDS if c not in standby]
    if missing:
        raise ValueError(f"{primary_name} -> {standby_name}: missing {', '.join(missing)}")

    standby_region = region(stacks[standby_name])
    alias = ((primary["kms/main"].get("vars") or {}).get("replica_alias_names") or {}).get(standby_region)
    if not alias:
        raise ValueError(f"{primary_name} kms/main has no replica_alias_names entry for {standby_region}")
    vault, vault_region = backup_replica(primary.get("backup/main"), f"{primary_name} backup/main")
    facts = {
        "primary": primary_name,
        "primary_region": region(stacks[primary_name]),
        "primary_prefix": environment(primary["eks/main"], f"{primary_name} eks/main"),
        "standby": standby_name,
        "standby_region": standby_region,
        "primary_db_instance": name(primary["rds/main"], "identifier", f"{primary_name} rds/main"),
        "db_instance": name(standby["rds/main"], "identifier", f"{standby_name} rds/main"),
        # The promoted instance keeps the source's database.
        "db_name": (primary["rds/main"].get("vars") or {}).get("db_name"),
        "primary_cache": name(primary["elasticache/main"], "cluster_id", f"{primary_name} elasticache/main"),
        "cache": name(standby["elasticache/main"], "cluster_id", f"{standby_name} elasticache/main"),
        "global_datastore_suffix": global_datastore_suffix(primary["elasticache/main"], f"{primary_name} elasticache/main"),
        "cluster": name(standby["eks/main"], "name", f"{standby_name} eks/main"),
        "kms_alias": f"alias/{alias}",
        "user_migration": name(standby["lambda/cognito-user-migration"], "function_name", f"{standby_name} lambda/cognito-user-migration"),
        "backup_replica_vault": vault,
        "backup_replica_region": vault_region,
        "health_check_alarm": health_check(primary["apigateway/main"], stacks, (primary_name, standby_name)),
        "state": state(stacks, stacks[primary_name]),
    }
    check_residency(facts)
    return facts


def dr_region(stacks: dict, stack_name: str) -> str:
    """The DR region of `stack_name` (module docstring), '' when none applies."""
    if stack_name not in stacks:
        raise ValueError(f"Unknown stack {stack_name!r}")
    config = stacks[stack_name]
    declared = setting(config, "dr", "region")
    if declared:
        return declared
    _, replica_region = backup_replica(instances(config).get("backup/main"), f"{stack_name} backup/main")
    if replica_region:
        return replica_region
    standby = standby_of_stack(stacks, stack_name)
    if standby:
        return region(stacks[standby]) or ""
    if setting(config, "dr", "standby_of"):
        return region(config) or ""
    return ""


def budget_findings(stacks: dict) -> list:
    """One line per DR standby missing from its primary's budget_additional_environment_tags (--lint)."""
    findings = []
    for primary_name in primaries(stacks):
        standbys = sorted(n for n, config in stacks.items() if setting(config, "dr", "standby_of") == primary_name)
        if primary_name not in stacks:
            findings.append(f"{', '.join(standbys)}: settings.dr.standby_of names {primary_name!r}, which is not a stack")
            continue
        budgets = []
        for instance_name, spec in sorted(instances(stacks[primary_name]).items()):
            metadata = (spec or {}).get("metadata") or {}
            component = metadata.get("component") or instance_name
            if component == "cost-optimization" and concrete(spec):
                budgets.append((instance_name, spec))
        if not budgets:
            findings.append(
                f"{primary_name}: a DR primary (of {', '.join(standbys)}) with no enabled cost-optimization instance, "
                "so no budget counts the standby"
            )
        for instance_name, spec in budgets:
            tags = (spec.get("vars") or {}).get("budget_additional_environment_tags") or []
            for standby in standbys:
                prefix = setting(stacks[standby], "prefix")
                if prefix not in tags:
                    findings.append(
                        f"{primary_name} {instance_name}: budget_additional_environment_tags {tags} lacks {prefix!r}, "
                        f"the settings.prefix of its DR standby {standby} (settings.dr.standby_of): the standby shares "
                        "the account and has no budget of its own"
                    )
    return findings


def primary_dr_findings(stacks: dict, primary_name: str, standby_name: str) -> list:
    """The --lint findings of DR primary `primary_name` against its standby `standby_name` (dr_region_findings)."""
    declared = setting(stacks[primary_name], "dr", "region")
    standby_region = region(stacks[standby_name])
    where = f"{primary_name} (DR primary of {standby_name})"
    if not standby_region:
        return [f"{where}: its DR standby {standby_name} has no vars.region, so settings.dr.region cannot be checked"]
    # The kms and backup checks below compare against settings.dr.region, so it must be right first.
    if declared != standby_region:
        return [f"{where}: settings.dr.region is {declared!r}, not {standby_region!r}, the region of its DR standby"]
    findings = []
    primary = instances(stacks[primary_name])
    prefix = setting(stacks[standby_name], "prefix")
    expected = f"{prefix}-main"
    if not prefix:
        findings.append(
            f"{where} kms/main: standby {standby_name} has no settings.prefix, so the alias it reaches the "
            f"replica by (replica_alias_names[{declared!r}], <prefix>-main) cannot be checked"
        )
    kms = primary.get("kms/main")
    if not concrete(kms):
        findings.append(f"{where}: no enabled, non-abstract kms/main, so nothing replicates the key to {declared}")
    else:
        variables = kms.get("vars") or {}
        replicas = variables.get("replica_regions")
        if replicas != [declared]:
            findings.append(f"{where} kms/main: replica_regions is {replicas}, not [{declared!r}] (settings.dr.region)")
        alias = (variables.get("replica_alias_names") or {}).get(declared)
        if prefix and alias != expected:
            findings.append(
                f"{where} kms/main: replica_alias_names[{declared!r}] is {alias!r}, not {expected!r} "
                f"({standby_name}'s settings.prefix + \"-main\", the alias it reaches the replica by)"
            )
    # rds/data recovers from backup copies in the DR region (owner decision 2026-10-07).
    backup = primary.get("backup/main")
    variables = (backup or {}).get("vars") or {}
    if not (concrete(backup) and variables.get("enable_cross_region_backup") is True):
        findings.append(
            f"{where}: no enabled, non-abstract backup/main with enable_cross_region_backup: true copies recovery "
            f"points to {declared} (replica_region = settings.dr.region), so the standby has no backup to restore "
            "rds/data from (docs/OPERATIONS.md, Disaster recovery)"
        )
    elif variables.get("replica_region") != declared:
        findings.append(
            f"{where} backup/main: replica_region is {variables.get('replica_region')!r}, not {declared!r} "
            "(settings.dr.region)"
        )
    return findings


def dr_region_findings(stacks: dict) -> list:
    """One line per stack whose settings.dr.region disagrees with its DR standby, key or backups (--lint)."""
    findings = []
    standbys = {}
    for primary_name in primaries(stacks):
        if primary_name not in stacks:
            continue  # budget_findings reports it
        try:
            standbys[primary_name] = standby_of_stack(stacks, primary_name)
        except ValueError as error:
            findings.append(str(error))
    named = set(primaries(stacks))
    for stack_name, config in sorted(stacks.items()):
        declared = setting(config, "dr", "region")
        if stack_name in standbys:
            findings += primary_dr_findings(stacks, stack_name, standbys[stack_name])
        elif declared and stack_name not in named:
            findings.append(
                f"{stack_name}: settings.dr.region is {declared!r}, but no stack names it in "
                "settings.dr.standby_of (only a DR primary sets it): add its DR standby (a stack with "
                f"settings.dr.standby_of: {stack_name}) or remove settings.dr.region"
            )
    return findings


def load_catalog(relative: str) -> dict:
    """The single YAML document of repo file `relative`, its !terraform.* reads as strings; ValueError when it fails."""
    command = ["yq", "--yaml-fix-merge-anchor-to-spec", "-o", "json", "-I0", TAGGED_READS, str(REPO / relative)]
    try:
        docs = [json.loads(line) for line in subprocess.check_output(command, text=True).splitlines() if line.strip()]
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        raise ValueError(f"{relative}: cannot be read with yq: {error}") from None
    if len(docs) != 1 or not isinstance(docs[0], dict):
        raise ValueError(f"{relative}: expected one YAML mapping, found {len(docs)} documents")
    return docs[0]


class _Missing:
    def __repr__(self) -> str:
        return "not set"


MISSING = _Missing()


def differences(left, right, path=()) -> list:
    """(dotted path, left value, right value) for each leaf where left and right differ; MISSING for an absent key."""
    if isinstance(left, dict) and isinstance(right, dict):
        found = []
        for key in sorted(set(left) | set(right), key=str):
            found += differences(left.get(key, MISSING), right.get(key, MISSING), (*path, str(key)))
        return found
    return [] if left == right else [(".".join(path) or "(document)", left, right)]


def failover_findings(stacks: dict, standby_doc: dict, failover_doc: dict) -> list:
    """One line per way the eks-backend-services failover flavor drifts from main-standby or the stacks (--lint)."""
    findings = []
    blocks = {}
    for relative, doc in ((STANDBY_FILE, standby_doc), (FAILOVER_FILE, failover_doc)):
        block = ((doc.get("components") or {}).get("terraform") or {}).get(FAILOVER_INSTANCE)
        if not isinstance(block, dict):
            findings.append(f"{relative}: no components.terraform.{FAILOVER_INSTANCE}")
        blocks[relative] = block or {}
    if findings:
        return findings
    failover_vars = blocks[FAILOVER_FILE].get("vars") or {}
    # The allowed deltas are compared away below, so pin their values here.
    for relative, wanted, why in ((FAILOVER_FILE, True, "failover step 6 deploys it"),
                                  (STANDBY_FILE, False, "it stays off while the standby is warm")):
        enabled = (blocks[relative].get("metadata") or {}).get("enabled")
        if enabled is not wanted:
            findings.append(f"{relative}: {FAILOVER_INSTANCE} metadata.enabled is {enabled!r}, not {wanted}: {why}")
    if "database_secret_arn" in failover_vars:
        findings.append(
            f"{FAILOVER_FILE}: {FAILOVER_INSTANCE} sets vars.database_secret_arn ({failover_vars['database_secret_arn']!r}); "
            "it must not: the secret exists only after promotion, so failover step 6 sets it in the standby's stack file"
        )

    def comparable(doc):
        doc = copy.deepcopy(doc)
        block = doc["components"]["terraform"][FAILOVER_INSTANCE]
        for section, key in FAILOVER_CHANGES:
            (block.get(section) or {}).pop(key, None)
        return doc

    for where, standby_value, failover_value in differences(comparable(standby_doc), comparable(failover_doc)):
        findings.append(
            f"{FAILOVER_FILE}: {where} is {failover_value!r}, not {standby_value!r} as in {STANDBY_FILE}: the failover "
            "flavor is main-standby with only metadata.enabled, vars.database_name and vars.cluster_secret_store_name "
            "changed and no vars.database_secret_arn"
        )

    database_name = failover_vars.get("database_name")
    standbys = sorted(n for n, config in stacks.items() if setting(config, "dr", "standby_of"))
    for stack_name in [p for p in primaries(stacks) if p in stacks] + standbys:
        rds = instances(stacks[stack_name]).get("rds/main") or {}
        db_name = (rds.get("vars") or {}).get("db_name")
        if db_name != database_name:
            findings.append(
                f"{FAILOVER_FILE}: {FAILOVER_INSTANCE} vars.database_name is {database_name!r}, not {db_name!r}, the "
                f"db_name of {stack_name} rds/main (the promoted standby database keeps its primary's db_name)"
            )
    store = failover_vars.get("cluster_secret_store_name")
    if store != DEFAULT_STORE:
        findings.append(
            f"{FAILOVER_FILE}: {FAILOVER_INSTANCE} vars.cluster_secret_store_name is {store!r}, not "
            f"{DEFAULT_STORE!r}, the default ClusterSecretStore external-secrets/main creates (components/terraform/external-secrets/outputs.tf)"
        )
    for stack_name in standbys:
        external_secrets = instances(stacks[stack_name]).get("external-secrets/main") or {}
        creates = (external_secrets.get("vars") or {}).get("create_default_cluster_secret_store")
        if creates is not True:
            findings.append(
                f"{stack_name} external-secrets/main: create_default_cluster_secret_store is {creates!r}, not true: "
                f"{FAILOVER_FILE} sets cluster_secret_store_name to {store!r}, the store only that creates "
                "(components/terraform/external-secrets/outputs.tf)"
            )
    return findings


def promoted_findings(base_file: str, base_doc: dict, promoted_file: str, promoted_doc: dict) -> list:
    """One line per way an rds promoted flavor drifts from the replica flavor it is named after (--lint)."""
    blocks = {}
    for relative, doc in ((base_file, base_doc), (promoted_file, promoted_doc)):
        block = ((doc.get("components") or {}).get("terraform") or {}).get(RDS_INSTANCE)
        if not isinstance(block, dict):
            return [f"{relative}: no components.terraform.{RDS_INSTANCE}"]
        blocks[relative] = block

    def replica_links(block):
        """The replicate_source_db read and the cross-stack rds/main dependencies of `block`."""
        read = (block.get("vars") or {}).get("replicate_source_db", MISSING)
        deps = [d for d in ((block.get("dependencies") or {}).get("components") or [])
                if isinstance(d, dict) and d.get("component") == RDS_INSTANCE and d.get("stack") is not None]
        return read, deps

    findings = []
    base_read, base_deps = replica_links(blocks[base_file])
    if not is_read(base_read) or len(base_deps) != 1:
        findings.append(
            f"{base_file}: {RDS_INSTANCE} is not a replica (vars.replicate_source_db {base_read!r}, "
            f"{len(base_deps)} rds/main dependencies with a stack): {promoted_file} has no replica link to drop"
        )
    promoted_read, promoted_deps = replica_links(blocks[promoted_file])
    if promoted_read is not MISSING or promoted_deps:
        findings.append(
            f"{promoted_file}: {RDS_INSTANCE} keeps the replica link (vars.replicate_source_db {promoted_read!r}, "
            f"rds/main dependencies {promoted_deps!r}): a promoted standby replicates nothing"
        )
    if findings:
        return findings

    expected = copy.deepcopy(base_doc)
    block = expected["components"]["terraform"][RDS_INSTANCE]
    del block["vars"]["replicate_source_db"]
    block["dependencies"]["components"] = [d for d in block["dependencies"]["components"] if d not in base_deps]
    return [
        f"{promoted_file}: {where} is {promoted_value!r}, not {base_value!r} as in {base_file}: the promoted flavor "
        "is the replica flavor minus only vars.replicate_source_db and its rds/main dependency"
        for where, base_value, promoted_value in differences(expected, promoted_doc)
    ]


def promoted_files() -> list:
    """(base, promoted) repo-relative paths of each rds promoted flavor, main-standby's first."""
    found = sorted(str(path.relative_to(REPO)) for path in REPO.glob(RDS_PROMOTED_GLOB))
    pairs = [(RDS_STANDBY_FILE, RDS_PROMOTED_FILE)]
    pairs += [(f.replace("-promoted.yaml", ".yaml"), f) for f in found if f != RDS_PROMOTED_FILE]
    return pairs


def describe_stacks() -> dict:
    """The stacks' resolved config; ValueError, one line, when atmos fails or returns no JSON."""
    command = ["atmos", "describe", "stacks", "--process-functions=false", "--format", "json",
               "--components", ",".join(COMPONENTS), "--sections", "settings,vars,metadata"]
    try:
        return json.loads(subprocess.check_output(command))
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        raise ValueError(f"dr-pair: '{' '.join(command[:3])}' failed: {error}") from None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("stack", nargs="?")
    mode.add_argument("--check", metavar="STACK")
    mode.add_argument("--dr-region", metavar="STACK")
    mode.add_argument("--lint", action="store_true")
    args = parser.parse_args()

    if args.lint:
        stacks = json.load(sys.stdin)
        findings = budget_findings(stacks) + dr_region_findings(stacks)
        try:
            findings += failover_findings(stacks, load_catalog(STANDBY_FILE), load_catalog(FAILOVER_FILE))
        except ValueError as error:
            findings.append(str(error))
        for base_file, promoted_file in promoted_files():
            try:
                findings += promoted_findings(base_file, load_catalog(base_file),
                                              promoted_file, load_catalog(promoted_file))
            except ValueError as error:
                findings.append(str(error))
        for finding in findings:
            print(f"dr-pair: {finding}", file=sys.stderr)
        return 1 if findings else 0
    try:
        stacks = describe_stacks()
        if args.dr_region is not None:
            print(dr_region(stacks, args.dr_region))
            return 0
        facts = pair_facts(stacks, args.check if args.check is not None else args.stack)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1
    if args.check is None:
        print(json.dumps(facts, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
