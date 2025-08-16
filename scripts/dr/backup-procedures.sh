#!/usr/bin/env bash
# Comprehensive Backup Procedures for IDP Platform
# This script implements automated backup procedures with validation and monitoring

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/backup-config.yaml"
LOG_FILE="${SCRIPT_DIR}/../../logs/backup-$(date +%Y%m%d-%H%M%S).log"
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-30}
S3_BACKUP_BUCKET=${S3_BACKUP_BUCKET:-"idp-platform-backups"}
BACKUP_ENCRYPTION_KEY=${BACKUP_ENCRYPTION_KEY:-""}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

# Error handling
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Backup operation failed with exit code $exit_code"
        send_alert "BACKUP_FAILED" "Backup operation failed. Check logs: $LOG_FILE"
    fi
    
    # Cleanup temporary files
    rm -rf /tmp/idp-backup-*
}

trap cleanup EXIT

# Validation functions
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    local required_tools=("kubectl" "velero" "aws" "pg_dump" "redis-cli" "tar" "gzip")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is not installed"
            return 1
        fi
    done
    
    # Validate AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured"
        return 1
    fi
    
    # Validate kubectl access
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot access Kubernetes cluster"
        return 1
    fi
    
    # Validate Velero installation
    if ! velero version &> /dev/null; then
        log_error "Velero is not properly configured"
        return 1
    fi
    
    log_success "All prerequisites validated"
    return 0
}

# Alert function
send_alert() {
    local alert_type=$1
    local message=$2
    
    # Send to CloudWatch
    aws cloudwatch put-metric-data \
        --namespace "IDP/Backup" \
        --metric-data MetricName="$alert_type",Value=1,Unit=Count \
        --region "${AWS_DEFAULT_REGION:-us-east-1}" || true
    
    # Send Slack notification if webhook is configured
    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"🚨 IDP Backup Alert: $message\"}" \
            "$SLACK_WEBHOOK_URL" || true
    fi
    
    # Send SNS notification if topic is configured
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        aws sns publish \
            --topic-arn "$SNS_TOPIC_ARN" \
            --message "$message" \
            --subject "IDP Backup Alert: $alert_type" || true
    fi
}

# Database backup functions
backup_postgresql() {
    log_info "Starting PostgreSQL backup..."
    
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="postgresql-backup-${timestamp}.sql.gz"
    local s3_key="database/postgresql/${backup_file}"
    
    # Get database connection details
    local db_host=$(kubectl get secret database-credentials -n idp-system -o jsonpath='{.data.host}' | base64 -d)
    local db_port=$(kubectl get secret database-credentials -n idp-system -o jsonpath='{.data.port}' | base64 -d)
    local db_name=$(kubectl get secret database-credentials -n idp-system -o jsonpath='{.data.database}' | base64 -d)
    local db_user=$(kubectl get secret database-credentials -n idp-system -o jsonpath='{.data.username}' | base64 -d)
    local db_password=$(kubectl get secret database-credentials -n idp-system -o jsonpath='{.data.password}' | base64 -d)
    
    # Create backup
    PGPASSWORD="$db_password" pg_dump \
        -h "$db_host" \
        -p "$db_port" \
        -U "$db_user" \
        -d "$db_name" \
        --verbose \
        --no-owner \
        --no-privileges \
        --format=custom \
        --compress=9 | gzip > "/tmp/${backup_file}"
    
    # Verify backup integrity
    if gzip -t "/tmp/${backup_file}"; then
        log_success "PostgreSQL backup created successfully"
    else
        log_error "PostgreSQL backup verification failed"
        return 1
    fi
    
    # Upload to S3
    if [[ -n "$BACKUP_ENCRYPTION_KEY" ]]; then
        aws s3 cp "/tmp/${backup_file}" "s3://${S3_BACKUP_BUCKET}/${s3_key}" \
            --server-side-encryption aws:kms \
            --ssekms-key-id "$BACKUP_ENCRYPTION_KEY" \
            --metadata "backup-type=postgresql,timestamp=${timestamp}"
    else
        aws s3 cp "/tmp/${backup_file}" "s3://${S3_BACKUP_BUCKET}/${s3_key}" \
            --server-side-encryption AES256 \
            --metadata "backup-type=postgresql,timestamp=${timestamp}"
    fi
    
    # Create backup manifest
    cat > "/tmp/postgresql-manifest-${timestamp}.json" << EOF
{
    "backup_type": "postgresql",
    "timestamp": "${timestamp}",
    "file_name": "${backup_file}",
    "s3_location": "s3://${S3_BACKUP_BUCKET}/${s3_key}",
    "database_name": "${db_name}",
    "backup_size": $(stat -f%z "/tmp/${backup_file}" 2>/dev/null || stat -c%s "/tmp/${backup_file}"),
    "checksum": "$(sha256sum "/tmp/${backup_file}" | cut -d' ' -f1)"
}
EOF
    
    aws s3 cp "/tmp/postgresql-manifest-${timestamp}.json" \
        "s3://${S3_BACKUP_BUCKET}/manifests/postgresql-manifest-${timestamp}.json"
    
    # Cleanup local files
    rm -f "/tmp/${backup_file}" "/tmp/postgresql-manifest-${timestamp}.json"
    
    log_success "PostgreSQL backup completed: s3://${S3_BACKUP_BUCKET}/${s3_key}"
    return 0
}

