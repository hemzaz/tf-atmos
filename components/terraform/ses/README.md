# ses

One SES domain identity per instance, verified with Easy DKIM on the SES v2 API. Modelled on Cloud
Posse `aws-ses` as plain resources, without its SMTP IAM user (grant `ses:Send*` to roles instead)
or MAIL FROM subdomain.

## Wiring

- No instance in the fnx stacks. `microservices/ses` in the `microservices-platform` template serves
  the welcome-email Lambda; `ses/defaults` is the abstract base.
- `zone_id` takes the domain's public zone (for example a dns instance's `.zone_ids.<key>`); the
  three DKIM CNAMEs are written there. Null writes nothing: publish `dkim_records` yourself.
- Senders scope their IAM policy to `.email_identity_arn`.

## Notes

- A new account's SES is in the sandbox (verified recipients only, 200 messages a day). Request
  production access by hand, once per account and region.
- The zone must be public and delegated, or the identity stays `PENDING`. `verified_for_sending_status`
  and `dkim_status` update on a later refresh (minutes to 72 hours).
