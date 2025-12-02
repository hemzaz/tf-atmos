# NAT Gateway HA

Highly available NAT Gateway setup with one NAT Gateway per availability zone.

## Features

- One NAT Gateway per AZ for high availability
- Elastic IP management
- Automatic route table configuration
- CloudWatch monitoring and alarms
- Cost tracking dashboard
- Port allocation and packet drop alarms

## Usage

```hcl
module "nat_gateway_ha" {
  source = "./_library/networking/nat-gateway-ha"

  name_prefix = "prod"
  environment = "production"

  vpc_id                = "vpc-123456"
  public_subnet_ids     = ["subnet-pub1", "subnet-pub2", "subnet-pub3"]
  private_subnet_ids    = ["subnet-priv1", "subnet-priv2", "subnet-priv3"]
  availability_zones    = ["us-east-1a", "us-east-1b", "us-east-1c"]
  internet_gateway_id   = "igw-123456"

  enable_cloudwatch_alarms = true
  alarm_sns_topic_arns     = ["arn:aws:sns:us-east-1:123456789:alerts"]
}
```

## Inputs

See `variables.tf` for complete list of variables.

## Outputs

See `outputs.tf` for complete list of outputs.
