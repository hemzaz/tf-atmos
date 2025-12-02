#!/bin/bash
#
# Module Recommendation Engine
# Recommends modules based on use case
#

set -e

USE_CASE=$1

if [ -z "$USE_CASE" ]; then
    echo "Usage: $0 <use-case>"
    echo ""
    echo "Available use cases:"
    echo "  web-app         - Traditional web application"
    echo "  api             - REST/HTTP API"
    echo "  microservices   - Microservices platform"
    echo "  data-pipeline   - Data processing pipeline"
    echo "  streaming       - Real-time streaming"
    echo "  ml              - Machine learning platform"
    echo "  saas            - SaaS multi-tenant"
    exit 1
fi

case $USE_CASE in
    "web-app"|"webapp")
        echo "vpc,securitygroup,iam,eks,eks-addons,rds,acm,secretsmanager,monitoring"
        ;;
    "api"|"serverless")
        echo "apigateway,lambda,iam,secretsmanager,monitoring"
        ;;
    "microservices")
        echo "vpc,securitygroup,iam,eks,eks-addons,rds,apigateway,secretsmanager,monitoring"
        ;;
    "data-pipeline"|"analytics")
        echo "vpc,iam,s3,glue,athena,monitoring"
        ;;
    "streaming"|"real-time")
        echo "vpc,kinesis,lambda,s3,monitoring"
        ;;
    "ml"|"machine-learning")
        echo "vpc,securitygroup,iam,sagemaker,s3,rds,monitoring"
        ;;
    "saas"|"multi-tenant")
        echo "vpc,securitygroup,iam,eks,eks-addons,rds,cognito,apigateway,monitoring"
        ;;
    *)
        echo "Unknown use case: $USE_CASE"
        exit 1
        ;;
esac
