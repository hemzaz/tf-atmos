# ec2

Creates **one** EC2 instance per component instance, the model of
`cloudposse-terraform-components/aws-ec2-instance`: the instance, its own security
group, an IAM role and instance profile (SSM policy attached by default) and,
optionally, a generated key pair whose private key is stored in Secrets Manager.
Every resource is `count`-gated, so `enabled = false` plans nothing. IMDSv2 is
required by default and the root volume is encrypted. An instance may also be
keyless (reached through SSM only), as in Cloud Posse's module.

## Deployed instances and names

Every name is `<tags.Environment>-<name>`: the instance's `Name` tag,
`<prefix>-sg`, `<prefix>-role`, `<prefix>-profile`, and a generated key
`<prefix>-ec2-ssh-key` with its secret `ssh-key/<Environment>/<name>`. `name` must
not start with the Environment (validated). **Two instances in one stack must not
share a `name`**: every name above would collide (the component cannot see the
other instances, so this is not validated).

| Stack | `ec2/bastion` | key pair (generated) and secret | `ec2/app-server` | key pair |
|---|---|---|---|---|
| `fnx-dev-testenv-01` | `testenv-01-bastion` | `testenv-01-bastion-ec2-ssh-key`, `ssh-key/testenv-01/bastion` | `testenv-01-app-server` | bastion's |
| `fnx-staging-staging-01` | `staging-01-bastion` | `staging-01-bastion-ec2-ssh-key`, `ssh-key/staging-01/bastion` | `staging-01-app-server` | bastion's |
| `fnx-prod-production` | `production-bastion` | `production-bastion-ec2-ssh-key`, `ssh-key/production/bastion` | none | |

`ec2` is the abstract catalog entry both inherit. The bastions set no
`ssh_key_pair`, so the component generates an ED25519 key per instance and stores
the private key in Secrets Manager, encrypted with kms/main's key
(`ssh_key_secret_kms_key_id`). The `ssh_key_pair` output is that key, and each
app-server launches with its bastion's key through
`!terraform.state ec2/bastion .ssh_key_pair`. App-servers set
`create_ssh_keys: false`, so if that reference ever resolved to null the
app-server would launch keyless rather than silently generate its own key. A
given `ssh_key_pair` must exist: `data.aws_key_pair.existing` fails the plan
otherwise. Apply order: `kms/main`, then `ec2/bastion`, then `ec2/app-server`.

### The generated key

