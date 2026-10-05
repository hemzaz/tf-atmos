// node --test components/terraform/github-action-token-rotator/functions/token-rotator/
// Not packaged: main.tf's archive_file excludes this file.
import { test } from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync, createVerify } from "node:crypto";
import { appJwt, pemFrom, registrationTokenUrl } from "./index.mjs";

const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const pem = privateKey.export({ type: "pkcs1", format: "pem" });

test("the App JWT is RS256, signed by the key, issued by the App, valid under 10 minutes", () => {
  const jwt = appJwt(123456, pem, 1_700_000_000);
  const [header, payload, signature] = jwt.split(".");
  assert.deepEqual(JSON.parse(Buffer.from(header, "base64url")), { alg: "RS256", typ: "JWT" });
  const claims = JSON.parse(Buffer.from(payload, "base64url"));
  assert.equal(claims.iss, "123456");
  assert.equal(claims.iat, 1_700_000_000 - 60);
  assert.ok(claims.exp - claims.iat <= 600);
  const verifier = createVerify("RSA-SHA256");
  verifier.update(`${header}.${payload}`);
  assert.ok(verifier.verify(publicKey, Buffer.from(signature, "base64url")));
});

test("the private key is accepted as PEM or as base64 of the PEM", () => {
  assert.equal(pemFrom(pem), pem.trim());
  assert.equal(pemFrom(Buffer.from(pem).toString("base64")), pem);
});

test("a repository scope asks the repository, an organization scope the organization", () => {
  assert.equal(registrationTokenUrl("hemzaz/tf-atmos"), "https://api.github.com/repos/hemzaz/tf-atmos/actions/runners/registration-token");
  assert.equal(registrationTokenUrl("my-org"), "https://api.github.com/orgs/my-org/actions/runners/registration-token");
});
