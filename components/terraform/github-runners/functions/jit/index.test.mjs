// node --test components/terraform/github-runners/functions/jit/
// Not packaged: main.tf's archive_file excludes this file.
import { test } from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync, createVerify } from "node:crypto";
import { appJwt, pemFrom, tokenScope, runnersPath, jitRequest, jitParameterName, leaseParameterName, leaseInstanceId, onLaunch, onLeaseDeleted, onTerminate } from "./index.mjs";

const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const pem = privateKey.export({ type: "pkcs1", format: "pem" });

test("the App JWT is RS256, signed by the key, issued by the App, valid under 10 minutes", () => {
  const jwt = appJwt(123456, pem, 1_700_000_000);
  const [header, payload, signature] = jwt.split(".");
  assert.deepEqual(JSON.parse(Buffer.from(header, "base64url")), { alg: "RS256", typ: "JWT" });
  const claims = JSON.parse(Buffer.from(payload, "base64url"));
  assert.equal(claims.iss, "123456");
  assert.ok(claims.exp - claims.iat <= 600);
  const verifier = createVerify("RSA-SHA256");
  verifier.update(`${header}.${payload}`);
  assert.ok(verifier.verify(publicKey, Buffer.from(signature, "base64url")));
});

test("the private key is accepted as PEM or as base64 of the PEM", () => {
  assert.equal(pemFrom(pem), pem.trim());
  assert.equal(pemFrom(Buffer.from(pem).toString("base64")), pem);
});

test("the installation token is scoped to one repository and the one permission", () => {
  assert.deepEqual(tokenScope("hemzaz/tf-atmos"), { repositories: ["tf-atmos"], permissions: { administration: "write" } });
  assert.deepEqual(tokenScope("my-org"), { permissions: { organization_self_hosted_runners: "write" } });
});

test("a repository scope uses the repository's runner API, an organization scope the organization's", () => {
  assert.equal(runnersPath("hemzaz/tf-atmos"), "/repos/hemzaz/tf-atmos/actions/runners");
  assert.equal(runnersPath("my-org"), "/orgs/my-org/actions/runners");
});

test("the JIT request names the runner after the instance and lists every label", () => {
  assert.deepEqual(jitRequest("i-0123456789abcdef0", ["fnx-ue1-dev"], 1), {
    name: "i-0123456789abcdef0",
    runner_group_id: 1,
    labels: ["self-hosted", "linux", "x64", "fnx-ue1-dev"],
    work_folder: "_work",
  });
});

test("the JIT parameter is <prefix>/<instance id>", () => {
  assert.equal(jitParameterName("/github/runners/jit/", "i-1"), "/github/runners/jit/i-1");
  assert.equal(jitParameterName("/github/runners/jit", "i-1"), "/github/runners/jit/i-1");
});

// The launch and terminate flows against recorded fakes of GitHub and AWS.
const ENV = {
  GITHUB_APP_ID: "123456",
  GITHUB_INSTALLATION_ID: "7654321",
  GITHUB_SCOPE: "hemzaz/tf-atmos",
  APP_KEY_PARAMETER: "/github/runners/github-runners/app-private-key",
  RUNNER_LABELS: JSON.stringify(["fnx-ue1-dev"]),
  RUNNER_GROUP_ID: "1",
  JIT_PARAMETER_PREFIX: "/github/runners/jit",
  JIT_KMS_KEY_ID: "arn:aws:kms:us-east-1:123456789012:key/main",
  PARTITION: "aws",
  AWS_REGION: "us-east-1",
  ACCOUNT_ID: "123456789012",
  AUTOSCALING_GROUP_NAME: "dev-github-runners",
};
const DETAIL = {
  EC2InstanceId: "i-0123456789abcdef0",
  AutoScalingGroupName: "dev-github-runners",
  LifecycleHookName: "jit",
  LifecycleActionToken: "token-1",
};