backup_redis() {
    log_info "Starting Redis backup..."
    
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="redis-backup-${timestamp}.rdb.gz"
    local s3_key="redis/${backup_file}"
    
    # Get Redis connection details
    local redis_host=$(kubectl get secret redis-credentials -n idp-system -o jsonpath='{.data.host}' | base64 -d)
    local redis_port=$(kubectl get secret redis-credentials -n idp-system -o jsonpath='{.data.port}' | base64 -d)
    local redis_password=$(kubectl get secret redis-credentials -n idp-system -o jsonpath='{.data.password}' | base64 -d)
    
    # Create Redis dump
    redis-cli -h "$redis_host" -p "$redis_port" -a "$redis_password" \
        --rdb "/tmp/redis-dump-${timestamp}.rdb"
    
    # Compress backup
    gzip "/tmp/redis-dump-${timestamp}.rdb"
    mv "/tmp/redis-dump-${timestamp}.rdb.gz" "/tmp/${backup_file}"
    
    # Upload to S3
    if [[ -n "$BACKUP_ENCRYPTION_KEY" ]]; then
        aws s3 cp "/tmp/${backup_file}" "s3://${S3_BACKUP_BUCKET}/${s3_key}" \
            --server-side-encryption aws:kms \
            --ssekms-key-id "$BACKUP_ENCRYPTION_KEY" \
            --metadata "backup-type=redis,timestamp=${timestamp}"
    else
        aws s3 cp "/tmp/${backup_file}" "s3://${S3_BACKUP_BUCKET}/${s3_key}" \
            --server-side-encryption AES256 \
            --metadata "backup-type=redis,timestamp=${timestamp}"
    fi
    
    # Create backup manifest
    cat > "/tmp/redis-manifest-${timestamp}.json" << EOF
{
    "backup_type": "redis",
    "timestamp": "${timestamp}",
    "file_name": "${backup_file}",
    "s3_location": "s3://${S3_BACKUP_BUCKET}/${s3_key}",
    "backup_size": $(stat -f%z "/tmp/${backup_file}" 2>/dev/null || stat -c%s "/tmp/${backup_file}"),
    "checksum": "$(sha256sum "/tmp/${backup_file}" | cut -d' ' -f1)"
}
EOF
    
    aws s3 cp "/tmp/redis-manifest-${timestamp}.json" \
        "s3://${S3_BACKUP_BUCKET}/manifests/redis-manifest-${timestamp}.json"
    
    # Cleanup local files
    rm -f "/tmp/${backup_file}" "/tmp/redis-manifest-${timestamp}.json"
    
    log_success "Redis backup completed: s3://${S3_BACKUP_BUCKET}/${s3_key}"
    return 0
}

