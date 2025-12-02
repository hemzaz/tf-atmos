# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-12-02

### Added
- Initial release of vpc-advanced module
- Multi-AZ VPC with public, private, and database subnets
- NAT Gateway support (single or per-AZ)
- Internet Gateway for public subnets
- VPC Flow Logs (CloudWatch or S3)
- VPN Gateway support (optional)
- Transit Gateway attachment support (optional)
- VPC Endpoints support (Gateway and Interface types)
- IPv6 support (optional)
- Custom DHCP options set (optional)
- Default security group management
- Database subnet group creation
- Comprehensive resource tagging
- Complete working examples (simple and complete)
- Full input validation
- Detailed documentation

### Features
- Automatic subnet tier mapping for VPC endpoints
- Flexible route table configuration
- Per-AZ or shared NAT Gateway options
- Flow logs IAM role and policy management
- Support for both CloudWatch and S3 flow logs destinations
- Transit Gateway route propagation
- Comprehensive outputs for all created resources

### Documentation
- Complete README with usage examples
- Two working examples (simple and complete)
- Input and output documentation
- Best practices guide
- Known issues and troubleshooting
- Cost estimation guidance
