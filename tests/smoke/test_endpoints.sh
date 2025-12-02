#!/usr/bin/env bash
# =============================================================================
# Smoke Tests - Endpoint Availability
# =============================================================================
# Tests basic endpoint availability and health checks

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT="${ENVIRONMENT:-dev}"
TENANT="${TENANT:-fnx}"
TIMEOUT=10

# Test results
PASSED=0
FAILED=0
SKIPPED=0

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

test_passed() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

test_failed() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

test_skipped() {
    echo -e "${YELLOW}○${NC} $1"
    ((SKIPPED++))
}

# Test functions
test_http_endpoint() {
    local name="$1"
    local url="$2"
    local expected_status="${3:-200}"

    log_info "Testing endpoint: $name"

    if ! command -v curl &> /dev/null; then
        test_skipped "$name - curl not available"
        return
    fi

    local response_code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" "$url" 2>/dev/null || echo "000")

    if [ "$response_code" = "$expected_status" ]; then
        test_passed "$name - HTTP $response_code"
    elif [ "$response_code" = "000" ]; then
        test_failed "$name - Connection failed or timeout"
    else
        test_failed "$name - Expected HTTP $expected_status, got $response_code"
    fi
}

test_tcp_endpoint() {
    local name="$1"
    local host="$2"
    local port="$3"

    log_info "Testing TCP endpoint: $name"

    if timeout "$TIMEOUT" bash -c "cat < /dev/null > /dev/tcp/$host/$port" 2>/dev/null; then
        test_passed "$name - TCP connection successful"
    else
        test_failed "$name - TCP connection failed"
    fi
}

test_dns_resolution() {
    local name="$1"
    local hostname="$2"

    log_info "Testing DNS resolution: $name"

    if ! command -v dig &> /dev/null && ! command -v nslookup &> /dev/null; then
        test_skipped "$name - DNS tools not available"
        return
    fi

    if command -v dig &> /dev/null; then
        if dig +short "$hostname" | grep -q .; then
            test_passed "$name - DNS resolution successful"
        else
            test_failed "$name - DNS resolution failed"
        fi
    elif command -v nslookup &> /dev/null; then
        if nslookup "$hostname" &> /dev/null; then
            test_passed "$name - DNS resolution successful"
        else
            test_failed "$name - DNS resolution failed"
        fi
    fi
}

test_aws_service_endpoint() {
    local service="$1"
    local region="${AWS_DEFAULT_REGION:-us-east-1}"

    log_info "Testing AWS service endpoint: $service"

    if ! command -v aws &> /dev/null; then
        test_skipped "$service - AWS CLI not available"
        return
    fi

    case "$service" in
        "ec2")
            if aws ec2 describe-instances --region "$region" --max-results 1 &>/dev/null; then
                test_passed "$service - Service accessible"
            else
                test_failed "$service - Service not accessible"
            fi
            ;;
        "s3")
            if aws s3 ls &>/dev/null; then
                test_passed "$service - Service accessible"
            else
                test_failed "$service - Service not accessible"
            fi
            ;;
        "eks")
            if aws eks list-clusters --region "$region" &>/dev/null; then
                test_passed "$service - Service accessible"
            else
                test_failed "$service - Service not accessible"
            fi
            ;;
        "rds")
            if aws rds describe-db-instances --region "$region" --max-records 1 &>/dev/null; then
                test_passed "$service - Service accessible"
            else
                test_failed "$service - Service not accessible"
            fi
            ;;
        *)
            test_skipped "$service - Unknown service"
            ;;
    esac
}

# Main test execution
main() {
    echo "========================================="
    echo "  Smoke Tests - Endpoint Availability"
    echo "========================================="
    echo "Environment: $ENVIRONMENT"
    echo "Tenant: $TENANT"
    echo "Timeout: ${TIMEOUT}s"
    echo "========================================="
    echo

    # Test AWS service endpoints
    log_info "Testing AWS Service Endpoints..."
    test_aws_service_endpoint "ec2"
    test_aws_service_endpoint "s3"
    test_aws_service_endpoint "eks"
    test_aws_service_endpoint "rds"
    echo

    # Test DNS resolution for common AWS services
    log_info "Testing AWS DNS Resolution..."
    test_dns_resolution "EC2 API" "ec2.${AWS_DEFAULT_REGION:-us-east-1}.amazonaws.com"
    test_dns_resolution "S3 API" "s3.${AWS_DEFAULT_REGION:-us-east-1}.amazonaws.com"
    test_dns_resolution "EKS API" "eks.${AWS_DEFAULT_REGION:-us-east-1}.amazonaws.com"
    echo

    # Test VPC endpoints if configured
    if [ -n "${VPC_ENDPOINT_S3:-}" ]; then
        log_info "Testing VPC Endpoints..."
        test_dns_resolution "S3 VPC Endpoint" "$VPC_ENDPOINT_S3"
    fi

    # Summary
    echo
    echo "========================================="
    echo "  Test Summary"
    echo "========================================="
    echo -e "${GREEN}Passed:${NC}  $PASSED"
    echo -e "${RED}Failed:${NC}  $FAILED"
    echo -e "${YELLOW}Skipped:${NC} $SKIPPED"
    echo "========================================="

    # Exit with error if any tests failed
    if [ "$FAILED" -gt 0 ]; then
        exit 1
    fi
}

main "$@"
