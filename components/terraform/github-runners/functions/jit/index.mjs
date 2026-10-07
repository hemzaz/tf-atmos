// Just-in-time runner configuration for github-runners.
//
// Launch: the Auto Scaling group's launch lifecycle hook (EventBridge "EC2
// Instance-launch Lifecycle Action") holds a new instance in Pending:Wait.
// This function signs a GitHub App JWT with the App's private key (SSM, on a
// key only this function may decrypt), takes an installation token scoped to
// the one repository (or organization) and the one permission the runner API
// needs, asks GitHub for a JIT configuration for a runner named after the
// instance, revokes the token, writes the configuration to an SSM
// SecureString tagged with the instance's ARN (the instance may read and
// delete only that parameter), and lets the launch continue. A JIT
// configuration registers one ephemeral runner once: a copy taken after the
// runner started is useless, and no reusable registration credential exists
// anywhere. Any failure terminates the instance, lowering desired capacity, so
// a lasting failure cannot loop launches.
//
// Launch also writes the instance's lease, <prefix>/lease/<instance id>
// (tagged with its ARN, before the JIT configuration, so it exists whenever
// the runner runs). A runner done with its job deletes its own lease (it may
// delete only parameters tagged with its own ARN) and has no Auto Scaling
// permission at all.
//
// Lease deleted ("Parameter Store Change", Delete, under <prefix>/lease/):
// end that instance, lowering desired capacity. Only an InService instance of
// this pool: one already leaving (or gone) is left alone, so this never
// lowers capacity twice. This replaces Cloud Posse's and philips-labs' runner
// self-termination (TerminateInstanceInAutoScalingGroup on the instance
// role), which IAM cannot scope to the caller's own instance.
//
// Terminate ("EC2 Instance Terminate Successful"): delete the instance's JIT
// parameter, if it never read it, its lease, and its runner registration, if
// GitHub still has one (a runner that never took a job).
//
// Node.js 22 runtime only: node:crypto for RS256, fetch, and the AWS SDK v3
// the runtime ships. The AWS and HTTP calls come in as `deps`, so the flow is
// tested without either (index.test.mjs).
import { createSign } from "node:crypto";

const API = "https://api.github.com";

function base64url(input) {
  return Buffer.from(input).toString("base64url");
}

// The key may be stored as PEM or as base64 of the PEM.
export function pemFrom(value) {
  const text = value.trim();
  return text.startsWith("-----BEGIN") ? text : Buffer.from(text, "base64").toString("utf8");
}

export function appJwt(appId, privateKeyPem, nowSeconds = Math.floor(Date.now() / 1000)) {
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  // iat 60 s back for clock drift; GitHub allows at most 10 minutes.
  const payload = base64url(JSON.stringify({ iat: nowSeconds - 60, exp: nowSeconds + 540, iss: String(appId) }));
  const signer = createSign("RSA-SHA256");
  signer.update(`${header}.${payload}`);
  return `${header}.${payload}.${signer.sign(privateKeyPem).toString("base64url")}`;
}

// The installation token request body: only this scope's repository and the
// one permission its runner API needs (a repository runner needs
// Administration; an organization runner, Self-hosted runners).
export function tokenScope(scope) {
  if (scope.includes("/")) {
    return { repositories: [scope.split("/")[1]], permissions: { administration: "write" } };
  }
  return { permissions: { organization_self_hosted_runners: "write" } };
}

export function runnersPath(scope) {
  return scope.includes("/") ? `/repos/${scope}/actions/runners` : `/orgs/${scope}/actions/runners`;
}

// generate-jitconfig's body. JIT runners are always ephemeral. GitHub adds no
// default labels to a JIT runner, so self-hosted/linux/x64 are listed.
export function jitRequest(instanceId, labels, runnerGroupId) {
  return {
    name: instanceId,
    runner_group_id: runnerGroupId,
    labels: ["self-hosted", "linux", "x64", ...labels],
    work_folder: "_work",
  };
}

export function jitParameterName(prefix, instanceId) {
  return `${prefix.replace(/\/+$/, "")}/${instanceId}`;
}

