#!/usr/bin/env bash
# Check disaster recovery readiness and status
# Extracted from the inline `dr-status` workflow; run via `atmos workflow dr-status -f disaster-recovery`.
#
# The workflow's dependencies.tools installs the pinned aws CLI and jq through
# the Atmos toolchain (also in CI's atmos container, which ships neither).
for tool in aws jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "dr-status: '$tool' is not on PATH. Run it as 'atmos workflow dr-status -f disaster-recovery' (the workflow's toolchain installs the pinned aws CLI and jq), or install it." >&2
    exit 127
  fi
done

# shellcheck source=../common/stack-context.sh
source "$(dirname "$0")/../common/stack-context.sh"
# The state bucket is read through the stack's read-only backend role (state_aws).
# shellcheck source=../common/state-read-role.sh
source "$(dirname "$0")/../common/state-read-role.sh"

# --- check-dr-status ---
# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_error() { echo -e "${RED}[FAIL]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $*"; }

# aws_query <not-found regex> <command...>: runs the command, printing its
# stdout. Returns 0 on success; 3 when it fails with an error matching the
# regex (the resource is absent: a finding, not a failure); for any other
# error (AccessDenied, throttling, a bad region) it prints the error and
# returns 1, which the callers turn into an exit: a report built on swallowed
# errors would score a broken check as a missing resource.
aws_query() {
  local not_found="$1" err rc=0
  shift
  err="$(mktemp)"
  "$@" 2>"$err" || rc=$?
  if [[ $rc -ne 0 ]]; then
    if [[ -n "$not_found" ]] && grep -Eq "$not_found" "$err"; then
      rm -f "$err"
      return 3
    fi
    echo >&2
    echo "dr-status: '$*' failed: $(cat "$err")" >&2
    rm -f "$err"
    return 1
  fi
  rm -f "$err"
}

# fail: the query errored (not a not-found): stop with that error.
fail() {
  echo "dr-status: stopping on the error above; fix access or retry." >&2
  exit 1
}

echo -e "\n${WHITE}=== Disaster Recovery Status Check ===${NC}\n"

DR_REGION="${DR_REGION:-us-east-2}"

echo "Primary Stack: $STACK"
echo "Primary Region: $REGION"
echo "DR Region: $DR_REGION"
echo

DR_SCORE=0
DR_MAX=90 # 25 points previously scored on the DynamoDB lock table (replaced by S3 lockfiles); 15 on backup vaults

# =================================================================
# Check Terraform State Backend
# =================================================================
echo -e "${WHITE}1. Terraform State Backend${NC}"

BUCKET_NAME="${STATE_BUCKET}"

echo -n "   S3 bucket exists: "
rc=0
aws_query '\(404\)|Not Found|NoSuchBucket' state_aws s3api head-bucket --bucket "$BUCKET_NAME" >/dev/null || rc=$?
if [[ $rc -eq 0 ]]; then
  log_success "Yes"
  ((DR_SCORE+=10))

  echo -n "   Versioning enabled: "
  VERSIONING="$(aws_query '' state_aws s3api get-bucket-versioning --bucket "$BUCKET_NAME" --query 'Status' --output text)" || fail
  if [[ "$VERSIONING" == "Enabled" ]]; then
    log_success "Yes"
    ((DR_SCORE+=10))
  else
    log_error "No"
  fi

  echo -n "   Cross-region replication: "
  rc=0
  REPLICA="$(aws_query 'ReplicationConfigurationNotFoundError' state_aws s3api get-bucket-replication --bucket "$BUCKET_NAME" \
    --query 'ReplicationConfiguration.Rules[0].Destination.Bucket' --output text)" || rc=$?
  if [[ $rc -eq 0 ]]; then
    log_success "Configured (to ${REPLICA##*:})"
    ((DR_SCORE+=15))
  elif [[ $rc -eq 3 ]]; then
    log_warning "Not configured"
  else
    fail
  fi
elif [[ $rc -eq 3 ]]; then
  log_error "Not found"
else
  fail
fi

# State locking uses S3 native lockfiles (use_lockfile); no DynamoDB table to check.

# =================================================================
# Check VPC and Networking
# =================================================================
echo -e "\n${WHITE}2. VPC and Networking${NC}"

