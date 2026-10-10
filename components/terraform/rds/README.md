# rds

One RDS instance (optional read replica) with subnet group, security group, parameter group,
optional RDS Proxy, enhanced-monitoring role, CloudWatch alarms, and Secrets Manager rotation
notifications. `manage_master_user_password` is always on: RDS owns the master secret.

## Wiring

- Instances: `rds/main` in the three AWS stacks and `fnx-ue1-local-localemu` (reads `vpc/main`
  subnets; in the AWS stacks it also admits `eks/main .eks_cluster_managed_security_group_id`);
  `rds/data` in the three AWS stacks (reads `vpc/services`). Only prod's instances read `kms/main .key_arn`;
  dev and staging use AWS-managed keys. `rds/main` also in `fnx-ue2-prod` (a cross-region replica)
  and `fnx-ew1-prod`; `fnx-ue1-prod`'s and `fnx-ew1-prod`'s inherit `rds/main-prod`
  (`stacks/catalog/rds/prod.yaml`). `check-data-residency.py` fails a stack outside the EU that
  depends on an EU one or names an `eu-` ARN in its vars (e.g. `replicate_source_db`), so no US
  replica can read an EU instance.
- Used by: `eks-backend-services` (`.password_secret_arn`, `.instance_endpoint`, `.instance_name`),
  `dns` (`network/main`'s `db.internal` CNAME from `.instance_address`), `monitoring`
  (`.instance_identifier`).
- The `idp-platform` template's `idp-platform/rds` instance.

## Notes

- With `environment = "prod"`, validation requires `multi_az`, `deletion_protection`,
  `publicly_accessible = false` and `backup_retention_period >= 7`. `storage_encrypted` must always
  be `true`.
- Prod's `rds/main` encrypts the master secret with `kms/main` (`master_user_secret_kms_key_id`);
  external-secrets can already decrypt it.
- `engine` is `postgres`, `mysql` or `mariadb` (10.5+). Unless set, `family` derives from the
  engine and `engine_version` (`postgres14`, `mysql8.0`, `mariadb10.11`) and `port` from the
  engine (5432 postgres, 3306 otherwise). An explicit `family` must belong to the engine.
- The parameter group is the engine defaults overlaid by `parameters` (the caller's entry wins,
  last per name). Defaults: `rds.force_ssl = 1` (postgres) or `require_secure_transport = ON`, and
  `log_statement = ddl`. Turning either off takes an explicit entry in `parameters`.
- The TLS parameter is `pending-reboot`: a new instance starts with it, but an instance that
  existed without it enforces TLS only after its next reboot.
- With TLS required, clients must connect with TLS; to verify the server
  (`sslmode=verify-full`), an app needs the RDS CA bundle
  (`https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem`) in its image.
  `eks-backend-services` builds its DSNs that way (`database_ca_bundle_path`).
- The read replica uses the primary's security group, parameter group, deletion protection,
  Performance Insights key and enhanced monitoring.
- `replicate_source_db` (Cloud Posse `terraform-aws-rds`'s input) makes the instance a replica of
  another: an identifier in the same region, an ARN (`instance_arn` output) across regions, with
  `kms_key_id` a key in the replica's region. It takes engine version, master user and database
  from the source, carries `Role=read-replica` (so `backup` skips it), and has no master user
  secret (`password_secret_arn` is null) and no rotation. Setting it back to `null` promotes the
  replica: RDS then creates the managed secret and rotation starts. A replica cannot use RDS Proxy.
  Setting it on a standalone instance, or to another source, does not force a replacement in the
  AWS provider, and AWS cannot turn an instance into a replica: the apply errors. Replace it
  explicitly (`-replace=aws_db_instance.main`, deletion protection lifted first), as the DR
  failback does (docs/OPERATIONS.md). A promotion's plan must update in place: `db_name` and
  `username` force a replacement, so they must equal the source's.
  Deleting an unpromoted replica needs `skip_final_snapshot: true` (RDS takes no final snapshot of a
  replica); deletion protection blocks it either way.
- The final snapshot is `final_snapshot_identifier`, else `<Environment>-<identifier>-final-snapshot`:
  stable across plans, so destroying, recreating and destroying again needs the old snapshot
  deleted or a new `final_snapshot_identifier`.
- Use `instance_identifier` (the `DBInstanceIdentifier` dimension) for CloudWatch, not `instance_id`
  (the `db-...` resource ID since AWS provider v5).
- `rds/main` really runs against LocalEmu in `atmos workflow localemu -f localemu`; Floci cannot run
  it (no `CreateDBSubnetGroup`).
