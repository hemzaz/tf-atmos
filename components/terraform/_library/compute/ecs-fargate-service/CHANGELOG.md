# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-12-02

### Added
- Initial release of ECS Fargate Service module
- Complete ECS Fargate service with cluster creation
- Auto-scaling support (CPU, memory, ALB request count)
- Blue-green deployment via AWS CodeDeploy
- Deployment circuit breaker for automatic rollback
- Service discovery via AWS Cloud Map
- Load balancer integration (ALB/NLB)
- CloudWatch Container Insights
- CloudWatch Logs integration
- ECS Exec support for debugging
- AWS X-Ray tracing support
- Secrets management (Secrets Manager, SSM Parameter Store)
- IAM roles with least privilege
- Fargate Spot support for cost optimization
- EFS volume support for persistent storage
- Security group management
- Comprehensive variable validation
- Complete examples (basic, complete, blue-green)
- Production-ready defaults
- Cost optimization features
- Comprehensive outputs
