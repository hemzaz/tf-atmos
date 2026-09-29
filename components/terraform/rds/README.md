# rds

One RDS instance (optional read replica) with subnet group, security group, parameter group,
optional RDS Proxy, enhanced-monitoring role, CloudWatch alarms, and Secrets Manager rotation
notifications. `manage_master_user_password` is always on: RDS owns the master secret.

## Wiring

- Instances: `rds/main` in the three AWS stacks and `fnx-local-localemu` (reads `vpc/main`
  subnets, `kms/main .key_arn`, and admits `eks/main .eks_cluster_managed_security_group_id`);
  `rds/data` in the three AWS stacks (reads `vpc/services` and `kms/main`).
- Used by: `eks-backend-services` (`.password_secret_arn`, `.instance_endpoint`, `.instance_name`),
  `dns` (`network/main`'s `db.internal` CNAME from `.instance_address`), `monitoring`
  (`.instance_identifier`).
- `idp-platform` calls this component as a module (`source = "../rds"`); mirror variable changes
  there.

## Notes

- With `environment = "prod"`, validation requires `multi_az`, `deletion_protection`,
  `publicly_accessible = false` and `backup_retention_period >= 7`. `storage_encrypted` must always
  be `true`.
- Prod's `rds/main` encrypts the master secret with `kms/main` (`master_user_secret_kms_key_id`);
  external-secrets can already decrypt it.
- Use `instance_identifier` (the `DBInstanceIdentifier` dimension) for CloudWatch, not `instance_id`
  (the `db-...` resource ID since AWS provider v5).
- `rds/main` really runs against LocalEmu in `atmos workflow localemu -f localemu`; Floci cannot run
  it (no `CreateDBSubnetGroup`).
