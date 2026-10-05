#!/bin/bash
# GitHub Actions runner bootstrap (Amazon Linux 2023). Rendered by main.tf
# (templatefile); a $${...} here is a shell expansion, a single-dollar one a
# Terraform value. Ported from Cloud Posse aws-github-runners' user-data.sh and
# create-latest-svc.sh: Docker for container jobs, a pinned and checksummed
# runner release instead of "latest", and (ephemeral) one job per instance.
set -euo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

${pre_install}

dnf install -y docker git jq libicu
systemctl enable --now docker

imds() {
  local token
  token=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
  curl -s -H "X-aws-ec2-metadata-token: $${token}" "http://169.254.169.254/latest/meta-data/$1"
}
INSTANCE_ID=$(imds instance-id)
REGION=$(imds placement/region)
INSTANCE_TYPE=$(imds instance-type)

# Leave the Auto Scaling group and lower its desired capacity, so the group
# does not replace this instance: work arrives by raising desired capacity.
terminate() {
  aws autoscaling terminate-instance-in-auto-scaling-group --region "$${REGION}" \
    --instance-id "$${INSTANCE_ID}" --should-decrement-desired-capacity || shutdown -h now
}

# The runner and its jobs run as an unprivileged user; the docker group lets
# container jobs (the atmos image) start.
id runner >/dev/null 2>&1 || useradd --create-home runner
usermod -aG docker runner

RUNNER_DIR=/opt/actions-runner
mkdir -p "$${RUNNER_DIR}"
cd "$${RUNNER_DIR}"
TARBALL="actions-runner-linux-x64-${runner_version}.tar.gz"
curl -fsSL -o "$${TARBALL}" "https://github.com/actions/runner/releases/download/v${runner_version}/$${TARBALL}"
echo "${runner_sha256}  $${TARBALL}" | sha256sum -c -
tar xzf "$${TARBALL}"
rm -f "$${TARBALL}"
chown -R runner:runner "$${RUNNER_DIR}"

RUNNER_TOKEN=$(aws ssm get-parameter --region "$${REGION}" --with-decryption \
  --name "${token_parameter_name}" --query Parameter.Value --output text)

sudo -u runner ./config.sh --unattended --disableupdate \
  --url "https://github.com/${github_scope}" --token "$${RUNNER_TOKEN}" \
  --name "$${INSTANCE_ID}" --labels "${labels},$${INSTANCE_TYPE}" \
  %{ if runner_group != "" }--runnergroup "${runner_group}" %{ endif }%{ if ephemeral }--ephemeral%{ endif }
unset RUNNER_TOKEN

${post_install}

%{ if ephemeral ~}
# One job, then leave. A runner that gets no job within the idle timeout
# leaves too; GitHub removes its offline registration.
sudo -u runner ./run.sh &
RUNNER_PID=$!
(
  sleep ${idle_timeout_seconds}
  if ! ls "$${RUNNER_DIR}"/_diag/Worker_*.log >/dev/null 2>&1; then
    echo "No job within ${idle_timeout_seconds} seconds; terminating."
    terminate
  fi
) &
wait "$${RUNNER_PID}" || true
terminate
%{ else ~}
./svc.sh install runner
./svc.sh start
%{ endif ~}
