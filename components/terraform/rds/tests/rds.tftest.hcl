# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.
#
# Covers the custom_ingress_rules /0 guard, the parameter-group defaults and
# caller overrides (TLS, log_statement), the read replica's parity with the
# primary and the stable final snapshot name.

mock_provider "aws" {}

# The service-role trusts embed the account id (S4).
override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
  }
}

override_data {
  target = data.aws_partition.current
  values = {
    partition = "aws"
  }
}

variables {
  region     = "us-east-1"
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  identifier = "test-db"
  db_name    = "testdb"
  tags = {
    Environment = "test"
    Tenant      = "fnx"
    ManagedBy   = "Terraform"
  }
}

run "default_has_no_custom_ingress_rules" {
  command = plan

  assert {
    condition     = length(var.custom_ingress_rules) == 0
    error_message = "custom_ingress_rules must default to an empty list."
  }
}

# --- B1 DR: a cross-region replica (Cloud Posse terraform-aws-rds replicate_source_db) ---

run "cross_region_replica_takes_engine_user_and_db_from_its_source" {
  command = plan

  variables {
    engine              = "postgres"
    engine_version      = "14"
    replicate_source_db = "arn:aws:rds:us-east-1:123456789012:db:ue1-prod-main-db"
    kms_key_id          = "arn:aws:kms:us-east-2:123456789012:key/mrk-0123456789abcdef0123456789abcdef"
  }

  # engine_version, username and db_name are computed when unset, so a plan
  # cannot assert they are null; unset they come from the source.
  assert {
    condition     = aws_db_instance.main.replicate_source_db == "arn:aws:rds:us-east-1:123456789012:db:ue1-prod-main-db"
    error_message = "replicate_source_db must reach the instance."
  }


  assert {
    condition     = aws_db_instance.main.tags["Role"] == "read-replica"
    error_message = "A replica must carry Role=read-replica, which backup's tag selection excludes."
  }

  assert {
    condition     = length(aws_secretsmanager_secret_rotation.db_password) == 0
    error_message = "A replica has no master user secret, so no rotation until it is promoted."
  }

  # The parameter group still derives from engine/engine_version: it must
  # match the source's family.
  assert {
    condition     = aws_db_parameter_group.main.family == "postgres14"
    error_message = "A replica's parameter group must use the source engine's family."
  }
}

run "promoted_replica_is_a_primary_with_a_managed_secret" {
  command = plan

  assert {
    condition     = aws_db_instance.main.manage_master_user_password == true && aws_db_instance.main.tags["Role"] == "primary" && length(aws_secretsmanager_secret_rotation.db_password) == 1
    error_message = "Without replicate_source_db the instance is a primary: managed secret, rotation, Role=primary."
  }
}

run "replica_with_a_proxy_is_rejected" {
  command = plan

  variables {
    replicate_source_db = "arn:aws:rds:us-east-1:123456789012:db:ue1-prod-main-db"
    enable_rds_proxy    = true
  }

  expect_failures = [var.replicate_source_db]
}

run "replica_source_that_is_not_an_identifier_or_arn_is_rejected" {
  command = plan

  variables {
    replicate_source_db = "arn:aws:rds:us-east-1:123456789012:cluster:aurora"
  }

  expect_failures = [var.replicate_source_db]
}

# Prod's kms/main is multi-region (B1 DR): its key ids start with mrk-.
run "multi_region_kms_key_is_accepted" {
  command = plan

  variables {
    kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/mrk-0123456789abcdef0123456789abcdef"
  }
}

run "kms_key_id_that_is_not_a_key_arn_is_rejected" {
  command = plan

  variables {
    kms_key_id = "arn:aws:kms:us-east-1:123456789012:alias/ue1-main"
  }

  expect_failures = [var.kms_key_id]
}

run "retired_ca_cert_identifier_is_rejected" {
  command = plan

  variables {
    ca_cert_identifier = "rds-ca-2019"
  }

  expect_failures = [var.ca_cert_identifier]
}

run "custom_ingress_open_to_everywhere_is_rejected" {
  command = plan

  variables {
    custom_ingress_rules = [{
      description = "example"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/8", "0.0.0.0/0"]
    }]
  }

  expect_failures = [var.custom_ingress_rules]
}