# Kubernetes backup functions
backup_kubernetes() {
    log_info "Starting Kubernetes backup with Velero..."
    
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_name="idp-platform-${timestamp}"
    
    # Create Velero backup
    velero backup create "$backup_name" \
        --include-namespaces=idp-system,monitoring,istio-system,external-secrets-system \
        --default-volumes-to-fs-backup \
        --snapshot-volumes \
        --ttl 720h0m0s \
        --wait
    
    # Wait for backup completion and verify
    local backup_status
    local max_attempts=60
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        backup_status=$(velero backup get "$backup_name" -o json | jq -r '.status.phase')
        
        if [[ "$backup_status" == "Completed" ]]; then
            log_success "Kubernetes backup completed successfully: $backup_name"
            break
        elif [[ "$backup_status" == "Failed" ]] || [[ "$backup_status" == "PartiallyFailed" ]]; then
            log_error "Kubernetes backup failed or partially failed: $backup_name"
            velero backup describe "$backup_name"
            return 1
        fi
        
        log_info "Waiting for backup to complete... Status: $backup_status (Attempt $((attempt+1))/$max_attempts)"
        sleep 30
        ((attempt++))
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        log_error "Kubernetes backup timed out: $backup_name"
        return 1
    fi
    
    # Create backup report
    velero backup describe "$backup_name" --details > "/tmp/k8s-backup-report-${timestamp}.txt"
    aws s3 cp "/tmp/k8s-backup-report-${timestamp}.txt" \
        "s3://${S3_BACKUP_BUCKET}/reports/k8s-backup-report-${timestamp}.txt"
    rm -f "/tmp/k8s-backup-report-${timestamp}.txt"
    
    return 0
}

# Configuration backup functions
backup_configurations() {
    log_info "Starting configuration backup..."
    
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_dir="/tmp/idp-config-backup-${timestamp}"
    local backup_file="config-backup-${timestamp}.tar.gz"
    local s3_key="configurations/${backup_file}"
    
    mkdir -p "$backup_dir"
    
    # Backup Kubernetes configurations
    kubectl get all --all-namespaces -o yaml > "$backup_dir/all-resources.yaml"
    kubectl get configmaps --all-namespaces -o yaml > "$backup_dir/configmaps.yaml"
    kubectl get secrets --all-namespaces -o yaml > "$backup_dir/secrets.yaml"
    kubectl get networkpolicies --all-namespaces -o yaml > "$backup_dir/networkpolicies.yaml"
    kubectl get ingresses --all-namespaces -o yaml > "$backup_dir/ingresses.yaml"
    
    # Backup Velero configurations
    velero backup-location get -o yaml > "$backup_dir/velero-backup-locations.yaml"
    velero volume-snapshot-location get -o yaml > "$backup_dir/velero-snapshot-locations.yaml"
    
    # Backup monitoring configurations
    kubectl get prometheus,alertmanager,grafana --all-namespaces -o yaml > "$backup_dir/monitoring-configs.yaml" || true
    
    # Backup custom resources
    kubectl get externalsecrets --all-namespaces -o yaml > "$backup_dir/external-secrets.yaml" || true
    kubectl get servicemonitors --all-namespaces -o yaml > "$backup_dir/service-monitors.yaml" || true
    
    # Create tarball
    tar -czf "/tmp/${backup_file}" -C "/tmp" "idp-config-backup-${timestamp}"
    
    # Upload to S3
    if [[ -n "$BACKUP_ENCRYPTION_KEY" ]]; then
        aws s3 cp "/tmp/${backup_file}" "s3://${S3_BACKUP_BUCKET}/${s3_key}" \
            --server-side-encryption aws:kms \
            --ssekms-key-id "$BACKUP_ENCRYPTION_KEY" \
            --metadata "backup-type=configurations,timestamp=${timestamp}"
    else
        aws s3 cp "/tmp/${backup_file}" "s3://${S3_BACKUP_BUCKET}/${s3_key}" \
            --server-side-encryption AES256 \
            --metadata "backup-type=configurations,timestamp=${timestamp}"
    fi
    
    # Create backup manifest
    cat > "/tmp/config-manifest-${timestamp}.json" << EOF
{
    "backup_type": "configurations",
    "timestamp": "${timestamp}",
    "file_name": "${backup_file}",
    "s3_location": "s3://${S3_BACKUP_BUCKET}/${s3_key}",
    "backup_size": $(stat -f%z "/tmp/${backup_file}" 2>/dev/null || stat -c%s "/tmp/${backup_file}"),
    "checksum": "$(sha256sum "/tmp/${backup_file}" | cut -d' ' -f1)"
}
EOF
    
    aws s3 cp "/tmp/config-manifest-${timestamp}.json" \
        "s3://${S3_BACKUP_BUCKET}/manifests/config-manifest-${timestamp}.json"
    
    # Cleanup local files
    rm -rf "$backup_dir" "/tmp/${backup_file}" "/tmp/config-manifest-${timestamp}.json"
    
    log_success "Configuration backup completed: s3://${S3_BACKUP_BUCKET}/${s3_key}"
    return 0
}

