# Transit Gateway

Production-ready AWS Transit Gateway module with VPC attachments, VPN connections, and cross-region peering.

## Features

- Transit Gateway with customizable ASN
- VPC attachments with route table management
- VPN attachments with BGP support
- Custom route tables and associations
- Route propagation control
- Cross-account sharing via RAM
- Cross-region peering
- CloudWatch monitoring ready

## Usage

```hcl
module "transit_gateway" {
  source = "./_library/networking/transit-gateway"

  name_prefix = "prod"
  environment = "production"

  amazon_side_asn = 64512
  dns_support     = true
  vpn_ecmp_support = true

  vpc_attachments = {
    vpc1 = {
      vpc_id     = "vpc-123456"
      subnet_ids = ["subnet-abc123", "subnet-def456"]
      route_table_id = "rt1"
    }
  }

  transit_gateway_route_tables = {
    rt1 = {
      routes = [
        {
          destination_cidr_block = "10.0.0.0/8"
          attachment_key         = "vpc1"
        }
      ]
    }
  }
}
```

## Inputs

See `variables.tf` for complete list of variables.

## Outputs

See `outputs.tf` for complete list of outputs.