run "custom_ingress_ipv6_open_to_everywhere_is_rejected" {
  command = plan

  # ::/0 is as open as 0.0.0.0/0; the prefix-length check must catch both.
  variables {
    custom_ingress_rules = [{
      description = "example"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = ["::/0"]
    }]
  }

  expect_failures = [var.custom_ingress_rules]
}

run "custom_ingress_slash_00_is_rejected" {
  command = plan

  # AWS parses "/00" the same as "/0"; the check compares the prefix length
  # as a number, not as the literal string "0", so this must be caught too.
  variables {
    custom_ingress_rules = [{
      description = "example"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/00"]
    }]
  }

  expect_failures = [var.custom_ingress_rules]
}

run "custom_ingress_from_private_cidr_is_allowed" {
  command = plan

  variables {
    custom_ingress_rules = [{
      description = "example"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/8"]
    }]
  }

  assert {
    condition     = length(var.custom_ingress_rules) == 1
    error_message = "A private CIDR must be accepted."
  }
}

# --- Hardening: parameters, TLS, read replica, final snapshot ---------------

run "postgres_defaults_log_ddl_and_force_ssl" {
  command = plan

  variables {
    engine = "postgres"
    family = "postgres16"
  }

  assert {
    condition     = one([for p in aws_db_parameter_group.main.parameter : p.value if p.name == "log_statement"]) == "ddl"
    error_message = "log_statement must default to ddl, not all."
  }

  assert {
    condition     = one([for p in aws_db_parameter_group.main.parameter : p.value if p.name == "rds.force_ssl"]) == "1"
    error_message = "Postgres must default to rds.force_ssl = 1."
  }

  assert {
    condition     = one([for p in aws_db_parameter_group.main.parameter : p.apply_method if p.name == "rds.force_ssl"]) == "pending-reboot"
    error_message = "rds.force_ssl must apply at the next reboot, not drop live sessions mid-apply."
  }

  assert {
    condition     = length([for p in aws_db_parameter_group.main.parameter : p if p.name == "require_secure_transport"]) == 0
    error_message = "require_secure_transport is a MySQL parameter; Postgres must not get it."
  }

  assert {
    condition     = one([for p in aws_db_parameter_group.main.parameter : p.apply_method if p.name == "shared_preload_libraries"]) == "pending-reboot"
    error_message = "shared_preload_libraries is static: AWS rejects apply_method immediate."
  }
}

run "mysql_defaults_require_secure_transport" {
  command = plan

  assert {
    condition     = one([for p in aws_db_parameter_group.main.parameter : p.value if p.name == "require_secure_transport"]) == "ON"
    error_message = "MySQL must default to require_secure_transport = ON."
  }

  assert {
    condition     = length([for p in aws_db_parameter_group.main.parameter : p if p.name == "rds.force_ssl" || startswith(p.name, "query_cache")]) == 0
    error_message = "MySQL must get neither rds.force_ssl nor the query cache parameters MySQL 8.0 removed."
  }
}

# The stacks set engine = postgres, engine_version = "14" and no family: the
# old mysql8.0 default family put postgres parameters in a mysql group.
run "postgres_family_and_port_derive_from_the_engine" {
  command = plan

  variables {
    engine         = "postgres"
    engine_version = "14"
  }

  assert {
    condition     = aws_db_parameter_group.main.family == "postgres14"
    error_message = "postgres 14 with no family must derive postgres14."
  }

  assert {
    condition     = aws_db_instance.main.port == 5432
    error_message = "postgres with no port must use 5432."
  }
}

run "postgres_minor_version_derives_the_major_family" {
  command = plan

  variables {
    engine         = "postgres"
    engine_version = "16.4"
  }

  assert {
    condition     = aws_db_parameter_group.main.family == "postgres16"
    error_message = "postgres 16.4 must derive postgres16."
  }
}

run "mysql_family_and_port_derive_from_the_engine" {
  command = plan

  variables {
    engine_version = "8.0.39"
  }

  assert {
    condition     = aws_db_parameter_group.main.family == "mysql8.0" && aws_db_instance.main.port == 3306
    error_message = "mysql 8.0.39 with no family/port must derive mysql8.0 and 3306."
  }
}

