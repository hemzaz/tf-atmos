# Changelog

## [1.0.0] - 2025-12-02

### Added
- Initial release of Lambda Pattern Library module
- Support for 5 deployment patterns: REST API, Event-Driven, Stream Processing, Scheduled, VPC-Integrated
- API Gateway integration (REST and HTTP APIs)
- EventBridge rules for scheduled and event-driven patterns
- SQS queue processing with batch configuration
- SNS topic subscription support
- Kinesis and DynamoDB Streams processing
- Lambda Function URLs for public HTTPS endpoints
- Provisioned concurrency for consistent performance
- Dead Letter Queue for failed invocations
- AWS X-Ray tracing support
- CloudWatch Logs with configurable retention
- VPC integration for private resource access
- EFS file system support for persistent storage
- Lambda layers management
- Secrets Manager and SSM Parameter Store integration
- Code signing configuration
- SnapStart support for Java/Kotlin (faster cold starts)
- Comprehensive IAM role management
- Cost optimization features
- Multiple runtime support (Python, Node.js, Java, Go, .NET, Ruby)
- ARM64 architecture support for cost savings
- Complete examples for all patterns