The secret is JSON with `private_key_openssh` (use this one: for ED25519,
`private_key_pem` is PKCS#8, which OpenSSH rejects with "invalid format"),
`private_key_pem`, `public_key_openssh`, `key_name` and the instance's IDs and
addresses. `scripts/certificates/export-ssh-key.sh -r eu-west-2 -s ssh-key/<Environment>/<name> -o <file>`
writes `private_key_openssh` to a new file with mode 600 (it refuses to replace an
existing file without `-f`). Without `-r`/`-p` it uses the ambient AWS
configuration (`AWS_REGION`, `AWS_DEFAULT_REGION`, `AWS_PROFILE`).

**The private key is also in Terraform state.** `tls_private_key` stores it there,
so anyone who can read the component's state in the `fnx-terraform-state` bucket
(which is encrypted and access-controlled) can SSH to the bastion. This is how
master behaved too; an ephemeral key cannot feed `aws_key_pair.public_key`, so
there is no way around it short of generating the key outside Terraform.
A deleted secret stays recoverable for `ssh_key_secret_recovery_window_in_days`
(30).

**Changing the key replaces the instance.** `tls_private_key` has no
`prevent_destroy` (as in Cloud Posse's key-pair modules), so changing
`ssh_key_algorithm` or `ssh_key_rsa_bits` replaces the private key, then the key
pair, then the instance itself, because `key_name` forces a new instance. Read
the plan for `must be replaced` before applying such a change.

## Security group

The instance's own group takes inline rules from `allowed_ingress_rules` and
`allowed_egress_rules` rather than Cloud Posse's `security_group_rules`, whose
module creates one `aws_security_group_rule` per rule. The inline form keeps the
rules in the stack files as they were, readable per instance, and keeps the group
one resource; Cloud Posse's form would add a rule resource per entry and a
`security_group_enabled`/`security_groups` split that no stack needs. Moving to
it later replaces the rules (see docs/OPERATIONS.md, "What `moved` cannot
express").

Policy: only **inbound** traffic is restricted. `allowed_ingress_rules` rejects any
`/0` (`0.0.0.0/0`, `::/0`). Egress is unrestricted by policy: the default (when
`allowed_egress_rules` is null) is Cloud Posse's, all outbound traffic to
`0.0.0.0/0`, and stacks may open egress to `0.0.0.0/0` (the bastions do, on 443).

## Inputs

Cloud Posse names where `terraform-aws-ec2-instance` has the setting.

| Input | Default | Notes |
|---|---|---|
| `name` | required | instance name without the Environment; unique per stack |
| `enabled` | `true` | |
| `region` | required | |
| `environment` | `"dev"` | lifecycle tier (`dev`/`staging`/`prod`) for validation rules only; the catalog sets it from `settings.context.stage` |
| `instance_type` | required | |
| `vpc_id` | required | |
| `subnet` / `subnet_ids` | `null` / `[]` | `subnet` wins, else the first of `subnet_ids`; neither is a clear precondition error |
| `tags` | required | must contain `Environment` |
| `ami` | `""` | empty: latest Amazon Linux 2023 (`al2023-ami-2023.*-x86_64`, owner amazon); the lookup only runs then |
| `user_data` | `null` | plain text; base64-encoded where AWS needs it |
| `ssh_key_pair` | `null` | an existing key pair; unset (or `""`) + `create_ssh_keys = true` generates one, unset + `false` launches keyless |
| `security_groups` | `[]` | extra security groups besides the instance's own |
| `associate_public_ip_address` | `false` | |
| `monitoring`, `ebs_optimized` | `true`, `true` | |
| `disable_api_termination` | `false` | required `true` when `environment = "prod"` |
| `root_volume_type`, `root_volume_size` | `gp3`, `20` | Cloud Posse: `gp2`, `10` |
| `root_block_device_encrypted`, `root_block_device_kms_key_id`, `delete_on_termination` | `true`, `null`, `true` | |
| `ebs_block_devices` | `[]` | additional volumes |
| `metadata_http_tokens_required`, `metadata_http_put_response_hop_limit`, `metadata_tags_enabled` | `true`, `1`, `false` | Cloud Posse's hop limit is 2 |
| `allowed_ingress_rules`, `allowed_egress_rules` | `[]`, `null` | see "Security group"; `null` egress is all outbound |
| `enable_ssm`, `custom_iam_policy` | `true`, `""` | |
| `create_ssh_keys` | **`false`** | generate a key when `ssh_key_pair` is unset; the catalog sets it `true`, app-servers set it `false` |
| `store_ssh_keys_in_secrets_manager`, `ssh_key_algorithm`, `ssh_key_rsa_bits` | `true`, `ED25519`, `4096` | key generation (RSA only for Windows) |
| `ssh_key_secret_kms_key_id` | `null` | KMS key ARN, alias ARN, key ID or `alias/<name>` for the private-key secret (validated); null: `aws/secretsmanager` |
| `ssh_key_secret_recovery_window_in_days` | `30` | `0` or `7`-`30`, as Cloud Posse's `recovery_window_in_days` |
| `enable_launch_templates` | `false` | Cloud Posse's ec2-instance has no launch template |
| `create_instances_from_templates` | `false` | launch from the template instead of standalone; requires `enable_launch_templates` |
| `enable_network_interface_config` | `true` | launch template: put the subnet and security groups on its network interface rather than on the instance |
| `enable_resource_name_dns` | `true` | launch template: resource-name private DNS (`hostname_type = ip-name`, A record) |

### Behaviour changes from master

- **Instance metadata tags are off** (`metadata_tags_enabled = false`); master
  enabled `instance_metadata_tags` on every standalone instance.
- **Detailed monitoring is on** (`monitoring = true`, Cloud Posse's default);
  master left it off unless set, so dev and staging instances now incur the
  (small) detailed-monitoring cost.
- **Default AMI is Amazon Linux 2023**; master used Amazon Linux 2 (end of life
  2026-06-30).
- **Default egress is all outbound** (Cloud Posse's); master allowed HTTPS to the
  S3 prefix list only.
- **Keyless instances are allowed**; master required a key.

## Outputs

`id`, `arn`, `name`, `private_ip`, `public_ip`, `private_dns`, `ssh_key_pair` (the
key the instance **launched with**, so another instance can use it as its
`ssh_key_pair`), `security_group_id` (a string), `security_group_ids`, `role`,
`role_arn`, `instance_profile`, `launch_template_id`, `ssh_key_secret_arn`
(sensitive). With `enabled = false` all are null except `security_group_ids`,
which is `[]`.

## Launch template

With `enable_launch_templates = true` the component also creates a launch template
with the same AMI, key, IMDS settings, security groups, instance profile and volumes.
With `create_instances_from_templates = true` the instance is launched from it
(`aws_instance.from_launch_template`) **instead of** standalone
(`aws_instance.default`): exactly one of the two exists.

## Dependencies

- Every instance depends on `vpc/main`; each bastion also depends on `kms/main`
  (its key's secret, and prod's root volume); `ec2/app-server` also depends on
  `ec2/bastion` (it reads `.ssh_key_pair`, and in staging `.security_group_id`).

## Tests

`tests/ec2.tftest.hcl` runs with mock providers (no credentials): names, no doubled
Environment, IAM length, the `ssh_key_pair`/`security_group_id` formats consumers
rely on, no duplicate instance with `create_instances_from_templates`, per-instance
generated keys (ED25519, KMS, recovery window, `private_key_openssh` in the
secret), keyless instances and `""` as unset, IMDS and encryption defaults on both
paths, termination protection, the ingress/egress policy, the AMI lookup, and the
validations.

```
terraform init -backend=false && terraform test
```

## Usage

```
atmos terraform plan ec2/bastion -s fnx-dev-testenv-01
atmos terraform plan ec2/app-server -s fnx-staging-staging-01
```
