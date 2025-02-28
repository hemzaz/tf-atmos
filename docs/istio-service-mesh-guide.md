# Istio Service Mesh Guide

This guide provides information on Istio service mesh implementation in the Atmos-managed AWS EKS infrastructure.

## What is Istio?

Istio is an open-source service mesh that provides a way to control and observe the interactions between your services. It adds features like traffic management, security, and observability without requiring changes to your application code.

## Architecture

Our Istio implementation consists of three main components:

1. **istio-base**: Contains the cluster-wide CRDs and base components
2. **istiod**: The control plane for Istio that manages configuration and certificates
3. **istio-ingress**: The ingress gateway that manages incoming traffic to the mesh

Additional observability components:

1. **Kiali**: Visualization dashboard for the service mesh
2. **Jaeger**: Distributed tracing system

## Usage

### Enabling Istio for a Namespace

To enable Istio for a namespace, add the following label:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: my-namespace
  labels:
    istio-injection: enabled
```

### Automatic HTTPS with Custom Domain Names

To expose a service with automatic HTTPS:

1. Create a Gateway or use the default one:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: my-gateway
  namespace: istio-ingress
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    hosts:
    - "myservice.example.com"
    tls:
      mode: SIMPLE
      # References the mounted certificate from ACM 
      serverCertificate: /etc/istio/ingressgateway-certs/tls.crt
      privateKey: /etc/istio/ingressgateway-certs/tls.key
```

2. Create a VirtualService pointing to your service:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-service
  namespace: my-namespace
spec:
  hosts:
  - "myservice.example.com"
  gateways:
  - istio-ingress/my-gateway
  http:
  - route:
    - destination:
        host: my-service.my-namespace.svc.cluster.local
        port:
          number: 8080
```

This will:
1. Automatically create DNS entries via external-dns
2. Use the wildcard certificate for TLS
3. Route traffic to your service

### Traffic Management

Istio provides features for traffic management:

- **Virtual Services**: Route traffic to different versions of services
- **Destination Rules**: Define policies for traffic
- **Gateways**: Configure how traffic enters the mesh

Example VirtualService:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: reviews
spec:
  hosts:
  - reviews
  http:
  - route:
    - destination:
        host: reviews
        subset: v1
      weight: 90
    - destination:
        host: reviews
        subset: v2
      weight: 10
```

### Security

Istio provides security features:

- **mTLS**: Mutual TLS between services
- **Authorization Policies**: Control access between services

Example AuthorizationPolicy:

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: httpbin
  namespace: foo
spec:
  selector:
    matchLabels:
      app: httpbin
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/default/sa/sleep"]
    to:
    - operation:
        methods: ["GET"]