run "mariadb_family_derives_major_minor" {
  command = plan

  variables {
    engine         = "mariadb"
    engine_version = "10.11"
  }

  assert {
    condition     = aws_db_parameter_group.main.family == "mariadb10.11" && aws_db_instance.main.port == 3306
    error_message = "mariadb 10.11 must derive mariadb10.11 and 3306."
  }
}

run "explicit_family_and_port_win" {
  command = plan

  variables {
    engine         = "postgres"
    engine_version = "14"
    family         = "postgres14"
    port           = 6432
  }

  assert {
    condition     = aws_db_parameter_group.main.family == "postgres14" && aws_db_instance.main.port == 6432 && one(aws_security_group.rds.ingress[*].from_port) == 6432
    error_message = "An explicit family and port must be used, the port by the security group too."
  }
}

run "mismatched_family_is_rejected" {
  command = plan

  variables {
    engine         = "postgres"
    engine_version = "14"
    family         = "mysql8.0"
  }

  expect_failures = [var.family]
}

run "unknown_engine_is_rejected" {
  command = plan

  variables {
    engine = "oracle-ee"
    family = "oracle-ee-19"
  }

  expect_failures = [var.engine]
}

run "mariadb_before_10_5_is_rejected" {
  command = plan

  variables {
    engine         = "mariadb"
    engine_version = "10.4"
  }

  expect_failures = [var.engine_version]
}

run "caller_parameters_override_defaults" {
  command = plan

  variables {
    engine = "postgres"
    family = "postgres16"
    parameters = [
      { name = "log_statement", value = "mod" },
      { name = "rds.force_ssl", value = "0" },
      { name = "log_statement", value = "none" },
      { name = "pg_stat_statements.track", value = "all" },
    ]
  }

  assert {
    condition     = one([for p in aws_db_parameter_group.main.parameter : p.value if p.name == "log_statement"]) == "none"
    error_message = "The caller's log_statement must win over the default, last entry per name."
  }

  assert {
    condition     = one([for p in aws_db_parameter_group.main.parameter : p.value if p.name == "rds.force_ssl"]) == "0"
    error_message = "An explicit caller rds.force_ssl must win over the default."
  }

  assert {
    condition     = one([for p in aws_db_parameter_group.main.parameter : p.apply_method if p.name == "pg_stat_statements.track"]) == "immediate"
    error_message = "A caller parameter without apply_method must default to immediate."
  }
}

run "bad_apply_method_is_rejected" {
  command = plan

  variables {
    parameters = [{ name = "long_query_time", value = "2", apply_method = "later" }]
  }

  expect_failures = [var.parameters]
}

run "final_snapshot_identifier_is_static" {
  command = plan

  variables {
    skip_final_snapshot = false
  }

  # A literal: the old timestamp() suffix was unknown at plan time and
  # different on every plan.
  assert {
    condition     = aws_db_instance.main.final_snapshot_identifier == "test-test-db-final-snapshot"
    error_message = "final_snapshot_identifier must be the stable <Environment>-<identifier>-final-snapshot."
  }
}

run "final_snapshot_identifier_is_static_on_a_second_plan" {
  command = plan

  variables {
    skip_final_snapshot = false
  }

  assert {
    condition     = aws_db_instance.main.final_snapshot_identifier == "test-test-db-final-snapshot"
    error_message = "A second plan must produce the same final_snapshot_identifier."
  }
}

run "final_snapshot_identifier_override_and_skip" {
  command = plan

  variables {
    skip_final_snapshot       = false
    final_snapshot_identifier = "custom-final"
  }

  assert {
    condition     = aws_db_instance.main.final_snapshot_identifier == "custom-final"
    error_message = "An explicit final_snapshot_identifier must be used as given."
  }
}

run "skip_final_snapshot_takes_none" {
  command = plan

  variables {
    skip_final_snapshot = true
  }

  assert {
    condition     = aws_db_instance.main.final_snapshot_identifier == null && aws_db_instance.main.skip_final_snapshot
    error_message = "skip_final_snapshot = true must still take no final snapshot."
  }
}

