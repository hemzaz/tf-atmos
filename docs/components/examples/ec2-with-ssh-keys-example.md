# EC2 with Automatic SSH Key Generation Example

This example demonstrates how to use the EC2 component with automatic SSH key generation and storage in AWS Secrets Manager.

## Features

- Creates a VPC with public and private subnets
- Deploys two instances: a public bastion and a private application server
- Supports three SSH key approaches:
  1. Global SSH key for multiple instances (specified via `global_key_name`)
  2. Individual SSH keys per instance (when key_name is set to null)
  3. Existing key pairs (specified via the instance's `key_name`)
- Automatically generates SSH key pairs for instances without existing keys
- Securely stores all generated private keys in AWS Secrets Manager
- Makes keys available for retrieval by users
- Configures security groups with restricted ingress/egress rules
- Applies IAM policies for least privilege access

## Architecture

```
┌───────────────────────────────────────────────────────────────┐
│ VPC                                                           │
│                                                               │
│  ┌──────────────────────────┐     ┌──────────────────────────┐│
│  │ Public Subnet            │     │ Private Subnet           ││
│  │                          │     │                          ││
│  │  ┌───────────────────┐   │     │  ┌───────────────────┐   ││
│  │  │                   │   │     │  │                   │   ││
│  │  │  Bastion Host     │   │     │  │  App Server       │   ││
│  │  │  with Auto SSH    │───┼─────┼─►│  with Auto SSH    │   ││
│  │  │  Key Generation   │   │     │  │  Key Generation   │   ││
│  │  │                   │   │     │  │                   │   ││
│  │  └───────────────────┘   │     │  └───────────────────┘   ││
│  │                          │     │                          ││
│  └──────────────────────────┘     └──────────────────────────┘│
│                                                               │
└───────────────────────────────────────────────────────────────┘
                                ▲
                                │
                                ▼
          ┌───────────────────────────────────────────┐
          │                                           │
          │      AWS Secrets Manager                  │
          │      - Bastion SSH Private Key            │
          │      - App Server SSH Private Key         │
          │                                           │
          └───────────────────────────────────────────┘
```

## Usage

1. Initialize the Terraform workspace:
   ```bash
   terraform init
   ```

2. Review the execution plan:
   ```bash
   terraform plan
   ```

3. Apply the configuration:
   ```bash
   terraform apply
   ```

4. After applying, you'll get outputs with:
   - The bastion's public IP address
   - The IDs of all created instances
   - ARNs of the secrets containing the SSH private keys
   - Names of the generated SSH key pairs

## Retrieving SSH Keys

### Retrieving Individual Instance Keys

To retrieve a private key for a specific instance from AWS Secrets Manager:

```bash
# Get the bastion host SSH key
aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw ssh_key_secret_arns | jq -r '.bastion') \
  --query 'SecretString' --output text | jq -r '.private_key_pem' > bastion.pem

# Set proper permissions
chmod 400 bastion.pem

# Connect to the bastion
ssh -i bastion.pem ec2-user@$(terraform output -raw bastion_public_ip)
```

### Retrieving the Global SSH Key

If you've configured a global SSH key, retrieve it with:

```bash
# Get the global SSH key
aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw global_key_secret_arn) \
  --query 'SecretString' --output text | jq -r '.private_key_pem' > global.pem

# Set proper permissions
chmod 400 global.pem

# Connect to an instance using the global key
ssh -i global.pem ec2-user@<INSTANCE_IP>
```

### Finding Which Instances Use Which Keys

```bash
# List all instances using the global key
terraform output instances_using_global_key

# List all instances with individual keys
terraform output instances_using_individual_keys

# View all key names and their mapping to instances
terraform output generated_key_names
```

## Security Considerations

- Private keys are stored in AWS Secrets Manager with encryption
- Public bastion has limited ingress rules (SSH only from specified CIDR)
- Egress traffic is limited to HTTP/HTTPS
- IAM policies follow least privilege principle
- SSH keys are unique per instance

## Customization

Edit the `main.tf` file to:

1. Change instance types and sizes
2. Modify security group rules
3. Add or remove instances
4. Change the SSH key algorithm or bit size
5. Add custom user data
6. Update IAM policies

## Clean Up

To destroy all resources:

```bash
terraform destroy
```