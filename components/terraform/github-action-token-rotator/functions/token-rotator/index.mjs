// GitHub Actions runner registration-token rotator (Cloud Posse
// aws-github-action-token-rotator's job, without its third-party package).
//
// On each run: read the GitHub App's private key from SSM, sign an App JWT
// (RS256, node:crypto), exchange it for an installation token, request a
// runner registration token for GITHUB_SCOPE ("owner/repo" for a repository,
// "org" for an organization) and write it to the SSM SecureString
// TOKEN_PARAMETER. A registration token lasts an hour; the schedule runs more
// often than that. No dependency outside the Node.js 22 runtime, which ships
// the AWS SDK v3.
import { createSign } from "node:crypto";

const API = "https://api.github.com";

function base64url(input) {
  return Buffer.from(input).toString("base64url");
}

// The key may be stored as PEM or as base64 of the PEM (Cloud Posse's and
// philips-labs' convention).
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

export function registrationTokenUrl(scope) {
  return scope.includes("/")
    ? `${API}/repos/${scope}/actions/runners/registration-token`
    : `${API}/orgs/${scope}/actions/runners/registration-token`;
}

async function post(url, authorization) {
  const response = await fetch(url, {
    method: "POST",
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: authorization,
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "tf-atmos-github-action-token-rotator",
    },
  });
  if (!response.ok) {
    // The body names the failure (bad installation, missing permission); it
    // carries no secret.
    throw new Error(`POST ${url}: ${response.status} ${await response.text()}`);
  }
  return response.json();
}

export const handler = async () => {
  // Imported here, not at the top, so the pure helpers above load (and are
  // tested) without the SDK, which only the Lambda runtime provides.
  const { SSMClient, GetParameterCommand, PutParameterCommand } = await import("@aws-sdk/client-ssm");
  const ssm = new SSMClient({});
  const env = process.env;
  const key = await ssm.send(new GetParameterCommand({ Name: env.PRIVATE_KEY_PARAMETER, WithDecryption: true }));
  const jwt = appJwt(env.GITHUB_APP_ID, pemFrom(key.Parameter.Value));

  const installation = await post(
    `${API}/app/installations/${env.GITHUB_INSTALLATION_ID}/access_tokens`,
    `Bearer ${jwt}`,
  );
  const registration = await post(registrationTokenUrl(env.GITHUB_SCOPE), `Bearer ${installation.token}`);

  await ssm.send(
    new PutParameterCommand({
      Name: env.TOKEN_PARAMETER,
      Value: registration.token,
      Type: "SecureString",
      KeyId: env.TOKEN_KMS_KEY_ID,
      Overwrite: true,
    }),
  );
  // Never log a token; the expiry is enough to follow the rotation.
  console.log(`Rotated the runner registration token for ${env.GITHUB_SCOPE}; it expires at ${registration.expires_at}`);
  return { expires_at: registration.expires_at };
};
