# ec2

One EC2 instance per component instance, modelled on Cloud Posse `aws-ec2-instance`: the instance,
its own security group, an IAM role and instance profile (SSM by default), and optionally a
generated key pair whose private key is stored in Secrets Manager. IMDSv2 is required (hop limit
1), the root volume is encrypted, the default AMI is the latest Amazon Linux 2023, and keyless
(SSM-only) instances are allowed.

## Wiring

- Instances: `ec2/bastion` in the three AWS stacks (reads `vpc/main` subnets and `kms/main
  .key_arn`); `ec2/app-server` in dev and staging (reads `vpc/main` and `ec2/bastion
  .ssh_key_pair` / `.security_group_id`).
- Apply order: `kms/main`, `ec2/bastion`, `ec2/app-server`.

## Notes

- Names are `<Environment>-<name>` (instance, `-sg`, `-role`, `-profile`, `-ec2-ssh-key`, secret
  `ssh-key/<Environment>/<name>`). Two instances in one stack must not share a `name`; this is not
  validated.
- Bastions generate an ED25519 key; app-servers set `create_ssh_keys: false` and launch with the
  bastion's key (keyless if that read resolves to null). A given `ssh_key_pair` must already exist.
- Export the key with `scripts/certificates/export-ssh-key.sh -s ssh-key/<Environment>/<name> -o
  <file>`; use `private_key_openssh` (the ED25519 PEM is PKCS#8, which OpenSSH rejects).
- The private key is also in Terraform state (`tls_private_key`), so state readers can reach the
  bastion.
- Changing `ssh_key_algorithm` or `ssh_key_rsa_bits` replaces the key, the key pair and the
  instance.
- `disable_api_termination` must be `true` when `environment = "prod"`.
- With `create_instances_from_templates` the instance launches from the launch template instead of
  standalone; exactly one of the two exists.

## Security group

The instance's own group takes inline rules from `allowed_ingress_rules` and
`allowed_egress_rules` instead of Cloud Posse's per-rule `security_group_rules`, keeping one
resource and readable per-instance rules; moving to Cloud Posse's form later replaces the rules.
Ingress rejects any `/0`; egress defaults to all outbound (Cloud Posse's default).
