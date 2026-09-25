# ses

One SES domain identity per instance, verified with Easy DKIM, modelled on
Cloud Posse's
[aws-ses](https://github.com/cloudposse-terraform-components/aws-ses)
component (which wraps `cloudposse/ses`). Written as plain resources on the
SES v2 API (`aws_sesv2_email_identity`), like the other root components.

## Deployed instances

None in the three fnx stacks. `stacks/catalog/templates/microservices-platform.yaml`
defines `microservices/ses` for the welcome-email Lambda. The abstract base is
`ses/defaults` (`stacks/catalog/ses/defaults.yaml`).

## Inputs / outputs

| Key | Notes |
|---|---|
| `region`, `tags`, `domain` (required) | `tags` must include a non-empty `Environment`; `domain` is a lowercase DNS name (Cloud Posse's `domain_template`, rendered) |
| `zone_id` (null) | the domain's public Route 53 zone, usually `!terraform.state <dns instance> .zone_ids.<key>`; the three DKIM CNAME records are written there. Null writes nothing: publish `dkim_records` yourself |
| `ses_verify_dkim` (true), `dkim_signing_key_length` (`RSA_2048_BIT`), `dkim_record_ttl` (1800) | Cloud Posse's `ses_verify_dkim`; the key length and TTL are validated |
| `enabled` (true) | false creates nothing |
| out: `email_identity`, `email_identity_arn` | the domain and the identity ARN, for `ses:SendEmail`/`ses:SendRawEmail` policies |
| out: `verified_for_sending_status`, `dkim_status` | verification state: false/`PENDING` until SES sees the DKIM records (minutes to 72 hours); read them after a later refresh |
| out: `dkim_records` | the three CNAME records, name => value |

## Dependencies / gotchas

- **Sandbox.** A new account's SES is in the sandbox: it only sends to
  verified addresses, 200 messages a day. Production access is an
  account-level request (SES console, "Request production access", or
  `aws sesv2 put-account-details`), made by hand once per account and region;
  Terraform does not do it.
- The zone must be the domain's **public** zone and actually delegated, or
  SES never sees the records and the identity stays `PENDING`.
- Sending also needs an IAM policy on the sender (for example the lambda
  component's `custom_policy`), scoped to `email_identity_arn` and, ideally, a
  `ses:FromAddress` condition.

## Differences from Cloud Posse

- SES v2 (`aws_sesv2_email_identity`, Easy DKIM) instead of the v1
  `aws_ses_domain_identity` + `aws_ses_domain_dkim` pair; SES v2 verifies the
  domain through DKIM, so there is no `_amazonses` TXT record
  (`ses_verify_domain`).
- No SMTP IAM user or group (`ses_group_*`, `ses_user_enabled`): this repo
  does not create long-lived access keys. Grant `ses:Send*` to roles instead.
- No `custom_from_subdomain` (MAIL FROM) yet.
- Added: `zone_id` as an input (Cloud Posse reads `dns-delegated` remote
  state), `enabled`, validations, and the verification outputs.

## Tests

`tests/ses.tftest.hcl` runs against a mock provider (no credentials):

```
cd components/terraform/ses && terraform init -backend=false && terraform test
```
