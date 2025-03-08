# TF-Atmos Codebase Issues

This document contains issues that need to be addressed in the codebase, prioritized by severity and category. For feature enhancements and nice-to-have improvements, see TODO.md. For bugs that have been fixed, see BUGS_FIXED.md.

## Critical Reliability Issues

All critical reliability issues have been fixed and moved to BUGS_FIXED.md.

## High Reliability Issues

All high reliability issues have been fixed and moved to BUGS_FIXED.md.

## Critical Usability Issues

All critical usability issues have been fixed and moved to BUGS_FIXED.md.

## Critical Security Vulnerabilities

All critical security vulnerabilities have been fixed and moved to BUGS_FIXED.md.

## High Security Vulnerabilities

1. **Insecure file permissions in credential files**
   - File: `/integrations/atlantis/scripts/assume-role.sh` (Lines 88-94)
   - Issue: Creates AWS credentials file without setting secure file permissions 
   - Evidence: No chmod after creating credentials file
   - Impact: Credentials could be readable by other users on the system
   - Recommendation: Set secure permissions (chmod 600) immediately after file creation

2. **Overpermissive KMS Key Policy**
   - File: `/components/terraform/backend/s3-backend.tf` (Lines 25-37)
   - Issue: The KMS key policy grants full `kms:*` permissions to the root account
   - Evidence: ```
     "Action": "kms:*",
     "Resource": "*"
     ```
   - Impact: Excessive permissions could lead to unauthorized key operations
   - Recommendation: Restrict the KMS policy to only necessary actions like `kms:Encrypt`, `kms:Decrypt`, `kms:ReEncrypt*`, `kms:GenerateDataKey*`, and `kms:DescribeKey`

3. **Hardcoded Redis Connection**
   - File: `/gaia/cli.py` (Lines 35-37)
   - Issue: Hardcoded Redis connection string without authentication
   - Evidence: `broker='redis://localhost:6379/0'`
   - Impact: Potential unauthorized access to task queue and data
   - Recommendation: Use environment variables or configuration file for Redis connection details and add authentication

4. **Hard-coded AWS regions**
   - File: `/gaia/utils.py` (Line 176)
   - Issue: AWS region hard-coded without configurability
   - Impact: Forces operations to use a specific region regardless of user intent
   - Recommendation: Make AWS region configurable through environment or config files

## Performance Issues

All performance issues have been fixed and moved to BUGS_FIXED.md.

## Additional Issues

All additional issues have been fixed and moved to BUGS_FIXED.md.

## Recommended Next Steps

1. **High Priority Security Improvements**
   - Fix hardcoded Redis connection and add authentication
   - Make AWS regions configurable
   - Address overpermissive security policies
   - Set secure permissions for credential files

2. **Medium Priority Improvements**
   - Implement efficient caching for component discovery
   - Consolidate and optimize Terraform dependencies
   - Standardize error handling across all operations

3. **Performance Enhancements**
   - All high-priority performance enhancements have been completed