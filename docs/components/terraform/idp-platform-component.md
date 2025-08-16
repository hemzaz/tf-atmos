# Internal Developer Platform (IDP) Platform Component

This Terraform component deploys a comprehensive Internal Developer Platform infrastructure including EKS clusters, storage buckets, networking, and supporting services.

## Architecture

The IDP platform component creates:
- **EKS Clusters**: Managed Kubernetes clusters with multi-AZ deployment
- **Storage Infrastructure**: S3 buckets for artifacts, logs, documentation, and uploads
- **Networking**: VPC configuration with public/private subnets and security groups
- **Database**: RDS PostgreSQL instance with high availability
- **Security**: KMS encryption, IAM roles, and security groups
- **Monitoring**: CloudWatch integration and logging

## Features

- **Multi-AZ High Availability**: Deployed across multiple availability zones
- **Security Hardened**: Encryption at rest and in transit, least-privilege IAM
- **Cost Optimized**: Intelligent storage lifecycle policies and right-sized instances
- **Observability**: Comprehensive logging and monitoring
- **Scalable**: Auto-scaling groups and load balancing

## Usage

```hcl
# Example configuration in Atmos stack file
components:
  terraform:
    idp-platform:
      vars:
        region: "us-west-2"
        vpc_cidr: "10.0.0.0/16"
        cluster_name: "idp-main"
        cluster_version: "1.28"
        node_instance_types: ["t3.medium", "t3.large"]
        database_instance_class: "db.t3.medium"
        enable_monitoring: true
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| region | AWS region for deployment | `string` | `"us-west-2"` | no |
| vpc_cidr | CIDR block for VPC | `string` | `"10.0.0.0/16"` | no |
| cluster_name | Name of the EKS cluster | `string` | n/a | yes |
| cluster_version | Kubernetes version | `string` | `"1.28"` | no |
| node_instance_types | EC2 instance types for worker nodes | `list(string)` | `["t3.medium"]` | no |
| database_instance_class | RDS instance class | `string` | `"db.t3.medium"` | no |
| enable_monitoring | Enable CloudWatch monitoring | `bool` | `true` | no |
| cluster_endpoint_public_access_cidrs | CIDR blocks for EKS API access | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster_id | EKS cluster ID |
| cluster_endpoint | EKS cluster endpoint |
| cluster_arn | EKS cluster ARN |
| vpc_id | VPC ID |
| private_subnet_ids | Private subnet IDs |
| public_subnet_ids | Public subnet IDs |
| rds_endpoint | RDS endpoint |
| s3_bucket_names | Map of S3 bucket names |
| security_group_ids | Security group IDs |

## Security Considerations

- **Network Isolation**: Private subnets for workloads, public subnets for load balancers only
- **Encryption**: All data encrypted at rest using KMS, in transit using TLS
- **Access Control**: Least-privilege IAM roles and policies
- **API Security**: EKS API server access restricted by default
- **Audit Logging**: CloudTrail and VPC Flow Logs enabled
- **Secrets Management**: Integration with AWS Secrets Manager

## Monitoring and Observability

- CloudWatch metrics and alarms
- VPC Flow Logs
- EKS control plane logging
- Application Load Balancer access logs
- Custom metrics for application health

## Cost Optimization

- Intelligent storage tiering (S3 Lifecycle policies)
- Spot instances for non-critical workloads
- Right-sized instance recommendations
- Reserved capacity planning
- Cost allocation tags

## Dependencies

- VPC component (if not using built-in VPC)
- IAM roles and policies
- KMS keys for encryption
- Route53 hosted zone (if using custom domains)

## Examples

See the `examples/` directory for complete deployment examples including:
- Basic IDP deployment
- Multi-region setup
- High-availability configuration
- Integration with existing VPC

## Troubleshooting

### Common Issues

1. **EKS Cluster Creation Timeout**
   - Check subnet configurations and internet gateway
   - Verify IAM permissions for EKS service role

2. **RDS Connection Issues**
   - Verify security group rules
   - Check subnet group configuration

3. **S3 Access Denied**
   - Review bucket policies and IAM permissions
   - Check for public access blocks

### Debugging

```bash
# Validate configuration
atmos terraform validate idp-platform -s <stack-name>

# Plan deployment
atmos terraform plan idp-platform -s <stack-name>

# Check cluster status
kubectl cluster-info --kubeconfig <kubeconfig-path>
```

## Contributing

When modifying this component:

1. Follow Terraform best practices
2. Update documentation and examples
3. Test changes in a development environment
4. Validate with `terraform validate` and `terraform plan`
5. Update version constraints as needed

## Version History

- **v1.0.0**: Initial release with basic IDP infrastructure
- **v1.1.0**: Added multi-AZ support and enhanced security
- **v1.2.0**: Cost optimization and monitoring improvements