# Cleanup old backups
cleanup_old_backups() {
    log_info "Cleaning up old backups..."
    
    # Calculate cutoff date
    local cutoff_date
    if [[ "$OSTYPE" == "darwin"* ]]; then
        cutoff_date=$(date -v-${BACKUP_RETENTION_DAYS}d '+%Y-%m-%d')
    else
        cutoff_date=$(date -d "${BACKUP_RETENTION_DAYS} days ago" '+%Y-%m-%d')
    fi
    
    # Cleanup S3 backups older than retention period
    aws s3api list-objects-v2 \
        --bucket "$S3_BACKUP_BUCKET" \
        --query "Contents[?LastModified<'${cutoff_date}'].Key" \
        --output text | \
    while read -r key; do
        if [[ -n "$key" && "$key" != "None" ]]; then
            log_info "Deleting old backup: $key"
            aws s3 rm "s3://${S3_BACKUP_BUCKET}/${key}"
        fi
    done
    
    # Cleanup old Velero backups
    local old_backups
    old_backups=$(velero backup get --output json | \
        jq -r ".items[] | select(.metadata.creationTimestamp < \"${cutoff_date}\") | .metadata.name")
    
    for backup in $old_backups; do
        if [[ -n "$backup" ]]; then
            log_info "Deleting old Velero backup: $backup"
            velero backup delete "$backup" --confirm
        fi
    done
    
    log_success "Old backup cleanup completed"
}

