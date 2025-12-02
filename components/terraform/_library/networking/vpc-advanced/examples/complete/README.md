# Complete VPC Example

This example creates a full-featured production VPC with:

- 3 availability zones
- Public, private, and database subnets
- NAT Gateway per AZ (high availability)
- VPC Flow Logs to CloudWatch
- VPC Endpoints for S3, DynamoDB, ECR, CloudWatch, SSM
- Restricted default security group
- Comprehensive tagging

## Usage

```bash
terraform init
terraform plan
terraform apply
```

## Outputs

The example outputs key resource IDs including:
- VPC ID
- Subnet IDs (public, private, database)
- NAT Gateway public IPs
- VPC endpoint IDs

## Cost Estimation

Monthly costs (us-east-1):
- NAT Gateways: ~$97.92 (3 gateways x $0.045/hour x 730 hours)
- VPC Endpoints: ~$21.90 (7 interface endpoints x $0.01/hour x 730 hours)
- Data transfer: Variable based on usage
- Total: ~$120/month + data transfer

## Clean Up

```bash
terraform destroy
```

**Note**: Ensure all resources in the VPC are deleted before destroying the VPC.