export function leaseParameterName(prefix, instanceId) {
  return `${prefix.replace(/\/+$/, "")}/lease/${instanceId}`;
}

// The instance id a deleted lease names, or null for any other parameter.
export function leaseInstanceId(prefix, parameterName) {
  const leases = `${prefix.replace(/\/+$/, "")}/lease/`;
  if (typeof parameterName !== "string" || !parameterName.startsWith(leases)) return null;
  const instanceId = parameterName.slice(leases.length);
  return /^i-[0-9a-f]+$/.test(instanceId) ? instanceId : null;
}

function instanceArn(env, instanceId) {
  return `arn:${env.PARTITION}:ec2:${env.AWS_REGION}:${env.ACCOUNT_ID}:instance/${instanceId}`;
}

async function github(deps, method, path, token, body) {
  const response = await deps.fetch(`${API}${path}`, {
    method,
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${token}`,
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "tf-atmos-github-runners",
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!response.ok) {
    // GitHub's error body names the failure (scope, permission); no secret in it.
    throw new Error(`${method} ${path}: ${response.status} ${await response.text()}`);
  }
  return response.status === 204 ? null : response.json();
}

// Runs fn with a scoped installation token, then revokes the token.
async function withInstallationToken(deps, env, fn) {
  const jwt = appJwt(env.GITHUB_APP_ID, pemFrom(await deps.getParameter(env.APP_KEY_PARAMETER)));
  const { token } = await github(deps, "POST", `/app/installations/${env.GITHUB_INSTALLATION_ID}/access_tokens`, jwt, tokenScope(env.GITHUB_SCOPE));
  try {
    return await fn(token);
  } finally {
    await github(deps, "DELETE", "/installation/token", token).catch((error) => console.error(`token revocation: ${error.message}`));
  }
}

export async function onLaunch(detail, env, deps) {
  const instanceId = detail.EC2InstanceId;
  try {
    const jit = await withInstallationToken(deps, env, (token) =>
      github(deps, "POST", `${runnersPath(env.GITHUB_SCOPE)}/generate-jitconfig`, token,
        jitRequest(instanceId, JSON.parse(env.RUNNER_LABELS), Number(env.RUNNER_GROUP_ID))));
    // The lease first: the runner deletes it when done, which ends it.
    await deps.putParameter({
      Name: leaseParameterName(env.JIT_PARAMETER_PREFIX, instanceId),
      Value: instanceArn(env, instanceId),
      Type: "String",
      Tier: "Standard",
      Tags: [{ Key: "RunnerInstanceArn", Value: instanceArn(env, instanceId) }],
    });
    await deps.putParameter({
      Name: jitParameterName(env.JIT_PARAMETER_PREFIX, instanceId),
      Value: jit.encoded_jit_config,
      Type: "SecureString",
      // An encoded JIT configuration is about 4.3-4.6 KB, over Standard's 4 KB:
      // Intelligent-Tiering stores it as Advanced only when it must.
      Tier: "Intelligent-Tiering",
      KeyId: env.JIT_KMS_KEY_ID,
      Tags: [{ Key: "RunnerInstanceArn", Value: instanceArn(env, instanceId) }],
    });
    await deps.completeLifecycle(detail, "CONTINUE");
    console.log(`JIT runner ${jit.runner.id} configured for ${instanceId}`);
  } catch (error) {
    // End the instance with a lower desired capacity: an abandoned launch
    // alone is replaced by the group, and a lasting failure (a revoked App, a
    // missing key) would loop launches. If Auto Scaling refuses to terminate an
    // instance still in Pending:Wait (e.g. ScalingActivityInProgress), let the
    // launch CONTINUE instead: the instance finds no JIT configuration and its
    // own EXIT trap terminates it, decrementing, from InService.
    let terminated = true;
    await deps.terminateInstance(instanceId).catch((e) => {
      terminated = false;
      console.error(`terminate ${instanceId}: ${e.message}; continuing the launch so the instance ends itself`);
    });
    await deps.completeLifecycle(detail, terminated ? "ABANDON" : "CONTINUE").catch(() => {});
    throw error;
  }
}

export async function onLeaseDeleted(detail, env, deps) {
  const instanceId = leaseInstanceId(env.JIT_PARAMETER_PREFIX, detail.name);
  if (instanceId === null) throw new Error(`not a runner lease: ${JSON.stringify(detail.name)}`);
  const instance = await deps.describeInstance(instanceId);
  if (instance?.group !== env.AUTOSCALING_GROUP_NAME || instance.state !== "InService") {
    console.log(`${instanceId} is not an InService runner of ${env.AUTOSCALING_GROUP_NAME} (${JSON.stringify(instance)}): nothing to end`);
    return;
  }
  try {
    await deps.terminateInstance(instanceId);
    console.log(`Ended ${instanceId} (its lease was deleted), lowering desired capacity`);
  } catch (error) {
    if (error.name === "ValidationError" && /not found/i.test(error.message)) return;
    throw error;
  }
}

export async function onTerminate(detail, env, deps) {
  const instanceId = detail.EC2InstanceId;
  await deps.deleteParameter(jitParameterName(env.JIT_PARAMETER_PREFIX, instanceId));
  await deps.deleteParameter(leaseParameterName(env.JIT_PARAMETER_PREFIX, instanceId));
  await withInstallationToken(deps, env, async (token) => {
    const found = await github(deps, "GET", `${runnersPath(env.GITHUB_SCOPE)}?name=${encodeURIComponent(instanceId)}`, token);
    for (const runner of found.runners ?? []) {
      if (runner.name === instanceId) {
        await github(deps, "DELETE", `${runnersPath(env.GITHUB_SCOPE)}/${runner.id}`, token);
        console.log(`Removed runner ${runner.id} (${instanceId})`);
      }
    }
  });
}

async function awsDeps() {
  const { SSMClient, GetParameterCommand, PutParameterCommand, DeleteParameterCommand } = await import("@aws-sdk/client-ssm");
  const { AutoScalingClient, CompleteLifecycleActionCommand, DescribeAutoScalingInstancesCommand, TerminateInstanceInAutoScalingGroupCommand } = await import("@aws-sdk/client-auto-scaling");
  const ssm = new SSMClient({});
  const autoscaling = new AutoScalingClient({});
  return {
    fetch,
    getParameter: async (name) =>
      (await ssm.send(new GetParameterCommand({ Name: name, WithDecryption: true }))).Parameter.Value,
    putParameter: (input) => ssm.send(new PutParameterCommand(input)),
    deleteParameter: (name) =>
      ssm.send(new DeleteParameterCommand({ Name: name })).catch((error) => {
        if (error.name !== "ParameterNotFound") throw error;
      }),
    // The instance's group and lifecycle state, or null when it is in none.
    describeInstance: async (instanceId) => {
      const found = (await autoscaling.send(new DescribeAutoScalingInstancesCommand({ InstanceIds: [instanceId] })))
        .AutoScalingInstances?.[0];
      return found ? { group: found.AutoScalingGroupName, state: found.LifecycleState } : null;
    },
    terminateInstance: (instanceId) =>
      autoscaling.send(new TerminateInstanceInAutoScalingGroupCommand({ InstanceId: instanceId, ShouldDecrementDesiredCapacity: true })),
    completeLifecycle: (detail, result) =>
      autoscaling.send(new CompleteLifecycleActionCommand({
        AutoScalingGroupName: detail.AutoScalingGroupName,
        LifecycleHookName: detail.LifecycleHookName,
        LifecycleActionToken: detail.LifecycleActionToken,
        InstanceId: detail.EC2InstanceId,
        LifecycleActionResult: result,
      })),
  };
}

export const handler = async (event) => {
  const deps = await awsDeps();
  if (event["detail-type"] === "EC2 Instance-launch Lifecycle Action") return onLaunch(event.detail, process.env, deps);
  if (event["detail-type"] === "EC2 Instance Terminate Successful") return onTerminate(event.detail, process.env, deps);
  if (event["detail-type"] === "Parameter Store Change") return onLeaseDeleted(event.detail, process.env, deps);
  throw new Error(`unexpected event ${event["detail-type"]}`);
};
