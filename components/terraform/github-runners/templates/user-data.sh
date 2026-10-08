#!/bin/bash
# GitHub Actions runner bootstrap (Amazon Linux 2023). Rendered by main.tf
# (templatefile); a $${...} here is a shell expansion, a single-dollar one a
# Terraform value. Ported from Cloud Posse aws-github-runners' user-data.sh,
# with a pinned and checksummed runner release and a just-in-time runner
# configuration instead of a registration token: the jit function writes this
# instance's single-use configuration to SSM while the instance waits in its
# launch lifecycle hook; the instance reads it, deletes it, runs one job and
# leaves.
set -euo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1
# Until the instance knows who it is, a failure can only power it off
# (instance_initiated_shutdown_behavior terminates it).
trap 'shutdown -h now' EXIT

imds() {
  local token
  token=$(curl -sfX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
  curl -sf -H "X-aws-ec2-metadata-token: $${token}" "http://169.254.169.254/latest/meta-data/$1"
}
INSTANCE_ID=$(imds instance-id)
REGION=$(imds placement/region)

# Leave. The instance role has no Auto Scaling permission (it could not be
# scoped to this instance): deleting this instance's lease, which the jit
# function wrote at launch, makes the function end the instance and lower
# desired capacity, so the group does not replace it (work arrives by raising
# desired capacity). If that event is lost, power off after 600 s: the group
# replaces the instance, and the replacement idles out with a decrement.
# A job the fork guard refused (its marker, files/job-started.sh) leaves
# WITHOUT lowering desired capacity: powering off with the lease kept, the
# group replaces this runner, and the replacement takes the next queued job.
REFUSED_MARKER=/var/lib/runner-state/refused
terminate() {
  if [ -e "$${REFUSED_MARKER}" ]; then
    echo "The fork guard refused this runner's job; leaving so a replacement takes the next one."
    shutdown -h now
    return
  fi
  aws ssm delete-parameter --region "$${REGION}" --name "${jit_parameter_prefix}/lease/$${INSTANCE_ID}" ||
    echo "Could not delete the lease; powering off in 600 s instead."
  sleep 600
  shutdown -h now
}
# Whatever happens from here on, failed bootstrap or finished job, the
# instance leaves: an ephemeral runner never serves a second job.
trap terminate EXIT

${pre_install}

dnf install -y docker git jq libicu
systemctl enable --now docker

# The runner and its jobs run as an unprivileged user; the docker group lets
# container jobs (the atmos image) start.
id runner >/dev/null 2>&1 || useradd --create-home runner
usermod -aG docker runner
# The fork guard's refusal marker (the hook runs as the runner user).
install -d -m 0700 -o runner -g runner /var/lib/runner-state

RUNNER_DIR=/opt/actions-runner
mkdir -p "$${RUNNER_DIR}"
cd "$${RUNNER_DIR}"
TARBALL="actions-runner-linux-x64-${runner_version}.tar.gz"
curl -fsSL -o "$${TARBALL}" "https://github.com/actions/runner/releases/download/v${runner_version}/$${TARBALL}"
echo "${runner_sha256}  $${TARBALL}" | sha256sum -c -
tar xzf "$${TARBALL}"
rm -f "$${TARBALL}"
chown -R runner:runner "$${RUNNER_DIR}"

${post_install}

# The fork guard (files/job-started.sh): the runner's job-started hook, named
# in .env (which the runner loads), fails a job before its first step unless
# it comes from github_scope by push, dispatch, schedule or merge queue, or
# from a same-repository pull request, and (allowed_refs) on an allowed ref.
# Workflow files are pull-request controlled; this hook and its policy are not.
install -d -m 0755 /opt/runner-hooks
cat > /opt/runner-hooks/job-started.sh <<'HOOK'
${job_started_hook}
HOOK
cat > /opt/runner-hooks/policy <<'POLICY'
ALLOWED_SCOPE='${github_scope}'
ALLOWED_REFS='${join(" ", allowed_refs)}'
REFUSED_MARKER='/var/lib/runner-state/refused'
POLICY
chmod 0755 /opt/runner-hooks/job-started.sh
chmod 0644 /opt/runner-hooks/policy
echo "ACTIONS_RUNNER_HOOK_JOB_STARTED=/opt/runner-hooks/job-started.sh" > "$${RUNNER_DIR}/.env"

# The jit function writes the configuration while the launch hook holds this
# instance (it may still be on its way); read it once, then delete it.
JIT_PARAMETER="${jit_parameter_prefix}/$${INSTANCE_ID}"
for _ in $(seq 1 60); do
  if JIT_CONFIG=$(aws ssm get-parameter --region "$${REGION}" --with-decryption \
      --name "$${JIT_PARAMETER}" --query Parameter.Value --output text 2>/dev/null); then
    break
  fi
  JIT_CONFIG=""
  sleep 5
done
[ -n "$${JIT_CONFIG}" ] || { echo "No JIT configuration at $${JIT_PARAMETER}"; exit 1; }
aws ssm delete-parameter --region "$${REGION}" --name "$${JIT_PARAMETER}"

# One job, then leave (the EXIT trap). A runner that gets no job within the
# idle timeout leaves too; the jit function removes its registration.
sudo -u runner ./run.sh --jitconfig "$${JIT_CONFIG}" &
RUNNER_PID=$!
unset JIT_CONFIG
(
  sleep ${idle_timeout_seconds}
  if ! ls "$${RUNNER_DIR}"/_diag/Worker_*.log >/dev/null 2>&1; then
    echo "No job within ${idle_timeout_seconds} seconds; terminating."
    terminate
  fi
) &
wait "$${RUNNER_PID}" || true
