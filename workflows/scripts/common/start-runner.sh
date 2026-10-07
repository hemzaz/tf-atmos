#!/usr/bin/env bash
# Start one ephemeral in-VPC runner: raise the desired capacity of the runner
# pool's Auto Scaling group (github-runners) by one, up to its max_size. The
# runner takes one queued job labelled for the pool and lowers the capacity
# again when it leaves. At max_size nothing is started: the job waits for a
# runner of the pool to free up.
#
# Requires: ASG (the pool's group, ci-components.py --pools "asg"), AWS
# credentials of a CI role (iam/ci ci-runner-pools.tf grants SetDesiredCapacity
# on runner pools only). Run through `atmos workflow start-runner -f ci-runners`,
# which installs the pinned aws-cli.
set -euo pipefail

: "${ASG:?ASG is required: the Auto Scaling group of the runner pool}"
[[ "${ASG}" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "::error::bad Auto Scaling group name '${ASG}'"; exit 1; }

read -r desired max < <(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "${ASG}" \
  --query 'AutoScalingGroups[0].[DesiredCapacity,MaxSize]' --output text)
if [[ ! "${desired}" =~ ^[0-9]+$ || ! "${max}" =~ ^[0-9]+$ ]]; then
  echo "::error::runner pool ${ASG} not found"
  exit 1
fi
if (( desired >= max )); then
  echo "::notice::runner pool ${ASG} is at max_size ${max}; the job waits for a free runner"
  exit 0
fi
aws autoscaling set-desired-capacity --auto-scaling-group-name "${ASG}" \
  --desired-capacity "$(( desired + 1 ))" --no-honor-cooldown
echo "runner pool ${ASG}: desired capacity ${desired} -> $(( desired + 1 ))"