run "read_replica_matches_primary" {
  command = apply

  variables {
    engine                          = "postgres"
    family                          = "postgres16"
    create_read_replica             = true
    deletion_protection             = true
    performance_insights_enabled    = true
    performance_insights_kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    monitoring_interval             = 60
    create_monitoring_role          = true
    max_allocated_storage           = 500
    ca_cert_identifier              = "rds-ca-rsa4096-g1"
  }

  override_resource {
    target = aws_db_instance.main
    values = {
      master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds-test-AbCdEf", kms_key_id = "", secret_status = "active" }]
    }
  }

  override_resource {
    target = aws_iam_role.monitoring
    values = {
      arn = "arn:aws:iam::123456789012:role/test-test-db-monitoring-role"
    }
  }

  assert {
    condition     = aws_db_instance.read_replica[0].vpc_security_group_ids == toset([aws_security_group.rds.id])
    error_message = "The replica must use the primary's security group, not the VPC default."
  }

  assert {
    condition     = aws_db_instance.read_replica[0].replicate_source_db == aws_db_instance.main.identifier
    error_message = "replicate_source_db must be the primary's identifier, not its db-XXXX resource id."
  }

  assert {
    condition     = aws_db_instance.read_replica[0].deletion_protection
    error_message = "The replica must inherit the primary's deletion_protection."
  }

  assert {
    condition     = aws_db_instance.read_replica[0].performance_insights_kms_key_id == aws_db_instance.main.performance_insights_kms_key_id
    error_message = "The replica must encrypt Performance Insights with the primary's key."
  }

  assert {
    condition     = aws_db_instance.read_replica[0].parameter_group_name == aws_db_parameter_group.main.name
    error_message = "The replica must use the primary's parameter group (TLS and logging defaults)."
  }

  assert {
    condition     = aws_db_instance.read_replica[0].monitoring_role_arn == aws_db_instance.main.monitoring_role_arn && aws_db_instance.read_replica[0].monitoring_interval == 60
    error_message = "The replica must have the primary's enhanced monitoring."
  }

  assert {
    condition = (
      aws_db_instance.read_replica[0].max_allocated_storage == aws_db_instance.main.max_allocated_storage
      && aws_db_instance.read_replica[0].max_allocated_storage == 500
    )
    error_message = "The replica must autoscale storage to the primary's max_allocated_storage."
  }

  assert {
    condition = (
      aws_db_instance.read_replica[0].ca_cert_identifier == aws_db_instance.main.ca_cert_identifier
      && aws_db_instance.read_replica[0].ca_cert_identifier == "rds-ca-rsa4096-g1"
    )
    error_message = "The replica must use the primary's CA certificate."
  }
}

