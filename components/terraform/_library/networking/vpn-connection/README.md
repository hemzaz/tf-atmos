# VPN Connection

Site-to-Site VPN with customer gateway, virtual private gateway, and comprehensive monitoring.

## Features

- Customer gateway configuration
- Virtual private gateway or Transit Gateway support
- Static and dynamic routing (BGP)
- Tunnel configuration with IKEv2
- CloudWatch logs and alarms
- High availability with dual tunnels
- Advanced IPsec parameters

## Usage

```hcl
module "vpn" {
  source = "./_library/networking/vpn-connection"

  name_prefix = "prod"
  environment = "production"

  customer_gateway_ip_address = "203.0.113.12"
  customer_gateway_bgp_asn    = 65000

  vpc_id                      = "vpc-123456"
  vpn_gateway_amazon_side_asn = 64512

  enable_cloudwatch_logs   = true
  enable_cloudwatch_alarms = true
  alarm_sns_topic_arns     = ["arn:aws:sns:us-east-1:123456789:alerts"]
}
```

## Inputs

See `variables.tf` for complete list of variables.

## Outputs

See `outputs.tf` for complete list of outputs.