echo -n "   Primary VPC exists: "
PRIMARY_VPC="$(aws_query '' aws ec2 describe-vpcs --filters "Name=tag:Tenant,Values=${TENANT}" "Name=tag:Environment,Values=${ENVIRONMENT}" \
  --region "$REGION" --query 'Vpcs[0].VpcId' --output text)" || fail
if [[ "$PRIMARY_VPC" != "None" ]] && [[ -n "$PRIMARY_VPC" ]]; then
  log_success "$PRIMARY_VPC"
  ((DR_SCORE+=10))
else
  log_error "Not found"
fi

echo -n "   NAT Gateway redundancy: "
NAT_COUNT="$(aws_query '' aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$PRIMARY_VPC" "Name=state,Values=available" \
  --region "$REGION" --query 'NatGateways | length(@)' --output text)" || fail
if [[ "$NAT_COUNT" -gt 1 ]]; then
  log_success "$NAT_COUNT NAT Gateways (multi-AZ)"
  ((DR_SCORE+=5))
elif [[ "$NAT_COUNT" == "1" ]]; then
  log_warning "1 NAT Gateway (single point of failure)"
else
  log_error "No NAT Gateways"
fi

# =================================================================
# Check RDS Database
# =================================================================
echo -e "\n${WHITE}3. Database (RDS)${NC}"

RDS_INSTANCES="$(aws_query '' aws rds describe-db-instances --query "DBInstances[?contains(DBInstanceIdentifier, '${TENANT}') && contains(DBInstanceIdentifier, '${ENVIRONMENT}')]" \
  --region "$REGION")" || fail

if [[ -n "$RDS_INSTANCES" ]] && [[ "$RDS_INSTANCES" != "[]" ]]; then
  echo -n "   RDS instances found: "
  RDS_COUNT=$(echo "$RDS_INSTANCES" | jq 'length')
  log_success "$RDS_COUNT instance(s)"

  # Check Multi-AZ
  echo -n "   Multi-AZ deployment: "
  MULTI_AZ=$(echo "$RDS_INSTANCES" | jq -r '.[0].MultiAZ')
  if [[ "$MULTI_AZ" == "true" ]]; then
    log_success "Yes"
    ((DR_SCORE+=10))
  else
    log_warning "No (single AZ)"
  fi

  # Check automated backups
  echo -n "   Automated backups: "
  BACKUP_RETENTION=$(echo "$RDS_INSTANCES" | jq -r '.[0].BackupRetentionPeriod')
  if [[ "$BACKUP_RETENTION" -gt 0 ]]; then
    log_success "Yes ($BACKUP_RETENTION days retention)"
    ((DR_SCORE+=5))
  else
    log_error "No"
  fi

  # Check read replicas
  echo -n "   Read replicas: "
  READ_REPLICA_COUNT="$(aws_query '' aws rds describe-db-instances --query "DBInstances[?ReadReplicaSourceDBInstanceIdentifier!=null] | length(@)" \
    --region "$REGION" --output text)" || fail
  if [[ "$READ_REPLICA_COUNT" -gt 0 ]]; then
    log_success "$READ_REPLICA_COUNT replica(s)"
    ((DR_SCORE+=5))
  else
    log_warning "None"
  fi
else
  echo "   No RDS instances found for this environment"
fi

# =================================================================
# Check EKS Cluster
# =================================================================
echo -e "\n${WHITE}4. EKS Cluster${NC}"

EKS_CLUSTERS="$(aws_query '' aws eks list-clusters --region "$REGION" --query 'clusters' --output text)" || fail
# grep finding no cluster is not an error.
EKS_CLUSTERS="$(tr '\t' '\n' <<<"$EKS_CLUSTERS" | grep "$TENANT" || true)"

if [[ -n "$EKS_CLUSTERS" ]]; then
  for cluster in $EKS_CLUSTERS; do
    echo -n "   Cluster $cluster: "

    CLUSTER_STATUS="$(aws_query '' aws eks describe-cluster --name "$cluster" --region "$REGION" --query 'cluster.status' --output text)" || fail
    if [[ "$CLUSTER_STATUS" == "ACTIVE" ]]; then
      log_success "Active"
      ((DR_SCORE+=5))
    else
      log_error "$CLUSTER_STATUS"
    fi

    echo -n "   Node group redundancy: "
    NG_COUNT="$(aws_query '' aws eks list-nodegroups --cluster-name "$cluster" --region "$REGION" --query 'nodegroups | length(@)' --output text)" || fail
    if [[ "$NG_COUNT" -gt 1 ]]; then
      log_success "$NG_COUNT node groups"
      ((DR_SCORE+=5))
    elif [[ "$NG_COUNT" == "1" ]]; then
      log_warning "1 node group"
    else
      log_error "No node groups"
    fi
  done