# S4: confused-deputy conditions on the service-role trusts (RDS docs:
# USER_Monitoring.OS.Enabling.html#USER_Monitoring.OS.confused-deputy and
# cross-service-confused-deputy-prevention.html).
run "service_role_trusts_are_scoped_to_this_account" {
  command = plan

  variables {
    create_read_replica       = true
    monitoring_interval       = 60
    create_monitoring_role    = true
    enable_rds_proxy          = true
    create_rotation_sns_topic = true
  }

  override_resource {
    target          = aws_sns_topic.rotation_notifications[0]
    override_during = plan
    values = {
      arn = "arn:aws:sns:us-east-1:123456789012:test-test-db-rotation"
    }
  }

  override_resource {
    target          = aws_db_instance.main
    override_during = plan
    values = {
      master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds-test-AbCdEf", kms_key_id = "", secret_status = "active" }]
    }
  }

  assert {
    condition = (
      jsondecode(aws_iam_role.monitoring[0].assume_role_policy).Statement[0].Principal.Service == "monitoring.rds.amazonaws.com"
      && jsondecode(aws_iam_role.monitoring[0].assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "123456789012"
      && toset(jsondecode(aws_iam_role.monitoring[0].assume_role_policy).Statement[0].Condition.ArnLike["aws:SourceArn"]) == toset([
        "arn:aws:rds:us-east-1:123456789012:db:test-test-db",
        "arn:aws:rds:us-east-1:123456789012:db:test-test-db-read-replica",
      ])
    )
    error_message = "The enhanced-monitoring role must trust monitoring.rds.amazonaws.com only for this account and for exactly the primary and replica instance ARNs."
  }

  # The proxy trust stays exactly as AWS documents it (rds-proxy-iam-setup.html):
  # no Condition, since AWS does not document source keys for the proxy.
  assert {
    condition = (
      jsondecode(aws_iam_role.rds_proxy[0].assume_role_policy).Statement[0].Principal.Service == "rds.amazonaws.com"
      && !can(jsondecode(aws_iam_role.rds_proxy[0].assume_role_policy).Statement[0].Condition)
    )
    error_message = "The RDS Proxy role must trust rds.amazonaws.com with no Condition, as AWS documents it."
  }

  assert {
    condition = (
      jsondecode(aws_sns_topic_policy.rotation_notifications[0].policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "123456789012"
      && jsondecode(aws_sns_topic_policy.rotation_notifications[0].policy).Statement[0].Condition.ArnLike["aws:SourceArn"] == "arn:aws:events:us-east-1:123456789012:rule/*"
    )
    error_message = "The rotation topic accepts EventBridge publishes only from this account's rules."
  }
}

run "monitoring_trust_names_only_the_primary_without_a_replica" {
  command = plan

  variables {
    monitoring_interval    = 60
    create_monitoring_role = true
  }

  assert {
    condition     = jsondecode(aws_iam_role.monitoring[0].assume_role_policy).Statement[0].Condition.ArnLike["aws:SourceArn"] == ["arn:aws:rds:us-east-1:123456789012:db:test-test-db"]
    error_message = "Without a read replica the enhanced-monitoring trust names only the primary."
  }
}

run "prod_accepts_graviton_and_intel_production_classes" {
  command = plan

  variables {
    environment         = "prod"
    multi_az            = true
    deletion_protection = true
    instance_class      = "db.r6g.large"
  }
}

run "prod_accepts_t4g_medium" {
  command = plan

  variables {
    environment         = "prod"
    multi_az            = true
    deletion_protection = true
    instance_class      = "db.t4g.medium"
  }
}

run "prod_rejects_a_small_burstable_class" {
  command = plan

  variables {
    environment         = "prod"
    multi_az            = true
    deletion_protection = true
    instance_class      = "db.t3.micro"
  }

  expect_failures = [var.instance_class]
}

run "prod_accepts_r6i" {
  command = plan

  variables {
    environment         = "prod"
    multi_az            = true
    deletion_protection = true
    instance_class      = "db.r6i.xlarge"
  }
}

run "prod_accepts_m7g" {
  command = plan

  variables {
    environment         = "prod"
    multi_az            = true
    deletion_protection = true
    instance_class      = "db.m7g.large"
  }
}

run "prod_rejects_t4g_small" {
  command = plan

  variables {
    environment         = "prod"
    multi_az            = true
    deletion_protection = true
    instance_class      = "db.t4g.small"
  }

  expect_failures = [var.instance_class]
}

# A lane's Environment (<region code>-<name>) lengthens every name; a long one
# fails at plan, not at apply.
run "name_base_over_47_characters_is_rejected" {
  command = plan

  variables {
    identifier = "orders-database-primary"
    tags       = { Environment = "ue1-xxxxxxxxxxxxxxxxxxxx", Tenant = "fnx", ManagedBy = "Terraform" }
  }

  expect_failures = [var.identifier]
}

run "name_base_of_47_characters_passes" {
  command = plan

  variables {
    identifier              = "orders-database-primary"
    create_read_replica     = true
    enable_secrets_rotation = true
    enable_rotation_events  = true
    tags                    = { Environment = "ue1-xxxxxxxxxxxxxxxxxxx", Tenant = "fnx", ManagedBy = "Terraform" }
  }

  # The rotation-success rule is the longest 64-limited name: exactly 64 here.
  assert {
    condition     = aws_cloudwatch_event_rule.rotation_success[0].name == "ue1-xxxxxxxxxxxxxxxxxxx-orders-database-primary-rotation-success" && length(aws_cloudwatch_event_rule.rotation_success[0].name) == 64
    error_message = "At the 47-character base the rotation-success rule name is exactly 64 characters."
  }

  assert {
    condition     = aws_db_instance.read_replica[0].identifier == "ue1-xxxxxxxxxxxxxxxxxxx-orders-database-primary-read-replica" && aws_iam_role.monitoring[0].name == "ue1-xxxxxxxxxxxxxxxxxxx-orders-database-primary-monitoring-role"
    error_message = "The replica and monitoring role names are <Environment>-<identifier>-<suffix>."
  }
}