# Generate backup report
generate_backup_report() {
    log_info "Generating backup report..."
    
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local report_file="/tmp/backup-report-${timestamp}.json"
    
    # Get backup statistics
    local s3_backups=$(aws s3api list-objects-v2 --bucket "$S3_BACKUP_BUCKET" --query 'length(Contents)')
    local velero_backups=$(velero backup get --output json | jq '.items | length')
    local total_size=$(aws s3api list-objects-v2 --bucket "$S3_BACKUP_BUCKET" --query 'sum(Contents[].Size)')
    
    # Create report
    cat > "$report_file" << EOF
{
    "report_timestamp": "${timestamp}",
    "backup_summary": {
        "s3_backups": ${s3_backups:-0},
        "velero_backups": ${velero_backups:-0},
        "total_size_bytes": ${total_size:-0},
        "retention_days": ${BACKUP_RETENTION_DAYS}
    },
    "backup_locations": {
        "s3_bucket": "${S3_BACKUP_BUCKET}",
        "velero_provider": "aws"
    },
    "last_backup_status": {
        "postgresql": "$(test -f /tmp/postgresql-success && echo "success" || echo "unknown")",
        "redis": "$(test -f /tmp/redis-success && echo "success" || echo "unknown")",
        "kubernetes": "$(test -f /tmp/k8s-success && echo "success" || echo "unknown")",
        "configurations": "$(test -f /tmp/config-success && echo "success" || echo "unknown")"
    }
}
EOF
    
    # Upload report
    aws s3 cp "$report_file" "s3://${S3_BACKUP_BUCKET}/reports/backup-report-${timestamp}.json"
    
    # Send metrics to CloudWatch
    aws cloudwatch put-metric-data \
        --namespace "IDP/Backup" \
        --metric-data \
        MetricName=S3Backups,Value=${s3_backups:-0},Unit=Count \
        MetricName=VeleroBackups,Value=${velero_backups:-0},Unit=Count \
        MetricName=TotalBackupSize,Value=${total_size:-0},Unit=Bytes \
        --region "${AWS_DEFAULT_REGION:-us-east-1}"
    
    rm -f "$report_file"
    log_success "Backup report generated and uploaded"
}

# Main backup function
main() {
    local backup_type=${1:-"full"}
    
    log_info "Starting IDP Platform backup - Type: $backup_type"
    
    # Validate prerequisites
    if ! validate_prerequisites; then
        log_error "Prerequisites validation failed"
        exit 1
    fi
    
    # Create success markers directory
    mkdir -p /tmp
    
    # Perform backups based on type
    case "$backup_type" in
        "full")
            log_info "Performing full backup..."
            
            if backup_postgresql; then
                touch /tmp/postgresql-success
                send_alert "POSTGRESQL_BACKUP_SUCCESS" "PostgreSQL backup completed successfully"
            else
                send_alert "POSTGRESQL_BACKUP_FAILED" "PostgreSQL backup failed"
            fi
            
            if backup_redis; then
                touch /tmp/redis-success
                send_alert "REDIS_BACKUP_SUCCESS" "Redis backup completed successfully"
            else
                send_alert "REDIS_BACKUP_FAILED" "Redis backup failed"
            fi
            
            if backup_kubernetes; then
                touch /tmp/k8s-success
                send_alert "K8S_BACKUP_SUCCESS" "Kubernetes backup completed successfully"
            else
                send_alert "K8S_BACKUP_FAILED" "Kubernetes backup failed"
            fi
            
            if backup_configurations; then
                touch /tmp/config-success
                send_alert "CONFIG_BACKUP_SUCCESS" "Configuration backup completed successfully"
            else
                send_alert "CONFIG_BACKUP_FAILED" "Configuration backup failed"
            fi
            ;;
            
        "database")
            if backup_postgresql && backup_redis; then
                send_alert "DATABASE_BACKUP_SUCCESS" "Database backup completed successfully"
            else
                send_alert "DATABASE_BACKUP_FAILED" "Database backup failed"
            fi
            ;;
            
        "kubernetes")
            if backup_kubernetes; then
                send_alert "K8S_BACKUP_SUCCESS" "Kubernetes backup completed successfully"
            else
                send_alert "K8S_BACKUP_FAILED" "Kubernetes backup failed"
            fi
            ;;
            
        "config")
            if backup_configurations; then
                send_alert "CONFIG_BACKUP_SUCCESS" "Configuration backup completed successfully"
            else
                send_alert "CONFIG_BACKUP_FAILED" "Configuration backup failed"
            fi
            ;;
            
        *)
            log_error "Invalid backup type: $backup_type"
            echo "Usage: $0 [full|database|kubernetes|config]"
            exit 1
            ;;
    esac
    
    # Cleanup old backups
    cleanup_old_backups
    
    # Generate report
    generate_backup_report
    
    log_success "Backup operation completed successfully"
    send_alert "BACKUP_COMPLETED" "IDP Platform backup completed successfully"
}

# Run main function with arguments
main "$@"