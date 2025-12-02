# Complete S3 Bucket Example

This example creates a production-ready S3 bucket with all features enabled:

- KMS encryption
- Versioning
- Lifecycle policies (transitions to IA, Glacier, Deep Archive)
- Cross-region replication
- Event notifications
- Access logging
- Intelligent-Tiering
- Inventory reports
- Request metrics

## Usage

```bash
terraform init
terraform plan
terraform apply
```

## Cost Estimation

Monthly costs (us-east-1):
- Storage: Variable based on usage
- Replication: Data transfer + storage in destination region
- KMS: $1/month per key + $0.03 per 10,000 requests
- Requests: Variable based on usage
- Lifecycle transitions: $0.01 per 1,000 transitions
- Inventory: $0.0025 per million objects listed

## Clean Up

```bash
terraform destroy
```
