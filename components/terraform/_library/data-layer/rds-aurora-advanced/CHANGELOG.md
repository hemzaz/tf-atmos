# Changelog

All notable changes to the rds-aurora-advanced module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-12-02

### Added
- Initial release of RDS Aurora Advanced module
- Multi-AZ Aurora cluster deployment
- Aurora Serverless v2 support with auto-scaling
- Read replica auto-scaling based on CPU and connections
- Performance Insights with configurable retention
- Enhanced Monitoring with 1-60 second granularity
- Automatic secret rotation using AWS Secrets Manager
- Cross-region read replicas via Global Database
- Comprehensive parameter group tuning for PostgreSQL and MySQL
- KMS encryption for storage and Performance Insights
- IAM database authentication
- CloudWatch alarms for CPU, memory, and connections
- Complete backup configuration with retention
- Security group management with validation
- Deletion protection for production safety
- Cost optimization features
- Detailed outputs including connection strings

### Security
- Encryption at rest enabled by default
- Encryption in transit enforced via parameter groups
- Secrets Manager integration for credential management
- Automatic password rotation
- IAM database authentication support
- Deletion protection enabled by default

### Performance
- Optimized parameter groups for PostgreSQL and MySQL
- Performance Insights for query analysis
- Enhanced Monitoring for OS metrics
- Auto-scaling read replicas
- Serverless v2 for automatic capacity scaling

### Cost
- Estimated monthly cost: $280-800 depending on configuration
- Auto-scaling to reduce costs during low usage
- Serverless v2 option for variable workloads
- Configurable backup retention
