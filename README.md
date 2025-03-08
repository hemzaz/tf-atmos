# Terraform Atmos Toolchain

This project provides enterprise-grade tools for deploying and managing infrastructure with Terraform and Atmos.

## Overview

The toolchain includes:

- High-performance component discovery with intelligent caching
- Dependency resolution and management with cycle detection
- Environment onboarding and configuration with templates
- Advanced drift detection and remediation
- State lock management with safety mechanisms
- Secure certificate handling and rotation
- Thread-safe operations for concurrent tasks

## Installation

### Quick Setup

```bash
# Clone the repository
git clone https://github.com/example/tf-atmos.git
cd tf-atmos

# Install the package with dependencies
pip install -e .

# Optional: Start Redis for async operations (recommended for production)
# Redis connection is automatically validated - falls back to local execution if unavailable
brew install redis  # or apt-get install redis-server
brew services start redis
```

### Requirements

- Python 3.11+
- Terraform 1.11.0
- Atmos CLI 1.163.0+

See `requirements.txt` for complete Python dependencies.

## Usage

Use the Atmos workflows to manage your infrastructure. For detailed documentation on Gaia (the Python implementation), see [gaia/README.md](./gaia/README.md).

```bash
# Apply an environment
atmos workflow apply-environment tenant=acme account=prod environment=use1

# Plan an environment with drift detection
atmos workflow plan-environment tenant=acme account=prod environment=use1 detect_drift=true

# Validate components
atmos workflow validate tenant=acme account=prod environment=use1
```

## Directory Structure

- **gaia/**: Python implementation for Atmos workflows
- **bin/**: Executable scripts
- **scripts/**: Utility scripts
  - **certificates/**: Certificate management
  - **templates/**: Template files
- **workflows/**: Atmos workflow definitions
- **components/**: Terraform components
- **stacks/**: Atmos stack configurations

## Key Features

### Atmos Workflows

The toolchain provides pre-defined Atmos workflows for common operations:

```bash
# Apply a complete environment
atmos workflow apply-environment tenant=acme account=prod environment=use1

# Plan changes with drift detection
atmos workflow plan-environment tenant=acme account=prod environment=use1 detect_drift=true

# Validate components
atmos workflow validate tenant=acme account=prod environment=use1

# Onboard a new environment
atmos workflow onboard-environment tenant=acme account=prod environment=use1 vpc_cidr=10.0.0.0/16

# Detect infrastructure drift
atmos workflow drift-detection tenant=acme account=prod environment=use1
```

### Environment Management

Create and manage environments using standard workflows:

```bash
# Onboard a new environment
atmos workflow onboard-environment tenant=acme account=prod environment=use1 vpc_cidr=10.0.0.0/16

# Update an existing environment configuration
atmos workflow update-environment-template tenant=acme account=prod environment=use1
```

### Configuration

The toolchain can be configured through environment variables or configuration files:
- `.atmos.env` in project root
- `.env` in project root
- `~/.atmos/config`

## Recent Improvements

- **Performance**: Implemented intelligent caching, memory limits, and optimized dependencies
- **Security**: Fixed all critical security vulnerabilities including command injection issues
- **Reliability**: Added proper error handling, retry mechanisms, and validation
- **Usability**: Improved workflow interface and configuration
- **Maintainability**: Standardized interfaces and consolidated utilities

## License

MIT