function fakes({ jitStatus = 201, runners = [], terminateFails = false, instance = { group: "dev-github-runners", state: "InService" }, terminateError = null } = {}) {
  const calls = [];
  const reply = (status, body) => ({ ok: status < 300, status, json: async () => body, text: async () => JSON.stringify(body) });
  return {
    calls,
    deps: {
      fetch: async (url, init) => {
        calls.push({ kind: "github", method: init.method, path: url.replace("https://api.github.com", ""), auth: init.headers.Authorization, body: init.body && JSON.parse(init.body) });
        if (url.endsWith("/access_tokens")) return reply(201, { token: "ghs_installation" });
        if (url.endsWith("/generate-jitconfig")) return reply(jitStatus, jitStatus < 300 ? { runner: { id: 42 }, encoded_jit_config: "ENCODED" } : { message: "denied" });
        if (url.endsWith("/installation/token")) return reply(204, null);
        if (init.method === "GET") return reply(200, { runners });
        return reply(204, null);
      },
      getParameter: async (name) => { calls.push({ kind: "getParameter", name }); return pem; },
      putParameter: async (input) => { calls.push({ kind: "putParameter", input }); },
      deleteParameter: async (name) => { calls.push({ kind: "deleteParameter", name }); },
      terminateInstance: async (instanceId) => {
        calls.push({ kind: "terminate", instanceId });
        if (terminateFails) throw new Error("ScalingActivityInProgress");
        if (terminateError) throw terminateError;
      },
      describeInstance: async (instanceId) => { calls.push({ kind: "describe", instanceId }); return instance; },
      completeLifecycle: async (detail, result) => { calls.push({ kind: "complete", result }); },
    },
  };
}

const summary = (calls) => calls.map((c) => (c.kind === "github" ? `${c.method} ${c.path}` : c.kind));

test("launch: scoped token, JIT config for the instance, tagged parameter, token revoked, launch continues", async () => {
  const { calls, deps } = fakes();
  await onLaunch(DETAIL, ENV, deps);
  assert.deepEqual(summary(calls), [
    "getParameter",
    "POST /app/installations/7654321/access_tokens",
    "POST /repos/hemzaz/tf-atmos/actions/runners/generate-jitconfig",
    "DELETE /installation/token",
    "putParameter",
    "putParameter",
    "complete",
  ]);
  assert.equal(calls[0].name, ENV.APP_KEY_PARAMETER);
  assert.deepEqual(calls[1].body, { repositories: ["tf-atmos"], permissions: { administration: "write" } });
  assert.match(calls[1].auth, /^Bearer [\w-]+\.[\w-]+\.[\w-]+$/);
  assert.deepEqual(calls[2].body, jitRequest("i-0123456789abcdef0", ["fnx-ue1-dev"], 1));
  assert.equal(calls[2].auth, "Bearer ghs_installation");
  assert.equal(calls[3].auth, "Bearer ghs_installation");
  // The lease first, so it exists whenever the runner runs.
  assert.deepEqual(calls[4].input, {
    Name: "/github/runners/jit/lease/i-0123456789abcdef0",
    Value: "arn:aws:ec2:us-east-1:123456789012:instance/i-0123456789abcdef0",
    Type: "String",
    Tier: "Standard",
    Tags: [{ Key: "RunnerInstanceArn", Value: "arn:aws:ec2:us-east-1:123456789012:instance/i-0123456789abcdef0" }],
  });
  assert.deepEqual(calls[5].input, {
    Name: "/github/runners/jit/i-0123456789abcdef0",
    Value: "ENCODED",
    Type: "SecureString",
    Tier: "Intelligent-Tiering",
    KeyId: ENV.JIT_KMS_KEY_ID,
    Tags: [{ Key: "RunnerInstanceArn", Value: "arn:aws:ec2:us-east-1:123456789012:instance/i-0123456789abcdef0" }],
  });
  assert.equal(calls[6].result, "CONTINUE");
});

test("launch: a GitHub failure revokes the token, terminates the instance (lowering capacity), then abandons", async () => {
  const { calls, deps } = fakes({ jitStatus: 403 });
  await assert.rejects(onLaunch(DETAIL, ENV, deps), /generate-jitconfig: 403/);
  const kinds = summary(calls);
  assert.ok(kinds.includes("DELETE /installation/token"));
  assert.ok(!kinds.includes("putParameter"));
  assert.deepEqual(kinds.slice(-2), ["terminate", "complete"]);
  assert.equal(calls.at(-2).instanceId, "i-0123456789abcdef0");
  assert.equal(calls.at(-1).result, "ABANDON");
});

