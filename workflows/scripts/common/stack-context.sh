#!/usr/bin/env bash
# Resolve stack context for workflow scripts from Atmos instead of ad-hoc
# tenant/account/environment parameters.
#
# Requires: STACK (e.g. fnx-prod-production). Exports TENANT, ACCOUNT, STAGE,
# ENVIRONMENT, REGION and STATE_BUCKET as resolved by `atmos describe component`
# (naming context lives in settings.context / settings.environment, not vars).
# jq -e makes a missing path fail the script instead of yielding "null".
set -euo pipefail

: "${STACK:?STACK is required (e.g. STACK=fnx-prod-production)}"

_ctx="$(atmos describe component "${CONTEXT_COMPONENT:-vpc/main}" -s "${STACK}" \
  --process-functions=false --provenance=false --format json)"

TENANT="$(jq -er '.settings.context.tenant' <<<"${_ctx}")"
ACCOUNT="$(jq -er '.settings.environment.account' <<<"${_ctx}")"
STAGE="$(jq -er '.settings.context.stage' <<<"${_ctx}")"
ENVIRONMENT="$(jq -er '.settings.context.environment' <<<"${_ctx}")"
REGION="$(jq -er '.vars.region' <<<"${_ctx}")"
STATE_BUCKET="$(jq -er '.backend.bucket' <<<"${_ctx}")"
export TENANT ACCOUNT STAGE ENVIRONMENT REGION STATE_BUCKET
unset _ctx
