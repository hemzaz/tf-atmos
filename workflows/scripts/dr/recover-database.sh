#!/usr/bin/env bash
# Recover database from backup or snapshot
# Run via `atmos workflow recover-database -f disaster-recovery`.
# shellcheck source=../common/stack-context.sh
source "$(dirname "$0")/../common/stack-context.sh"

WHITE='\033[1;37m'
NC='\033[0m'

echo -e "\n${WHITE}=== Database Recovery Options ===${NC}\n"



echo "Available RDS Snapshots:"
echo

aws rds describe-db-snapshots \
  --region "$REGION" \
  --query "DBSnapshots[?contains(DBSnapshotIdentifier, '${TENANT}')].{Identifier:DBSnapshotIdentifier,Engine:Engine,Created:SnapshotCreateTime,Status:Status}" \
  --output table

echo
echo "Point-in-Time Recovery Windows:"

aws rds describe-db-instances \
  --region "$REGION" \
  --query "DBInstances[?contains(DBInstanceIdentifier, '${TENANT}')].{Instance:DBInstanceIdentifier,LatestRestorableTime:LatestRestorableTime}" \
  --output table
