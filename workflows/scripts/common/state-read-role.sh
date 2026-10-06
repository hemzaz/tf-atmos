#!/usr/bin/env bash
# Read the Terraform state bucket through the stack's READ-only backend role,
# never with the caller's own credentials. Source after stack-context.sh.
#
# The state bucket lives in the management account and grants nothing to the
# workload accounts' roles; access is only through the backend's stage-split
# access roles (components/terraform/backend). The role used here is the one
# the stack's own S3 backend assumes with TFSTATE_ACCESS=read
# (stacks/orgs/fnx/_defaults.yaml): fnx-terraform-backend-prod-read-role for a
# prod stack, fnx-terraform-backend-read-role for dev/staging. Those roles trust
# the matching CI plan role (the credentials disaster-recovery.yml runs with).
#
# Defines state_aws: `aws` with the assumed role's credentials, so the caller's
# (workload-account) credentials stay in place for every other call.
: "${STACK:?STACK is required}"

STATE_READ_ROLE_ARN="$(env TFSTATE_ACCESS=read atmos describe component "${CONTEXT_COMPONENT:-vpc/main}" -s "${STACK}" \
  --process-functions=false --provenance=false --format json | jq -er '.backend.assume_role.role_arn')"
export STATE_READ_ROLE_ARN

if ! _state_creds="$(aws sts assume-role --role-arn "${STATE_READ_ROLE_ARN}" --role-session-name "dr-${STACK}" \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)"; then
  echo "Cannot assume ${STATE_READ_ROLE_ARN}: the caller must be a principal that role trusts (backend/main access_roles in fnx-ue1-core)." >&2
  exit 1
fi
read -r _STATE_KEY _STATE_SECRET _STATE_TOKEN <<<"${_state_creds}"
unset _state_creds

state_aws() {
  AWS_ACCESS_KEY_ID="${_STATE_KEY}" AWS_SECRET_ACCESS_KEY="${_STATE_SECRET}" AWS_SESSION_TOKEN="${_STATE_TOKEN}" aws "$@"
}
