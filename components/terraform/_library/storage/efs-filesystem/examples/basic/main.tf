provider "aws" {
  region = "us-east-1"
}

module "efs" {
  source = "../../"

  name_prefix = "example"
  environment = "dev"

  subnet_ids         = ["subnet-12345678", "subnet-87654321", "subnet-abcdef12"]
  security_group_ids = ["sg-12345678"]

  performance_mode = "generalPurpose"
  throughput_mode  = "elastic"

  transition_to_ia = "AFTER_30_DAYS"
  enable_backup_policy = true

  access_points = {
    wordpress = {
      posix_user = {
        gid = 1000
        uid = 1000
      }
      root_directory = {
        path = "/wordpress"
        creation_info = {
          owner_gid   = 1000
          owner_uid   = 1000
          permissions = "0755"
        }
      }
    }
  }

  tags = {
    Project = "Example"
    Purpose = "Demo"
  }
}

output "file_system_id" {
  value = module.efs.file_system_id
}

output "mount_command" {
  value = module.efs.mount_command
}
