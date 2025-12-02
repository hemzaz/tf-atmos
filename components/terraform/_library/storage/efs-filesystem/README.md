# EFS Filesystem Module

Production-ready Amazon Elastic File System with lifecycle management, multi-AZ mount targets, and CloudWatch monitoring.

## Features

- Multi-AZ mount targets for high availability
- KMS encryption at rest with automatic key rotation
- Lifecycle management (IA and Archive storage classes)
- EFS access points for application isolation
- Automatic backups via AWS Backup integration
- Performance modes (General Purpose, Max I/O)
- Throughput modes (Bursting, Provisioned, Elastic)
- CloudWatch alarms for monitoring
- File system policies for access control

## Usage

```hcl
module "efs" {
  source = "../../_library/storage/efs-filesystem"

  name_prefix = "myapp"
  environment = "production"

  subnet_ids         = ["subnet-abc123", "subnet-def456", "subnet-ghi789"]
  security_group_ids = ["sg-xyz789"]

  performance_mode = "generalPurpose"
  throughput_mode  = "elastic"

  transition_to_ia = "AFTER_30_DAYS"
  enable_backup_policy = true

  access_points = {
    app1 = {
      posix_user = {
        gid = 1000
        uid = 1000
      }
      root_directory = {
        path = "/app1"
        creation_info = {
          owner_gid   = 1000
          owner_uid   = 1000
          permissions = "0755"
        }
      }
    }
  }

  tags = {
    Project = "MyApp"
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
