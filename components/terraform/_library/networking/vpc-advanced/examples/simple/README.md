# Simple VPC Example

This example creates a basic VPC suitable for development environments:

- 2 availability zones
- Public and private subnets
- Single NAT Gateway (cost optimization)
- VPC Flow Logs with 7-day retention
- Basic tagging

## Usage

```bash
terraform init
terraform plan
terraform apply
```

## Cost Estimation

Monthly costs (us-east-1):
- NAT Gateway: ~$32.64 (1 gateway x $0.045/hour x 730 hours)
- Flow Logs storage: ~$0.50 (depends on traffic)
- Total: ~$33/month + data transfer

## Clean Up

```bash
terraform destroy
```
