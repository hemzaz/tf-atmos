# {{ tenant | capitalize }}-{{ account }}-{{ aws_region }}-{{ env_name }} Environment

Environment configuration for the {{ env_name }} environment.

## Environment Details

- **Tenant:** {{ tenant }}
- **Account:** {{ account }}
- **Environment:** {{ env_name }}
- **Type:** {{ env_type }}
- **Region:** {{ aws_region }}
- **Created:** {{ create_date }}

## Network Configuration

- **VPC CIDR:** {{ vpc_cidr }}
- **Availability Zones:** {{ availability_zones|join(", ") }}

## Components

This environment includes the following components:

- Networking (VPC, subnets, gateways)
{% if eks_cluster %}
- Kubernetes (EKS)
  - Node Type: {{ eks_node_instance_type }}
  - Node Count: {{ eks_node_min_count }} - {{ eks_node_max_count }}
{% endif %}
{% if rds_instances %}
- Databases (RDS)
{% endif %}
- Certificate Management (ACM)
- Security Groups

## Compliance Requirements

{% if compliance_level == "basic" %}
This environment uses basic security controls.
{% elif compliance_level == "soc2" %}
This environment is configured for SOC2 compliance with additional security controls.
{% elif compliance_level == "hipaa" %}
This environment is configured for HIPAA compliance with strict security and privacy controls.
{% elif compliance_level == "pci" %}
This environment is configured for PCI-DSS compliance with enhanced security controls for payment data.
{% endif %}

## Management

### Deployment

To deploy this environment:

```bash
# Plan the deployment
atmos terraform plan vpc -s {{ tenant }}-{{ account }}-{{ aws_region }}-{{ env_name }}

# Apply the environment
atmos workflow apply-environment tenant={{ tenant }} account={{ account }} environment={{ env_name }}
```

### Testing

To validate the environment configuration:

```bash
# Validate the stack
atmos validate stacks --stack {{ tenant }}-{{ account }}-{{ aws_region }}-{{ env_name }}

# Run compliance checks
atmos workflow compliance-check tenant={{ tenant }} account={{ account }} environment={{ env_name }}
```

## Stack Organization

This environment follows the organizational structure:

```
stacks/
└── orgs/
    └── {{ tenant }}/
        └── {{ account }}/
            └── {{ aws_region }}/
                └── {{ env_name }}/
                    ├── main.yaml
                    └── components/
                        ├── globals.yaml
                        ├── networking.yaml
                        ├── security.yaml
                        {% if eks_cluster %}├── compute.yaml{% endif %}
                        {% if rds_instances or eks_cluster %}└── services.yaml{% endif %}
```

## Contact

For questions about this environment, contact {{ team_email }}.