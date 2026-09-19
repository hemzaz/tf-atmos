#!/usr/bin/env bash
# List Terraform S3 lockfiles (<state key>.tflock) in the stack's state bucket.
# Run via `atmos workflow list-locks -f state-operations`.
# shellcheck source=../common/stack-context.sh
source "$(dirname "$0")/../common/stack-context.sh"

aws s3api list-objects-v2 --bucket "${STATE_BUCKET}" \
  --query "Contents[?ends_with(Key, '.tflock')].{Key:Key,LastModified:LastModified}" \
  --output table