test("launch: if Auto Scaling refuses the terminate, the launch continues so the instance ends itself", async () => {
  const { calls, deps } = fakes({ jitStatus: 403, terminateFails: true });
  await assert.rejects(onLaunch(DETAIL, ENV, deps), /generate-jitconfig: 403/);
  assert.deepEqual(summary(calls).slice(-2), ["terminate", "complete"]);
  assert.equal(calls.at(-1).result, "CONTINUE");
  assert.ok(!summary(calls).includes("putParameter"));
});

test("terminate: deletes the unread parameter and the instance's leftover runner only", async () => {
  const { calls, deps } = fakes({ runners: [{ id: 7, name: "i-0123456789abcdef0" }, { id: 8, name: "i-other" }] });
  await onTerminate(DETAIL, ENV, deps);
  assert.deepEqual(summary(calls), [
    "deleteParameter",
    "deleteParameter",
    "getParameter",
    "POST /app/installations/7654321/access_tokens",
    "GET /repos/hemzaz/tf-atmos/actions/runners?name=i-0123456789abcdef0",
    "DELETE /repos/hemzaz/tf-atmos/actions/runners/7",
    "DELETE /installation/token",
  ]);
  assert.equal(calls[0].name, "/github/runners/jit/i-0123456789abcdef0");
  assert.equal(calls[1].name, "/github/runners/jit/lease/i-0123456789abcdef0");
});

test("the lease is <prefix>/lease/<instance id>, and only such a name yields an instance id", () => {
  assert.equal(leaseParameterName("/github/runners/x/jit/", "i-1"), "/github/runners/x/jit/lease/i-1");
  assert.equal(leaseInstanceId("/github/runners/x/jit", "/github/runners/x/jit/lease/i-0123abcd"), "i-0123abcd");
  for (const name of [
    "/github/runners/x/jit/i-0123abcd",
    "/github/runners/x/jit/lease/i-0123abcd/extra",
    "/github/runners/x/jit/lease/i-XYZ",
    "/github/runners/x/jit/lease/",
    "/github/runners/other/jit/lease/i-0123abcd",
    undefined,
  ]) {
    assert.equal(leaseInstanceId("/github/runners/x/jit", name), null, String(name));
  }
});

const LEASE = { operation: "Delete", name: "/github/runners/jit/lease/i-0123456789abcdef0" };

test("lease deleted: the InService runner of this group is ended, lowering capacity", async () => {
  const { calls, deps } = fakes();
  await onLeaseDeleted(LEASE, ENV, deps);
  assert.deepEqual(summary(calls), ["describe", "terminate"]);
  assert.equal(calls[1].instanceId, "i-0123456789abcdef0");
});

test("lease deleted: an invalid instance id is rejected before any call", async () => {
  const { calls, deps } = fakes();
  await assert.rejects(onLeaseDeleted({ operation: "Delete", name: "/github/runners/jit/lease/i-0;rm" }, ENV, deps), /not a runner lease/);
  await assert.rejects(onLeaseDeleted({ operation: "Delete", name: "/github/runners/jit/i-0123456789abcdef0" }, ENV, deps), /not a runner lease/);
  assert.deepEqual(calls, []);
});

test("lease deleted: an instance already leaving, gone, or in another group is left alone", async () => {
  for (const instance of [null, { group: "dev-github-runners", state: "Terminating" }, { group: "other-pool", state: "InService" }]) {
    const { calls, deps } = fakes({ instance });
    await onLeaseDeleted(LEASE, ENV, deps);
    assert.deepEqual(summary(calls), ["describe"], JSON.stringify(instance));
  }
});

test("lease deleted: an instance Auto Scaling no longer finds is success; other errors fail", async () => {
  const notFound = Object.assign(new Error("Instance Id not found - No managed instance found for instance ID i-0123456789abcdef0"), { name: "ValidationError" });
  await onLeaseDeleted(LEASE, ENV, fakes({ terminateError: notFound }).deps);
  const denied = Object.assign(new Error("not authorized"), { name: "AccessDenied" });
  await assert.rejects(onLeaseDeleted(LEASE, ENV, fakes({ terminateError: denied }).deps), /not authorized/);
});
