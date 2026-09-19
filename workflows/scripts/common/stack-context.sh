#!/usr/bin/env bash
# Resolve stack context for workflow scripts from Atmos instead of ad-hoc
# tenant/account/environment parameters.
#
# Requires: STACK (e.g. fnx-prod-production). Exports TENANT, ACCOUNT, STAGE,
# ENVIRONMENT, REGION and STATE_BUCKET as resolved by `atmos describe component`.
set -euo pipefail

: "${STACK:?STACK is required (e.g. STACK=fnx-prod-production)}"

_ctx="$(atmos describe component "${CONTEXT_COMPONENT:-vpc/main}" -s "${STACK}" \
  --process-functions=false --provenance=false --format json)"

TENANT="$(jq -r '.vars.tenant' <<<"${_ctx}")"
ACCOUNT="$(jq -r '.vars.account' <<<"${_ctx}")"
STAGE="$(jq -r '.vars.stage' <<<"${_ctx}")"
ENVIRONMENT="$(jq -r '.vars.environment' <<<"${_ctx}")"
REGION="$(jq -r '.vars.region' <<<"${_ctx}")"
STATE_BUCKET="$(jq -r '.backend.bucket' <<<"${_ctx}")"
export TENANT ACCOUNT STAGE ENVIRONMENT REGION STATE_BUCKET
unset _ctx
