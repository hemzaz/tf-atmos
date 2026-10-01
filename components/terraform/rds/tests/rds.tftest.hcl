# Mock-provider tests: no AWS credentials, no network. Run from the component
# directory with `terraform init -backend=false && terraform test`.
#
# Covers the custom_ingress_rules /0 guard, the parameter-group defaults and
# caller overrides (TLS, log_statement), the read replica's parity with the
# primary and the stable final snapshot name.

mock_provider "aws" {}

variables {
  region     = "eu-west-2"
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
    performance_insights_kms_key_id = "arn:aws:kms:eu-west-2:123456789012:key/00000000-0000-0000-0000-000000000000"
    monitoring_interval             = 60
    create_monitoring_role          = true
  }

  override_resource {
    target = aws_db_instance.main
    values = {
      master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:eu-west-2:123456789012:secret:rds-test-AbCdEf", kms_key_id = "", secret_status = "active" }]
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
}
