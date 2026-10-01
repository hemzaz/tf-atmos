# apigateway-account

The API Gateway account settings for one account and region: an IAM role trusted by
`apigateway.amazonaws.com` with the AWS managed `AmazonAPIGatewayPushToCloudWatchLogs` policy, set
as `aws_api_gateway_account.cloudwatch_role_arn`. Without it, a REST stage with execution or
access logging fails to create ("CloudWatch Logs role ARN must be set in account settings to
enable logging"). Cloud Posse `aws-api-gateway-account-settings`, except that it attaches the
managed policy instead of Cloud Posse's inline `logs:*` grant.

## Wiring

- Instance: `apigateway-account/main` in the three AWS stacks (`components/security.yaml`),
  deployed in the `security` layer, before `services`.
- Used by: `apigateway/main` and `apigateway/data` list it in `dependencies.components` (ordering
  only; they read no output). Templates that create a REST API with logging need it in the stack.

## Notes

- A per-account, per-region singleton: run exactly ONE enabled instance per account and region.
  Two instances overwrite each other's setting on every apply.
- The role name carries the region (`<Environment>-apigateway-cloudwatch-<region>`), so a second
  region's instance does not collide on the global IAM name.
- No `aws:SourceAccount` condition on the trust: neither AWS nor Cloud Posse documents one for this
  role, and API Gateway is not documented to send it.
- `reset_on_delete` is left at the provider default: destroying this only forgets the setting, so
  the account keeps pointing at the (now deleted) role and REST logging updates fail until another
  role is set.
- HTTP APIs do not use this role; their access logs need only the log group.