```

## Monitoring and Observability

Our Istio implementation includes:

- **Kiali**: Provides visualization of service mesh
  - Access URL: https://dashboard.example.com (automatically configured with external-dns)
  - Internal URL: http://kiali.istio-system.svc.cluster.local:20001
  
- **Jaeger**: Provides distributed tracing
  - Access URL: http://jaeger-query.istio-system.svc.cluster.local:16686

## Certificate Management

The implementation provides TLS certificate provisioning using AWS Certificate Manager. There are two approaches to use these certificates with Istio:

### Option 1: Direct Certificate Injection (Default)

1. **AWS Certificate Manager (ACM)**: Provisions and manages certificates with automatic renewal
2. **Route53**: Handles DNS validation for certificates
3. **external-dns**: Creates DNS records for Kubernetes services
4. **Manual Export**: Certificates must be manually exported from ACM
5. **Kubernetes Secret**: Certificate directly injected as a Kubernetes secret

Steps for implementation:
1. Certificate is created in ACM with Route53 validation
2. Certificate content is manually exported from ACM (console or CLI)
3. Certificate is directly injected as a Kubernetes TLS secret via Terraform
4. Istio gateway mounts this TLS secret for secure traffic

Advantages:
- Simpler implementation, fewer dependencies
- No external operators required
- Direct control over certificate content 

Limitations:
- Requires manual certificate rotation when ACM renews
- Certificate material must be handled manually

### Option 2: External Secrets Integration

1. **AWS Certificate Manager (ACM)**: Provisions and manages certificates with automatic renewal
2. **AWS Secrets Manager**: Securely stores certificate material
3. **external-secrets-operator**: Synchronizes certificates to Kubernetes
4. **Route53 & external-dns**: Handle DNS validation and records

Steps for implementation:
1. Deploy external-secrets operator as a separate component
2. Certificate is created in ACM with Route53 validation
3. Certificate content is stored in AWS Secrets Manager
4. external-secrets syncs the certificate to a Kubernetes TLS secret
5. Istio gateway mounts this TLS secret for secure traffic

Advantages:
- Fully automated certificate rotation
- Certificate private keys never leave AWS infrastructure
- Strong integration with AWS security controls

Limitations:
- More complex setup requiring additional components
- Potential race conditions or circular dependencies
- Requires separate deployment of external-secrets operator

To simplify initial setup, we use the direct injection method by default.

## Resource Requirements

Istio components have the following resource requirements:

- **istiod**: 500m CPU, 2Gi memory
- **istio-proxy** (sidecar): 100m-2000m CPU, 128Mi-1024Mi memory

## Best Practices

1. **Start Small**: Don't enable Istio for all namespaces at once
2. **Resource Planning**: Ensure you have enough resources for Istio components and sidecars
3. **Monitor Performance**: Keep an eye on the overhead added by Istio
4. **Set Appropriate Limits**: Configure memory and CPU limits to avoid resource contention
5. **Use Helm Values**: Customize Istio through the Helm values in your stack configuration

## Certificate Management

### Option 1: Direct Injection Certificate Rotation (Default)

When using the direct injection method, you'll need to manually rotate certificates after ACM renewal:

1. Export the renewed certificate from ACM (via AWS Console or CLI)
2. Update the `acm_certificate_crt` and `acm_certificate_key` values in your stack configuration
3. Re-apply the EKS addons component to update the Kubernetes secret

```bash
# View current certificate expiration date
kubectl get secret istio-gateway-cert -n istio-ingress -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates

# Export certificate from ACM via AWS CLI (example)
aws acm export-certificate --certificate-arn <ARN> --passphrase <BASE64_PASSPHRASE> --output text

# Update stack configuration
# Re-apply the configuration
atmos terraform apply eks-addons -s <tenant>-<account>-<environment>

# Verify the certificate was updated
kubectl get secret istio-gateway-cert -n istio-ingress -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates
```

### Option 2: External Secrets Certificate Rotation

When using the external-secrets integration, certificate rotation is automatic:

1. ACM automatically renews the certificate (typically 60 days before expiration)
2. The renewed certificate is stored in AWS Secrets Manager
3. The external-secrets operator detects the change and updates the Kubernetes secret
4. Istio immediately begins using the new certificate

If you need to manually trigger a refresh:

```bash
# View current certificate expiration date
kubectl get secret istio-gateway-cert -n istio-ingress -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates

# Force external-secrets operator to refresh the certificate
kubectl annotate externalsecret istio-certificate -n istio-ingress force-sync=$(date +%s) --overwrite

# Verify the certificate was updated
kubectl get secret istio-gateway-cert -n istio-ingress -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates
```

## Troubleshooting

Common issues:

1. **Pod not injected with sidecar**: Verify namespace has istio-injection label
2. **Services can't communicate**: Check network policies and authorization policies
3. **High latency**: Check resource allocation for istio-proxy sidecars
4. **Certificate issues**: Verify the certificate secret is properly synced from Secrets Manager

Debug commands:

```bash
# Check if Istio is injected in a pod
kubectl describe pod <pod-name> -n <namespace>

# Check Istio proxy logs
kubectl logs <pod-name> -c istio-proxy -n <namespace>

# Check Istio configuration
istioctl analyze -n <namespace>

# Check certificate secret
kubectl get secret istio-gateway-cert -n istio-ingress -o yaml

# Check external secrets status
kubectl get externalsecret istio-certificate -n istio-ingress
kubectl describe externalsecret istio-certificate -n istio-ingress
```

## Reference

- [Official Istio Documentation](https://istio.io/latest/docs/)
- [Istio GitHub Repository](https://github.com/istio/istio)
- [Kiali Documentation](https://kiali.io/docs/)
- [Jaeger Documentation](https://www.jaegertracing.io/docs/)