#!/usr/bin/env bash
# Start one ephemeral in-VPC runner: execute the runner pool's start policy
# (github-runners' <group>-start, a SimpleScaling +1). Auto Scaling applies the
# +1 atomically, so concurrent jobs each get their own runner, and caps it at
# max_size, so at max nothing starts and the job waits for a runner of the pool
# to free up. The runner takes one queued job labelled for the pool and leaves
# its group when done, lowering the capacity again.
#
# Requires: ASG (the pool's group, ci-components.py --pools "asg"), AWS
# credentials of a CI role (iam/ci ci-runner-pools.tf grants ExecutePolicy on
# the stack's runner pools only). Run through `atmos workflow start-runner -f
# ci-runners`, which installs the pinned aws-cli.
set -euo pipefail

: "${ASG:?ASG is required: the Auto Scaling group of the runner pool}"
[[ "${ASG}" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "::error::bad Auto Scaling group name '${ASG}'"; exit 1; }

# A pool already at max_size may refuse the +1 instead of capping it: that is
# a full pool, not a failure.
if ! out="$(aws autoscaling execute-policy --auto-scaling-group-name "${ASG}" \
    --policy-name "${ASG}-start" --no-honor-cooldown 2>&1)"; then
  if grep -qi "max" <<<"${out}"; then
    echo "::notice::runner pool ${ASG} is at max_size; the job waits for a free runner"
    exit 0
  fi
  echo "::error::could not start a runner in ${ASG}: ${out}"
  exit 1
fi
echo "runner pool ${ASG}: started one runner"
