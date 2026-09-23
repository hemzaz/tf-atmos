# ec2

Creates AWS EC2 instances from a map (`var.instances`), each with a dedicated
security group, an IAM role + instance profile (SSM policy attached by default),
and an optional per-instance or global SSH key pair whose private key is stored in
Secrets Manager. IMDSv2 is enforced on every instance. `launch-template.tf` can also
build per-instance `aws_launch_template` resources (default `true`), but instances
are only launched from them when `create_instances_from_templates = true` (default
`false`) — otherwise standalone `aws_instance` resources are what's actually created.

## Deployed instances

- `ec2/bastion` — dev, staging, prod
- `ec2/app-server` — dev, staging only (not deployed in prod)
- `ec2` (abstract catalog entry, not a real instance) — all 3 stacks

## Inputs / Outputs

| Required inputs | Behavior-changing | Outputs |
|---|---|---|
| `vpc_id`, `subnet_ids`, `instances` (each needs `instance_type`), `tags.Environment` | `create_ssh_keys`, `store_ssh_keys_in_secrets_manager`, `global_key_name` | Maps keyed by instance name: `instance_ids`, `instance_arns`, `instance_public_ips`, `instance_private_ips`, `security_group_ids`, `iam_role_arns`, `iam_role_names`, `iam_instance_profile_arns`, `iam_instance_profile_names`, `generated_key_names`, `ssh_key_secret_arns` (sensitive). Scalars: `global_key_name`, `global_key_secret_arn` (sensitive), and, for the component's only instance, named as in Cloud Posse's ec2-instance/ec2-bastion-server, `ssh_key_pair` and `security_group_id` |

`ssh_key_pair` is the key the instance actually launched with (its own `key_name`, its
generated key, the global key, or `default_key_name`), not `global_key_name`. The two
scalar outputs use `one()`: null with no enabled instance, and the plan fails with more
than one, so they never pick one instance out of several.

`vpc_endpoint_prefix_list_ids` is required (validation fails if empty) — default egress uses it
instead of `0.0.0.0/0`. An instance with `detailed_monitoring` unset follows `enable_detailed_monitoring` (default true).

## Dependencies & gotchas

- Depends on `vpc/main` (all instances); `ec2/app-server` also depends on
  `ec2/bastion`; `ec2/bastion` also depends on `kms/main`.
- `ec2/app-server` reads `!terraform.state ec2/bastion .ssh_key_pair` as its
  `key_name` (dev, staging) and `.security_group_id` as an item of an ingress
  rule's `security_groups` list (staging).
- `tags` map must contain a non-empty `Environment` key or plan fails validation.

## Usage

```
atmos terraform plan ec2/bastion -s fnx-dev-testenv-01
atmos terraform plan ec2/app-server -s fnx-staging-staging-01
```
