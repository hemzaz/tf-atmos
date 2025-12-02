# SaaS Multi-Tenant Blueprint

Multi-tenant SaaS platform with tenant isolation.

## Architecture

```
                         ┌─────────────────────────────┐
                         │     Control Plane           │
                         │  ┌─────────┐  ┌─────────┐  │
                         │  │ Tenant  │  │Billing  │  │
                         │  │  Mgmt   │  │ System  │  │
                         │  └─────────┘  └─────────┘  │
                         └─────────────┬───────────────┘
                                       │
    ┌──────────────────────────────────┼──────────────────────────────────┐
    │                                  │                                  │
    │              Application Plane   │                                  │
    │                                  ▼                                  │
    │    ┌─────────────────────────────────────────────────────────┐     │
    │    │                    API Gateway                          │     │
    │    │              (Tenant-aware routing)                     │     │
    │    └─────────────────────────┬───────────────────────────────┘     │
    │                              │                                      │
    │    ┌─────────────────────────┼─────────────────────────┐           │
    │    │                         │                         │           │
    │    │     Standard Tier       │     Premium Tier        │           │
    │    │  ┌─────────────────┐    │  ┌─────────────────┐   │           │
    │    │  │  Shared Nodes   │    │  │ Dedicated Nodes │   │           │
    │    │  │   (Pooled)      │    │  │   (Siloed)      │   │           │
    │    │  └─────────────────┘    │  └─────────────────┘   │           │
    │    │                         │                         │           │
    │    └─────────────────────────┼─────────────────────────┘           │
    │                              │                                      │
    └──────────────────────────────┼──────────────────────────────────────┘
                                   │
    ┌──────────────────────────────┼──────────────────────────────────────┐
    │                              │                                      │
    │              Data Plane      │                                      │
    │                              ▼                                      │
    │    ┌─────────────────────────────────────────────────────────┐     │
    │    │              Shared Database (RLS)                      │     │
    │    │    ┌─────────┐  ┌─────────┐  ┌─────────┐              │     │
    │    │    │Tenant A │  │Tenant B │  │Tenant C │              │     │
    │    │    │  Data   │  │  Data   │  │  Data   │              │     │
    │    │    └─────────┘  └─────────┘  └─────────┘              │     │
    │    └─────────────────────────────────────────────────────────┘     │
    │                                                                     │
    │    ┌─────────────────────────────────────────────────────────┐     │
    │    │          Premium: Dedicated Databases                   │     │
    │    │    ┌───────────────┐      ┌───────────────┐            │     │
    │    │    │   Tenant X    │      │   Tenant Y    │            │     │
    │    │    │   (Isolated)  │      │   (Isolated)  │            │     │
    │    │    └───────────────┘      └───────────────┘            │     │
    │    └─────────────────────────────────────────────────────────┘     │
    │                                                                     │
    └─────────────────────────────────────────────────────────────────────┘
```

## Isolation Models

| Model | Description | Cost | Use Case |
|-------|-------------|------|----------|
| **Pooled** | Shared resources, logical isolation | Low | Standard tier |
| **Siloed** | Dedicated resources per tenant | High | Premium tier |
| **Hybrid** | Mix based on tier | Medium | Multi-tier SaaS |

## Components

| Component | Purpose |
|-----------|---------|
| Tenant Management DB | Tenant metadata |
| Onboarding Workflow | Automated provisioning |
| EKS (shared nodes) | Standard tier compute |
| EKS (dedicated nodes) | Premium tier compute |
| RDS (shared) | Pooled database with RLS |
| RDS (dedicated) | Isolated tenant databases |
| Cognito | User authentication |
| Usage Metering | Billing metrics |

## Quick Start

1. **Deploy Control Plane**:
```bash
atmos terraform apply tenant-management-db -s <stack>
atmos terraform apply step-functions-onboarding -s <stack>
```

2. **Deploy Application Plane**:
```bash
atmos terraform apply eks -s <stack>
atmos terraform apply eks-addons -s <stack>
atmos terraform apply apigateway -s <stack>
```

3. **Deploy Data Plane**:
```bash
atmos terraform apply rds-shared -s <stack>
atmos terraform apply s3-tenant-data -s <stack>
atmos terraform apply elasticache -s <stack>
```

## Cost Estimate

| Tenants | Monthly Cost |
|---------|--------------|
| 10 | $500-1,000 |
| 100 | $2,000-5,000 |
| 1,000 | $10,000-30,000 |

## Tenant Isolation

### Database Row-Level Security

```sql
-- Enable RLS
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- Create policy
CREATE POLICY tenant_isolation ON orders
    USING (tenant_id = current_setting('app.tenant_id'));

-- Set tenant context
SET app.tenant_id = 'tenant_123';
```

### Kubernetes Namespaces

```yaml
# Namespace per tenant
apiVersion: v1
kind: Namespace
metadata:
  name: tenant-acme
  labels:
    tenant: acme
    tier: premium

---
# Network Policy
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tenant-isolation
  namespace: tenant-acme
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              tenant: acme
```

### S3 Prefix Isolation

```
s3://tenant-data/
├── tenants/
│   ├── tenant-acme/
│   │   ├── uploads/
│   │   └── exports/
│   ├── tenant-beta/
│   │   ├── uploads/
│   │   └── exports/
```

## Tenant Onboarding

### Provisioning Workflow

1. **Validate**: Check tenant configuration
2. **Create Database**: Schema or dedicated instance
3. **Provision Storage**: S3 prefix and policies
4. **Configure Auth**: Cognito user pool/client
5. **Deploy App**: Kubernetes namespace
6. **Notify**: Welcome email

### API Example

```bash
# Create tenant
curl -X POST https://api.example.com/admin/tenants \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "name": "Acme Corp",
    "tier": "premium",
    "config": {
      "region": "us-east-1",
      "features": ["analytics", "api-access"]
    }
  }'
```

## Billing Integration

### Usage Metrics

```python
# Emit usage event
kinesis.put_record(
    StreamName='usage-metering',
    Data=json.dumps({
        'tenant_id': 'tenant_123',
        'metric': 'api_calls',
        'value': 1,
        'timestamp': datetime.now().isoformat()
    }),
    PartitionKey='tenant_123'
)
```

### Aggregation

| Metric | Description |
|--------|-------------|
| API Calls | Number of API requests |
| Storage | GB of data stored |
| Compute | CPU/memory hours |
| Users | Active user count |

## Best Practices

1. **Tenant Context**: Always set tenant context
2. **Data Isolation**: Use RLS and prefixes
3. **Resource Limits**: Set quotas per tenant
4. **Monitoring**: Per-tenant metrics
5. **Compliance**: Audit logging per tenant
