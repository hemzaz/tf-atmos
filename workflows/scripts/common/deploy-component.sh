#!/usr/bin/env bash
# CD's deploy of one instance: plan to a planfile, check that planfile
# (check-plan-destroys.py: a delete or replace in a prod stage stack or a DR
# standby fails unless a scoped Allow-Destroy: trailer in
# BASE_SHA..GITHUB_SHA allows it; other stages get a warning), then apply
# THAT planfile, so what was checked is exactly what is applied (no re-plan;
# Terraform refuses the planfile if the state changed in between). Whether
# the plan changes anything is read from the plan JSON, never from
# -detailed-exitcode: with ci.enabled (atmos.yaml) Atmos maps plan's exit 2
# to 0. A plan without changes applies nothing.
#
# This is an in-job plan -> check -> apply, not the dropped stored-plan design
# (Q7): no plan is carried from the pull request to the merge; CD still
# deploys at merge, as Cloud Posse's atmos-terraform-apply does.
#
# Usage: deploy-component.sh <component>, with STACK and BASE_SHA (the
# stack's deployed/<stack> commit) set. terraform-cd.yml's deploy-affected and
# in-vpc.yml's deploy mode. Tests: test_deploy_component.py.
set -euo pipefail

component="${1:?usage: deploy-component.sh <component>}"
: "${STACK:?STACK is required}"
: "${BASE_SHA:?BASE_SHA is required: the last deployed commit of the stack}"

plans="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/cd-plans"
mkdir -p "${plans}"
# Absolute: Terraform runs in the component's directory.
planfile="$(cd "${plans}" && pwd)/${STACK}--${component//\//-}.planfile"
rm -f "${planfile}"

atmos terraform plan "${component}" -s "${STACK}" -- -out="${planfile}" -lock-timeout=10m </dev/null \
  || { echo "::error::${component} in ${STACK}: plan failed"; exit 1; }

rc=0
atmos terraform show "${component}" -s "${STACK}" -json "${planfile}" </dev/null \
  | python3 workflows/scripts/common/check-plan-destroys.py \
      --stack "${STACK}" --component "${component}" --base "${BASE_SHA}" \
  || rc=$?
case "${rc}" in
  0) atmos terraform deploy "${component}" -s "${STACK}" --planfile "${planfile}" </dev/null ;;
  3) ;; # no changes: nothing to apply
  *) exit 1 ;;
esac
rm -f "${planfile}"
