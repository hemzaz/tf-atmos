#!/usr/bin/env bash
# =============================================================================
# Smoke Tests - Health Checks
# =============================================================================
# Tests health and readiness of deployed infrastructure components

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
ENVIRONMENT="${ENVIRONMENT:-dev}"
TENANT="${TENANT:-fnx}"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Helper functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
test_passed() { echo -e "${GREEN}✓${NC} $1"; ((PASSED++)); }
test_failed() { echo -e "${RED}✗${NC} $1"; ((FAILED++)); }
test_warning() { echo -e "${YELLOW}⚠${NC} $1"; ((WARNINGS++)); }

# Health check functions
check_vpc_health() {
    log_info "Checking VPC health..."

    # Check if VPC exists
    local vpc_count
    vpc_count=$(aws ec2 describe-vpcs \
        --region "$REGION" \
        --filters "Name=tag:Tenant,Values=$TENANT" "Name=tag:Environment,Values=$ENVIRONMENT" \
        --query 'length(Vpcs)' --output text 2>/dev/null || echo "0")

    if [ "$vpc_count" -gt 0 ]; then
        test_passed "VPC exists for $TENANT-$ENVIRONMENT"
    else
        test_warning "No VPC found for $TENANT-$ENVIRONMENT"
        return
    fi

    # Check subnet availability
    local subnet_count
    subnet_count=$(aws ec2 describe-subnets \
        --region "$REGION" \
        --filters "Name=tag:Tenant,Values=$TENANT" \
        --query 'length(Subnets)' --output text 2>/dev/null || echo "0")

    if [ "$subnet_count" -ge 4 ]; then
        test_passed "Sufficient subnets available ($subnet_count)"
    else
        test_warning "Limited subnets available ($subnet_count)"
    fi
}

check_eks_health() {
    log_info "Checking EKS cluster health..."

    # List EKS clusters
    local clusters
    clusters=$(aws eks list-clusters --region "$REGION" --query 'clusters' --output text 2>/dev/null || echo "")

    if [ -z "$clusters" ]; then
        test_warning "No EKS clusters found"
        return
    fi

    # Check each cluster
    for cluster in $clusters; do
        if [[ "$cluster" == *"$TENANT"* ]] && [[ "$cluster" == *"$ENVIRONMENT"* ]]; then
            local status
            status=$(aws eks describe-cluster \
                --region "$REGION" \
                --name "$cluster" \
                --query 'cluster.status' --output text 2>/dev/null || echo "UNKNOWN")

            if [ "$status" = "ACTIVE" ]; then
                test_passed "EKS cluster $cluster is ACTIVE"
            else
                test_failed "EKS cluster $cluster is $status"
            fi
        fi
    done
}

check_rds_health() {
    log_info "Checking RDS instances health..."

    # List RDS instances
    local instances
    instances=$(aws rds describe-db-instances \
        --region "$REGION" \
        --query 'DBInstances[*].DBInstanceIdentifier' --output text 2>/dev/null || echo "")

    if [ -z "$instances" ]; then
        test_warning "No RDS instances found"
        return
    fi

    # Check each instance
    for instance in $instances; do
        if [[ "$instance" == *"$TENANT"* ]] && [[ "$instance" == *"$ENVIRONMENT"* ]]; then
            local status
            status=$(aws rds describe-db-instances \
                --region "$REGION" \
                --db-instance-identifier "$instance" \
                --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || echo "unknown")

            if [ "$status" = "available" ]; then
                test_passed "RDS instance $instance is available"
            else
                test_warning "RDS instance $instance is $status"
            fi
        fi
    done
}

check_alb_health() {
    log_info "Checking ALB health..."

    # List load balancers
    local lbs
    lbs=$(aws elbv2 describe-load-balancers \
        --region "$REGION" \
        --query 'LoadBalancers[*].LoadBalancerArn' --output text 2>/dev/null || echo "")

    if [ -z "$lbs" ]; then
        test_warning "No load balancers found"
        return
    fi

    # Check each load balancer
    for lb_arn in $lbs; do
        local lb_name
        lb_name=$(aws elbv2 describe-load-balancers \
            --region "$REGION" \
            --load-balancer-arns "$lb_arn" \
            --query 'LoadBalancers[0].LoadBalancerName' --output text 2>/dev/null || echo "")

        if [[ "$lb_name" == *"$TENANT"* ]] && [[ "$lb_name" == *"$ENVIRONMENT"* ]]; then
            local state
            state=$(aws elbv2 describe-load-balancers \
                --region "$REGION" \
                --load-balancer-arns "$lb_arn" \
                --query 'LoadBalancers[0].State.Code' --output text 2>/dev/null || echo "unknown")

            if [ "$state" = "active" ]; then
                test_passed "ALB $lb_name is active"
            else
                test_warning "ALB $lb_name is $state"
            fi
        fi
    done
}

check_cloudwatch_alarms() {
    log_info "Checking CloudWatch alarms..."

    # Get alarms in ALARM state
    local alarm_count
    alarm_count=$(aws cloudwatch describe-alarms \
        --region "$REGION" \
        --state-value ALARM \
        --query 'length(MetricAlarms)' --output text 2>/dev/null || echo "0")

    if [ "$alarm_count" -eq 0 ]; then
        test_passed "No alarms in ALARM state"
    else
        test_warning "$alarm_count CloudWatch alarms in ALARM state"
    fi
}

check_s3_buckets() {
    log_info "Checking S3 buckets..."

    # Check for Terraform state bucket
    local state_bucket="${TENANT}-${ENVIRONMENT}-terraform-state"

    if aws s3api head-bucket --bucket "$state_bucket" 2>/dev/null; then
        test_passed "Terraform state bucket exists: $state_bucket"

        # Check bucket encryption
        local encryption
        encryption=$(aws s3api get-bucket-encryption \
            --bucket "$state_bucket" \
            --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
            --output text 2>/dev/null || echo "NONE")

        if [ "$encryption" != "NONE" ]; then
            test_passed "State bucket is encrypted ($encryption)"
        else
            test_warning "State bucket encryption not configured"
        fi
    else
        test_warning "Terraform state bucket not found: $state_bucket"
    fi
}

# Main execution
main() {
    echo "========================================="
    echo "  Smoke Tests - Health Checks"
    echo "========================================="
    echo "Environment: $ENVIRONMENT"
    echo "Tenant: $TENANT"
    echo "Region: $REGION"
    echo "========================================="
    echo

    # Check AWS CLI availability
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found"
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi

    # Run health checks
    check_vpc_health
    echo
    check_eks_health
    echo
    check_rds_health
    echo
    check_alb_health
    echo
    check_cloudwatch_alarms
    echo
    check_s3_buckets

    # Summary
    echo
    echo "========================================="
    echo "  Health Check Summary"
    echo "========================================="
    echo -e "${GREEN}Passed:${NC}   $PASSED"
    echo -e "${RED}Failed:${NC}   $FAILED"
    echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
    echo "========================================="

    # Exit status
    if [ "$FAILED" -gt 0 ]; then
        log_error "Health checks failed"
        exit 1
    elif [ "$WARNINGS" -gt 0 ]; then
        log_warning "Health checks completed with warnings"
        exit 0
    else
        log_info "All health checks passed"
        exit 0
    fi
}

main "$@"
