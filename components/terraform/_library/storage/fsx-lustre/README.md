# FSx Lustre Module

Production-ready Amazon FSx for Lustre with S3 integration, automatic backups, and high-performance computing capabilities.

## Features

- Scratch or Persistent deployment types
- S3 data repository integration (import/export)
- Data repository associations with auto-import/export
- KMS encryption at rest with automatic key rotation
- Automatic backups for persistent deployments
- LZ4 data compression
- Weekly maintenance windows
- CloudWatch logging and alarms
- SSD or HDD storage options
- Configurable throughput performance

## Usage

```hcl
module "fsx_lustre" {
  source = "../../_library/storage/fsx-lustre"

  name_prefix = "myapp"
  environment = "production"

  subnet_id          = "subnet-abc123"
  security_group_ids = ["sg-xyz789"]

  storage_capacity_gb         = 2400
  deployment_type             = "PERSISTENT_2"
  per_unit_storage_throughput = 250

  create_s3_bucket = true
  data_compression_type = "LZ4"

  automatic_backup_retention_days = 7
  weekly_maintenance_start_time   = "1:03:00"

  data_repository_associations = {
    main = {
      data_repository_path = "s3://my-bucket/data/"
      file_system_path     = "/mnt/data"
      s3_auto_import_policy = ["NEW", "CHANGED", "DELETED"]
      s3_auto_export_policy = ["NEW", "CHANGED", "DELETED"]
    }
  }

  tags = {
    Project = "HPC"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 5.0.0 |

## Inputs

See `variables.tf` for all available inputs.

## Outputs

See `outputs.tf` for all available outputs.
