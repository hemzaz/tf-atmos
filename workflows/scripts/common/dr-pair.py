#!/usr/bin/env python3
"""Print a DR primary's failover facts as JSON, derived from the stacks' config.

The disaster-recovery workflows (workflows/disaster-recovery.yaml) render their
runbooks from these, so no stack, region or resource name is hard-coded there:

  STACK              the facts of DR primary STACK (dr-failover, dr-failback)
                     as one JSON object; exit 1 with the reason when STACK is
                     not a DR primary
  --check STACK      the same check, printing nothing on success
  --dr-region STACK  the DR region dr-status reports for STACK (below)

A DR primary is a stack that another stack names in settings.dr.standby_of
(fnx-ue2-prod for fnx-ue1-prod, fnx-ec1-prod for fnx-ew1-prod). Names follow
the components' "<tags.Environment>-<name>" convention (rds identifier,
elasticache cluster_id, eks name, lambda function_name, monitoring name), and
the standby's KMS alias is the primary kms/main's replica_alias_names entry for
the standby's region.

An EU (eu-*) primary's standby, backup copies and state replica must be in an
eu-* region too (GDPR: EU data, state and backups never leave the EU; the lint
check-data-residency.py enforces the same on the stacks): a runbook that would
move them elsewhere is refused here.

The DR region (--dr-region) is the stack's backup/main replica_region when it
copies cross-region (enable_cross_region_backup), else its standby's region
when it is a DR primary, else its own region when it is a standby; empty when
none applies.
"""
import argparse
import json
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
        "standby_prefix": environment(standby["eks/main"], f"{standby_name} eks/main"),
        "primary_db_instance": name(primary["rds/main"], "identifier", f"{primary_name} rds/main"),
        "db_instance": name(standby["rds/main"], "identifier", f"{standby_name} rds/main"),
        # The promoted instance keeps the source's database.
        "db_name": (primary["rds/main"].get("vars") or {}).get("db_name"),
        "primary_cache": name(primary["elasticache/main"], "cluster_id", f"{primary_name} elasticache/main"),
        "cache": name(standby["elasticache/main"], "cluster_id", f"{standby_name} elasticache/main"),
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
    _, replica_region = backup_replica(instances(config).get("backup/main"), f"{stack_name} backup/main")
    if replica_region:
        return replica_region
    standby = standby_of_stack(stacks, stack_name)
    if standby:
        return region(stacks[standby]) or ""
    if setting(config, "dr", "standby_of"):
        return region(config) or ""
    return ""


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
    args = parser.parse_args()

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
