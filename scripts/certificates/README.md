# Certificate Management

Bash scripts for TLS certificate and SSH key operations against AWS Secrets
Manager, ACM and Kubernetes. They are the implementation (there is no separate
CLI); run them directly or through the Atmos workflow.

| Script | Purpose |
|--------|---------|
| `rotate-cert.sh` | Rotate a TLS certificate in Secrets Manager / ACM and sync the Kubernetes secret |
| `rotate-ssh-key.sh` | Rotate an SSH key pair stored in Secrets Manager |
| `generate-ssh-key.sh` | Generate an SSH key pair and store it in Secrets Manager |
| `export-cert.sh` | Export a certificate from Secrets Manager / ACM |
| `export-ssh-key.sh` | Export an SSH key from Secrets Manager |
| `monitor-certificates.sh` | Report certificates approaching expiry |
| `certificate-utils.sh` | Shared functions (sourced by the scripts above) |

## Usage

```bash
# Certificate rotation through the workflow (prompts for secret, namespace, ACM ARN)
atmos workflow rotate -f rotate-certificate

# Or directly
./scripts/certificates/rotate-cert.sh -s <secret_name> -n <namespace> [-a <acm_cert_arn>]
```

Each script prints its options with `-h`.
