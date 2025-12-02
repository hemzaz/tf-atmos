# Microservices Platform Blueprint

Enterprise microservices platform with service mesh and full observability.

## Architecture

```
                    ┌─────────────────────────────────┐
                    │         API Gateway             │
                    │    (Kong / AWS API Gateway)     │
                    └───────────────┬─────────────────┘
                                    │
                    ┌───────────────┴─────────────────┐
                    │         Istio Ingress           │
                    │         Gateway                 │
                    └───────────────┬─────────────────┘
                                    │
    ┌───────────────────────────────┼───────────────────────────────┐
    │                               │                               │
    │  ┌─────────┐   ┌─────────┐   │   ┌─────────┐   ┌─────────┐  │
    │  │ Service │   │ Service │   │   │ Service │   │ Service │  │
    │  │    A    │◄──┤    B    │◄──┴──►│    C    │──►│    D    │  │
    │  │(Envoy)  │   │(Envoy)  │       │(Envoy)  │   │(Envoy)  │  │
    │  └────┬────┘   └────┬────┘       └────┬────┘   └────┬────┘  │
    │       │             │                 │             │       │
    │       └─────────────┴────────┬────────┴─────────────┘       │
    │                              │                               │
    │                    ┌─────────┴─────────┐                    │
    │                    │    Event Bus      │                    │
    │                    │  (EventBridge)    │                    │
    │                    └───────────────────┘                    │
    └─────────────────────────────────────────────────────────────┘
                    EKS Cluster with Istio Service Mesh

    ┌─────────────────────────────────────────────────────────────┐
    │                    Observability Stack                       │
    │  ┌───────────┐  ┌───────────┐  ┌───────────┐               │
    │  │ Prometheus│  │  Grafana  │  │   Jaeger  │               │
    │  │ (Metrics) │  │ (Dashbd)  │  │ (Tracing) │               │
    │  └───────────┘  └───────────┘  └───────────┘               │
    └─────────────────────────────────────────────────────────────┘
```

## Components

| Component | Purpose |
|-----------|---------|
| VPC | Network with expanded CIDR for pods |
| EKS | Kubernetes cluster |
| Istio | Service mesh for mTLS, traffic management |
| API Gateway | External API management |
| EventBridge | Asynchronous event bus |
| Prometheus | Metrics collection |
| Grafana | Visualization dashboards |
| Jaeger | Distributed tracing |

## Prerequisites

- AWS account with appropriate permissions
- Terraform >= 1.5.0
- Atmos >= 1.50.0
- Helm 3.x
- istioctl

## Quick Start

1. **Deploy Infrastructure**:
```bash
atmos terraform apply vpc -s <stack>
atmos terraform apply eks -s <stack>
```

2. **Deploy Platform Services**:
```bash
atmos terraform apply eks-addons -s <stack>
```

3. **Configure Service Mesh**:
```bash
kubectl apply -f blueprints/microservices-platform/istio-config/
```

## Cost Estimate

| Environment | Monthly Cost |
|-------------|--------------|
| Development | $500-800 |
| Staging | $1,000-1,500 |
| Production | $3,000-8,000+ |

## Features

### Service Mesh (Istio)

- **mTLS**: Automatic encryption between services
- **Traffic Management**: Canary, blue-green deployments
- **Circuit Breaker**: Automatic failure handling
- **Rate Limiting**: Per-service throttling

### Observability

- **Metrics**: Prometheus + Grafana dashboards
- **Tracing**: Jaeger distributed tracing
- **Logging**: Fluent Bit to CloudWatch
- **Service Graph**: Kiali visualization

### Security

- Zero-trust networking
- Pod security policies
- Network policies
- RBAC enforcement

## Namespace Strategy

```
namespaces/
├── system/           # Platform components
├── istio-system/     # Service mesh
├── monitoring/       # Observability
├── services-dev/     # Development services
├── services-staging/ # Staging services
└── services-prod/    # Production services
```

## Best Practices

1. **Resource Limits**: Set CPU/memory limits for all pods
2. **Health Checks**: Configure liveness and readiness probes
3. **Graceful Shutdown**: Handle SIGTERM properly
4. **Circuit Breakers**: Configure failure thresholds
5. **Retry Policies**: Use exponential backoff
