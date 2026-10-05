// node --test components/terraform/github-runners/functions/jit/
// Not packaged: main.tf's archive_file excludes this file.
import { test } from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync, createVerify } from "node:crypto";
import { appJwt, pemFrom, tokenScope, runnersPath, jitRequest, jitParameterName, onLaunch, onTerminate } from "./index.mjs";

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
};
const DETAIL = {
  EC2InstanceId: "i-0123456789abcdef0",
  AutoScalingGroupName: "dev-github-runners",
  LifecycleHookName: "jit",
  LifecycleActionToken: "token-1",
};

function fakes({ jitStatus = 201, runners = [], terminateFails = false } = {}) {
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
      },
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
    "complete",
  ]);
  assert.equal(calls[0].name, ENV.APP_KEY_PARAMETER);
  assert.deepEqual(calls[1].body, { repositories: ["tf-atmos"], permissions: { administration: "write" } });
  assert.match(calls[1].auth, /^Bearer [\w-]+\.[\w-]+\.[\w-]+$/);
  assert.deepEqual(calls[2].body, jitRequest("i-0123456789abcdef0", ["fnx-ue1-dev"], 1));
  assert.equal(calls[2].auth, "Bearer ghs_installation");
  assert.equal(calls[3].auth, "Bearer ghs_installation");
  assert.deepEqual(calls[4].input, {
    Name: "/github/runners/jit/i-0123456789abcdef0",
    Value: "ENCODED",
    Type: "SecureString",
    Tier: "Intelligent-Tiering",
    KeyId: ENV.JIT_KMS_KEY_ID,
    Tags: [{ Key: "RunnerInstanceArn", Value: "arn:aws:ec2:us-east-1:123456789012:instance/i-0123456789abcdef0" }],
  });
  assert.equal(calls[5].result, "CONTINUE");
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
    "getParameter",
    "POST /app/installations/7654321/access_tokens",
    "GET /repos/hemzaz/tf-atmos/actions/runners?name=i-0123456789abcdef0",
    "DELETE /repos/hemzaz/tf-atmos/actions/runners/7",
    "DELETE /installation/token",
  ]);
  assert.equal(calls[0].name, "/github/runners/jit/i-0123456789abcdef0");
});
