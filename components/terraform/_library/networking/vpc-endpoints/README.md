# VPC Endpoints

Comprehensive VPC endpoints module supporting 30+ AWS services with Gateway and Interface endpoints.

## Features

- Gateway endpoints (S3, DynamoDB) - free
- Interface endpoints (30+ services)
- Automatic security group creation
- Private DNS configuration
- Endpoint policies
- Cost estimation and breakdown
- Multi-AZ deployment

## Usage

```hcl
module "vpc_endpoints" {
  source = "./_library/networking/vpc-endpoints"

  name_prefix = "prod"
  environment = "production"
  vpc_id      = "vpc-123456"
  vpc_cidr    = "10.0.0.0/16"

  endpoints = {
    s3 = {
      type            = "Gateway"
      route_table_ids = ["rt-123", "rt-456"]
    }

    ecr_api = {
      type       = "Interface"
      subnet_ids = ["subnet-abc", "subnet-def"]
    }

    ecr_dkr = {
      type       = "Interface"
      subnet_ids = ["subnet-abc", "subnet-def"]
    }
  }
}
```

## Inputs

See `variables.tf` for complete list of variables.

## Outputs

See `outputs.tf` for complete list of outputs.