else
  echo "   No EKS clusters found for this environment"
fi

# =================================================================
# Check AWS Backup vaults
# =================================================================
echo -e "\n${WHITE}5. Backup Vaults (AWS Backup)${NC}"

# backup/main's vault, <Environment>-<tags.Name or "backup">, and, when it
# copies cross-region, the replica vault <that name>-replica in replica_region
# (components/terraform/backup/main.tf). Names come from the stack's resolved
# config: nothing in this repo creates an S3 "backups" bucket.
vault_points() { # <vault> <region>: its recovery point count, empty when missing; exits on any other error
  local rc=0
  aws_query 'ResourceNotFoundException' aws backup describe-backup-vault --backup-vault-name "$1" --region "$2" \
    --query 'NumberOfRecoveryPoints' --output text || rc=$?
  [[ $rc -eq 0 || $rc -eq 3 ]] || fail
}

if BACKUP_CFG="$(atmos describe component backup/main -s "$STACK" \
  --process-functions=false --provenance=false --format json 2>/dev/null)" &&
  [[ "$(jq -r '.metadata.enabled // true' <<<"$BACKUP_CFG")" != "false" ]]; then
  VAULT="${ENVIRONMENT}-$(jq -r '.vars.tags.Name // "backup"' <<<"$BACKUP_CFG")"
  echo -n "   Vault $VAULT ($REGION): "
  POINTS="$(vault_points "$VAULT" "$REGION")"
  if [[ -n "$POINTS" ]]; then
    log_success "$POINTS recovery point(s)"
    ((DR_SCORE+=5))
  else
    log_error "Not found"
  fi

  echo -n "   Cross-region copy: "
  if [[ "$(jq -r '.vars.enable_cross_region_backup // false' <<<"$BACKUP_CFG")" == "true" ]]; then
    REPLICA_REGION="$(jq -r '.vars.replica_region' <<<"$BACKUP_CFG")"
    log_success "to $REPLICA_REGION"
    ((DR_SCORE+=5))
    echo -n "   Vault ${VAULT}-replica ($REPLICA_REGION): "
    POINTS="$(vault_points "${VAULT}-replica" "$REPLICA_REGION")"
    if [[ -n "$POINTS" && "$POINTS" != "0" ]]; then
      log_success "$POINTS recovery point(s)"
      ((DR_SCORE+=5))
    elif [[ "$POINTS" == "0" ]]; then
      log_warning "Empty (no copy job has completed yet)"
    else
      log_error "Not found"
    fi
  else
    log_warning "Not configured (backup/main enable_cross_region_backup)"
  fi
else
  log_warning "No backup/main instance in $STACK"
fi

# =================================================================
# DR Score Summary
# =================================================================
echo -e "\n${WHITE}===========================================${NC}"
echo -e "${WHITE}        DR READINESS SCORE${NC}"
echo -e "${WHITE}===========================================${NC}\n"

echo "Score: $DR_SCORE / $DR_MAX"
echo

if [[ $DR_SCORE -ge 80 ]]; then
  echo -e "${GREEN}Status: EXCELLENT - DR ready${NC}"
elif [[ $DR_SCORE -ge 60 ]]; then
  echo -e "${GREEN}Status: GOOD - Minor improvements recommended${NC}"
elif [[ $DR_SCORE -ge 40 ]]; then
  echo -e "${YELLOW}Status: FAIR - Several improvements needed${NC}"
else
  echo -e "${RED}Status: POOR - Significant DR gaps${NC}"
fi

echo
echo "Recommendations:"
if [[ $DR_SCORE -lt 80 ]]; then
  echo "  - Enable S3 cross-region replication for state bucket"
  echo "  - Copy backups to the DR region (backup/main enable_cross_region_backup)"
  echo "  - Enable Multi-AZ for all RDS instances"
  echo "  - Deploy NAT Gateways in multiple AZs"
  echo "  - Create read replicas in DR region"
else
  echo "  - Current DR configuration meets best practices"
  echo "  - Consider regular DR drills to validate procedures"
fi
