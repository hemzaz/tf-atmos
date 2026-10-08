#!/usr/bin/env bash
# Start one ephemeral in-VPC runner: execute the runner pool's start policy
# (github-runners' <group>-start, a SimpleScaling +1). Auto Scaling applies the
# +1 atomically, so concurrent jobs each get their own runner. At max_size it
# silently caps the +1: nothing starts, and the job would wait in GitHub's
# queue (up to 24 h, holding its workflow's concurrency group). So a full pool
# fails here instead. Per-pool concurrency on the callers keeps at most
# IN_VPC_JOBS_PER_POOL (3) of these jobs per pool, and check-cluster-api-ci.py
# requires max_size >= 3, so a full pool means runners that never left. The
# runner takes one queued job labelled for the pool and leaves when done
# (deleting its lease, github-runners), lowering the capacity again.
#
# Requires: ASG (the pool's group, ci-components.py --pools "asg"), AWS
# credentials of the stack's CI apply role (iam/ci ci-runner-pools.tf grants
# ExecutePolicy on the stack's runner pools only, and
# DescribeAutoScalingGroups). Run through `atmos workflow start-runner -f
# ci-runners`, which installs the pinned aws-cli.
set -euo pipefail

: "${ASG:?ASG is required: the Auto Scaling group of the runner pool}"
[[ "${ASG}" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "::error::bad Auto Scaling group name '${ASG}'"; exit 1; }

# Runs an aws command, retrying a scaling activity in progress, contention or
# throttling after 5, 10 and 20 s; prints its output, fails on anything else.
aws_retrying() {
  local out delay
  for delay in 5 10 20 ""; do
    if out="$(aws "$@" 2>&1)"; then
      printf '%s\n' "${out}"
      return 0
    fi
    if [ -n "${delay}" ] && grep -Eq "ScalingActivityInProgress|ResourceContention|Throttling" <<<"${out}"; then
      echo "runner pool ${ASG}: ${out}; retrying in ${delay} s" >&2
      sleep "${delay}"
      continue
    fi
    echo "::error::runner pool ${ASG}: ${out}" >&2
    return 1
  done
}

capacity="$(aws_retrying autoscaling describe-auto-scaling-groups --auto-scaling-group-names "${ASG}" \
  --query 'AutoScalingGroups[0].[DesiredCapacity,MaxSize]' --output text)"
read -r desired max <<<"${capacity}"
if [[ ! "${desired}" =~ ^[0-9]+$ || ! "${max}" =~ ^[0-9]+$ ]]; then
  echo "::error::runner pool ${ASG} not found"
  exit 1
fi
if (( desired >= max )); then
  echo "::error::runner pool ${ASG} is full (desired=max=${max}); this job would never get a runner"
  exit 1
fi

aws_retrying autoscaling execute-policy --auto-scaling-group-name "${ASG}" \
  --policy-name "${ASG}-start" --no-honor-cooldown >/dev/null
echo "runner pool ${ASG}: started one runner (desired ${desired} of ${max})"
