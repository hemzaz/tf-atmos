# glue

One Glue catalog database plus its crawlers per instance, modelled on Cloud
Posse's
[aws-glue-catalog-database](https://github.com/cloudposse-terraform-components/aws-glue-catalog-database)
and
[aws-glue-crawler](https://github.com/cloudposse-terraform-components/aws-glue-crawler)
components (which wrap
[cloudposse/terraform-aws-glue](https://github.com/cloudposse/terraform-aws-glue)'s
`glue-catalog-database` and `glue-crawler` submodules), plus the
`AWSGlueServiceRole` attachment from Cloud Posse's
[aws-glue-iam](https://github.com/cloudposse-terraform-components/aws-glue-iam)
component. Folded into ONE component (database + crawlers + crawler role +
security configuration), unlike Cloud Posse's four separate components, since
an instance of this component is meant to be the whole unit of deployment for
one catalog and everything that populates it - an owner decision for this
repo, not an upstream pattern. Written as plain resources, like this repo's
other short-name root components (`stepfunctions`, `kinesis`, `sns`, `sqs`).

## Deployed instances

`data-pipeline/glue-database` in `stacks/catalog/templates/data-pipeline.yaml`
(a template, not a deployed stack) - the instance name predates this
component and was kept so existing `!terraform.state data-pipeline/glue-database
...` reads elsewhere in the template (firehose, athena, step-functions) did
not need repointing, even though the instance now also creates the three
crawlers that used to be the separate `data-pipeline/glue-crawlers` instance.
The abstract base `glue/defaults` (`stacks/catalog/glue/defaults.yaml`) wires
the key from `kms/main`; the instance sets `name`, `location_uri`,
`create_table_default_permissions` and `crawlers`.

## Inputs / outputs

| Key | Notes |
|---|---|
| `region`, `tags`, `name`, `kms_key_arn` (required) | `tags` must include a non-empty `Environment`. The crawler role, security configuration and each crawler are named `<Environment>-<name>[-<crawler key>]`; the catalog database reuses the same string with hyphens replaced by underscores, since Glue database names allow only lowercase letters, digits and underscores. `kms_key_arn` must be a full KMS key ARN |
| `database_description` (`""`) | Glue catalog database description |
| `location_uri` (`""`) | Default location for tables in the database, e.g. an `s3://` URI |
| `create_table_default_permissions` (`[]`) | List of `{principal = {data_lake_principal_identifier}, permissions}`, one `aws_glue_catalog_database` `create_table_default_permission` block per entry. The data-pipeline instance sets one entry granting `ALL` to `IAM_ALLOWED_PRINCIPALS` (this repo's accounts run under that legacy-grants model, not Lake Formation's fine-grained access control - see "Not implemented" in `main.tf`) |
| `crawlers` (`{}`) | Map of crawlers to create against this instance's own catalog database, keyed by a short suffix. Each entry: `description` (optional), `schedule` (optional, a `cron(...)` expression), `table_prefix` (optional), `configuration` (optional, a map the component `jsonencode()`s into the crawler's `configuration` JSON string), `s3_targets` (required, list of `{path, exclusions (optional, [])}`) and `schema_change_policy` (optional, `{delete_behavior, update_behavior}`). A variable validation requires at least one `s3_targets` entry per crawler and rejects a `schema_change_policy` with values AWS does not accept |
| `enabled` (`true`) | `false` creates nothing, including the crawler role and security configuration |
| out: `database_name`, `database_arn` | Always set when enabled |
| out: `crawler_names`, `crawler_arns` | Maps keyed by the `crawlers` key. Empty maps when `crawlers = {}` |
| out: `role_arn` | ARN of the IAM role every crawler in this instance assumes |
| out: `security_configuration_name` | Name of the KMS-encrypted security configuration every crawler in this instance uses |

## Dependencies / gotchas

- **One role, one security configuration, shared by every crawler in the
  instance.** Cloud Posse's `aws-glue-iam` component creates a role once per
  *instance* of itself and its `aws-glue-crawler` component takes that role's
  ARN as an input, so a caller wiring several crawlers to one role already
  has to compose three components per crawler group. Folding all of it into
  one component (the owner decision this component implements) removes that
  composition: every entry in `crawlers` shares `aws_iam_role.crawler` and
  `aws_glue_security_configuration.this`, matching how the original
  `data-pipeline/glue-crawlers` instance's three crawlers were always meant
  to run under a single `glue_crawler_role_arn` placeholder.
- **The crawler role's S3 grant is derived from `s3_targets`, not a separate
  input.** `s3:ListBucket`/`s3:GetObject` are scoped to exactly the buckets
  every crawler's `s3_targets[*].path` names (parsed out of the `s3://`
  URI, deduplicated across all crawlers) - there is no `target_bucket_arns`
  variable to keep in sync by hand. Add a crawler with a new bucket in its
  `s3_targets` and the role's policy picks it up on the next `apply`, with
  no other change.
- **KMS grants for the crawler role, not a key-policy change.** `kms/main`'s
  key policy delegates to the account root, so (as in this repo's kinesis
  and s3 components) an IAM identity's own policy is sufficient to use the
  key; this component's crawler role gets `kms:Decrypt` (source S3 objects
  under SSE-KMS) plus `kms:Encrypt`/`kms:GenerateDataKey` (the security
  configuration's own CloudWatch Logs/job bookmark/S3 output encryption -
  see [AWS's Glue encryption
  docs](https://docs.aws.amazon.com/glue/latest/dg/set-up-encryption.html)
  for why the role itself, not just the key policy, needs these).
- **PITFALL: no `aws_glue_data_catalog_encryption_settings`.** That resource
  is an account-wide singleton (one per account per region, keyed by
  `catalog_id`, not by database) - deliberately not created here. A second
  instance of this component in the same account/region would collide with
  the first's on apply if it tried to.
- **Lake Formation permissions are out of scope.** Cloud Posse's
  `aws-glue-catalog-database` also grants `aws_lakeformation_permissions` to
  the crawler role, to avoid crawler failures on accounts with Lake
  Formation's fine-grained access control switched on. This repo's accounts
  use `IAM_ALLOWED_PRINCIPALS` (this component's `create_table_default_permissions`
  default in `data-pipeline.yaml`), under which Lake Formation grants
  nothing extra - see the "Not implemented" note in `main.tf` for what
  turning that on later would need.

## Differences from Cloud Posse

- One component (database + crawlers + role + security configuration)
  instead of Cloud Posse's four (`aws-glue-catalog-database`,
  `aws-glue-crawler`, `aws-glue-iam`, plus whatever wires them together) -
  see "One role, one security configuration" above.
- Plain resources instead of `cloudposse/terraform-aws-glue`'s modules; no
  `context.tf`/null-label, names come from `tags.Environment` and
  `default_tags` carries the tags.
- `crawlers` is a map keyed by a short suffix (matching this repo's
  for-each-over-a-map convention for repeatable sub-resources, as in
  `eventbridge`'s `targets` or `kinesis`'s `consumers`), rather than one
  `aws-glue-crawler` component instance per crawler.
- Always creates an `aws_glue_security_configuration` with SSE-KMS/CSE-KMS
  everywhere and wires every crawler to it; Cloud Posse's `aws-glue-crawler`
  takes `security_configuration` as a plain string input and creates none of
  its own, leaving KMS-encrypted crawler output to whatever the caller
  separately provisions.
- No Lake Formation grants (see "Lake Formation permissions are out of
  scope" above).
