# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-12-02

### Added
- Initial release of s3-bucket module
- Server-side encryption support (SSE-S3, SSE-KMS, DSSE-KMS)
- Versioning with optional MFA delete
- Comprehensive lifecycle policies (transitions, expiration)
- Cross-region and same-region replication
- Bucket access logging
- Public access block controls
- Bucket policies (custom or public read)
- CORS configuration
- Static website hosting
- Object lock for compliance
- Intelligent-Tiering configuration
- Event notifications (SNS, SQS, Lambda)
- S3 inventory configuration
- Request metrics
- Full input validation
- Comprehensive outputs
- Complete examples (simple and complete)

### Features
- Automatic tag management
- Support for all major storage classes
- Flexible lifecycle rules with multiple transitions
- Multi-destination replication
- Integration with KMS for encryption
- Website hosting with custom index/error documents
- Inventory reports in Parquet format
- Metric collection for monitoring

### Security
- Public access blocked by default
- Encryption enabled by default
- Support for MFA delete
- Object lock for immutable storage
- Secure replication with KMS

### Documentation
- Complete README with usage examples
- Two working examples (simple and website)
- Input and output documentation
- Best practices guide
- Cost optimization recommendations
