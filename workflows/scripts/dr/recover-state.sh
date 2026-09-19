#!/usr/bin/env bash
# Recover Terraform state from backup
# Run via `atmos workflow recover-state -f disaster-recovery`.
# shellcheck source=../common/stack-context.sh
source "$(dirname "$0")/../common/stack-context.sh"

WHITE='\033[1;37m'
NC='\033[0m'

echo -e "\n${WHITE}=== Terraform State Recovery ===${NC}\n"

BUCKET_NAME="${STATE_BUCKET}"

echo "Listing state file versions..."
echo "Bucket: $BUCKET_NAME"
echo

# List recent versions of state files
aws s3api list-object-versions \
  --bucket "$BUCKET_NAME" \
  --prefix "${COMPONENT_PREFIX:-}" \
  --max-items 20 \
  --query 'Versions[*].{Key:Key,VersionId:VersionId,LastModified:LastModified,Size:Size}' \
  --output table

echo
echo "To restore a specific version (bucket versioning must be enabled):"
echo "  aws s3api copy-object --bucket $BUCKET_NAME --key <key> \\"
echo "    --copy-source \"$BUCKET_NAME/<key>?versionId=<version-id>\""
