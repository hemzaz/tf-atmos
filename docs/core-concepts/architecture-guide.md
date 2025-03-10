# Architecture Overview

_Last Updated: March 10, 2025_

This document provides a detailed overview of the Atmos-managed AWS infrastructure architecture.

## Table of Contents

- [Multi-Account Architecture](#multi-account-architecture)
- [Component Architecture](#component-architecture)
- [VPC Networking](#vpc-networking)
- [Kubernetes Architecture (EKS)](#kubernetes-architecture-eks)
- [Terraform State Management](#terraform-state-management)
- [CI/CD Pipeline Integration](#cicd-pipeline-integration)
- [Folder Structure](#folder-structure)
- [Technology Stack](#technology-stack)
- [For More Information](#for-more-information)

## Multi-Account Architecture

The infrastructure follows AWS's recommended multi-account strategy for isolation and security:

```mermaid
graph TD
    classDef management fill:#FF9900,stroke:#232F3E,color:white;
    classDef shared fill:#3F8624,stroke:#2E5B1A,color:white;
    classDef workload fill:#1F78B4,stroke:#12537E,color:white;
    
    Management[Management Account]:::management
    Shared[Shared Services Account]:::shared
    Dev[Development Account]:::workload
    Staging[Staging Account]:::workload
    Prod[Production Account]:::workload
    
    Management --> Shared
    Management --> Dev
    Management --> Staging
    Management --> Prod
    
    Shared --> Dev
    Shared --> Staging
    Shared --> Prod
```

## Component Architecture

The infrastructure is organized into layers, with components in each layer:

```mermaid
graph TD
    classDef network fill:#4472C4,stroke:#31538D,color:white;
    classDef infra fill:#70AD47,stroke:#507E33,color:white;
    classDef security fill:#ED7D31,stroke:#B85D23,color:white;
    classDef services fill:#5B9BD5,stroke:#406E94,color:white;
    classDef ops fill:#A6761D,stroke:#7C571A,color:white;
    
    NetworkLayer[Network Layer]:::network
    InfraLayer[Infrastructure Layer]:::infra
    SecurityLayer[Security Layer]:::security
    ServicesLayer[Services Layer]:::services
    OpsLayer[Operations Layer]:::ops
    
    NetworkLayer --> VPC[VPC]:::network
    NetworkLayer --> DNS[DNS]:::network
    NetworkLayer --> SG[Security Groups]:::network
    NetworkLayer --> TGW[Transit Gateway]:::network
    
    InfraLayer --> EC2[EC2]:::infra
    InfraLayer --> ECS[ECS]:::infra
    InfraLayer --> EKS[EKS]:::infra
    InfraLayer --> RDS[RDS]:::infra
    InfraLayer --> Lambda[Lambda]:::infra
    
    SecurityLayer --> IAM[IAM]:::security
    SecurityLayer --> Secrets[Secrets Manager]:::security
    SecurityLayer --> ACM[Certificate Manager]:::security
    
    ServicesLayer --> API[API Gateway]:::services
    ServicesLayer --> ALB[Load Balancer]:::services
    ServicesLayer --> CF[CloudFront]:::services
    ServicesLayer --> Istio[Istio]:::services
    
    OpsLayer --> Monitoring[CloudWatch]:::ops
    OpsLayer --> Backend[Terraform Backend]:::ops
    OpsLayer --> CI[CI/CD]:::ops
```

## VPC Networking

Each environment has its own VPC with public and private subnets across multiple availability zones:

```mermaid
graph TD
    classDef vpc fill:#4472C4,stroke:#31538D,color:white;
    classDef public fill:#70AD47,stroke:#507E33,color:white;
    classDef private fill:#ED7D31,stroke:#B85D23,color:white;
    classDef gateway fill:#5B9BD5,stroke:#406E94,color:white;
    
    VPC[VPC 10.0.0.0/16]:::vpc
    
    VPC --> AZ1[Availability Zone 1]
    VPC --> AZ2[Availability Zone 2]
    VPC --> AZ3[Availability Zone 3]
    
    AZ1 --> PublicAZ1[Public Subnet 10.0.0.0/24]:::public
    AZ1 --> PrivateAZ1[Private Subnet 10.0.3.0/24]:::private
    
    AZ2 --> PublicAZ2[Public Subnet 10.0.1.0/24]:::public
    AZ2 --> PrivateAZ2[Private Subnet 10.0.4.0/24]:::private
    
    AZ3 --> PublicAZ3[Public Subnet 10.0.2.0/24]:::public
    AZ3 --> PrivateAZ3[Private Subnet 10.0.5.0/24]:::private
    
    PublicAZ1 --> IGW[Internet Gateway]:::gateway
    PublicAZ2 --> IGW
    PublicAZ3 --> IGW
    
    PrivateAZ1 --> NAT1[NAT Gateway 1]:::gateway
    PrivateAZ2 --> NAT2[NAT Gateway 2]:::gateway
    PrivateAZ3 --> NAT3[NAT Gateway 3]:::gateway
    
    NAT1 --> IGW
    NAT2 --> IGW
    NAT3 --> IGW
```

## Kubernetes Architecture (EKS)

The EKS implementation follows best practices for scalability and security:

```mermaid
graph TD
    classDef control fill:#4472C4,stroke:#31538D,color:white;
    classDef node fill:#70AD47,stroke:#507E33,color:white;
    classDef addon fill:#ED7D31,stroke:#B85D23,color:white;
    classDef net fill:#5B9BD5,stroke:#406E94,color:white;
    
    EKS[EKS Cluster]:::control
    
    EKS --> ControlPlane[Control Plane]:::control
    EKS --> NodeGroups[Managed Node Groups]:::node
    EKS --> Fargate[Fargate Profiles]:::node
    EKS --> Addons[Cluster Add-ons]:::addon
    
    NodeGroups --> OnDemand[On-Demand Nodes]:::node
    NodeGroups --> Spot[Spot Nodes]:::node
    
    Addons --> Karpenter[Karpenter]:::addon
    Addons --> KEDA[KEDA]:::addon
    Addons --> Istio[Istio]:::addon
    Addons --> ExternalDNS[External DNS]:::addon
    Addons --> ExternalSecrets[External Secrets]:::addon
    Addons --> CertManager[Cert Manager]:::addon
    Addons --> AWSLoadBalancer[AWS Load Balancer Controller]:::addon
    
    Istio --> IstioGateway[Istio Gateway]:::net
    IstioGateway --> Certificates[TLS Certificates]:::net
```

## Terraform State Management

The backend component manages Terraform state for all environments:

```mermaid
graph TD
    classDef s3 fill:#4472C4,stroke:#31538D,color:white;
    classDef dynamo fill:#70AD47,stroke:#507E33,color:white;
    classDef iam fill:#ED7D31,stroke:#B85D23,color:white;
    
    Backend[Terraform Backend]
    
    Backend --> S3[S3 Bucket]:::s3
    Backend --> DynamoDB[DynamoDB Table]:::dynamo
    Backend --> IAM[IAM Roles]:::iam
    
    S3 --> Versioning[Versioning]:::s3
    S3 --> Encryption[Server-side Encryption]:::s3
    S3 --> Lifecycle[Lifecycle Rules]:::s3
    
    DynamoDB --> Locking[State Locking]:::dynamo
    DynamoDB --> Consistency[Consistency]:::dynamo
    
    IAM --> CrossAccount[Cross-account Access]:::iam
    IAM --> LeastPrivilege[Least Privilege]:::iam
```

## CI/CD Pipeline Integration

The infrastructure can be deployed and managed via CI/CD pipelines:

```mermaid
sequenceDiagram
    participant D as Developer
    participant G as Git Repository
    participant CI as CI/CD Pipeline
    participant A as Atmos CLI
    participant T as Terraform
    participant AWS as AWS Cloud
    
    D->>G: Commit changes
    G->>CI: Trigger pipeline
    CI->>A: Run atmos workflow plan
    A->>T: Generate Terraform plan
    T->>AWS: Preview changes
    T-->>A: Plan results
    A-->>CI: Review output
    CI->>D: Approval request
    D->>CI: Approve changes
    CI->>A: Run atmos workflow apply
    A->>T: Apply changes
    T->>AWS: Create/update resources
    T-->>A: Apply results
    A-->>CI: Deployment status
    CI-->>G: Update deployment status
    CI-->>D: Deployment notification
```

## Folder Structure

The project organization follows a logical structure to separate reusable components from specific implementations:

```
tf-atmos/
├── components/          # Reusable Terraform modules
│   └── terraform/       # Component implementations
├── docs/                # Documentation
├── examples/            # Example configurations
├── stacks/              # Stack configurations
│   ├── account/         # Account-specific stacks
│   ├── catalog/         # Reusable stack definitions
│   └── schemas/         # JSON schemas
├── templates/           # Templates for new components
└── workflows/           # Atmos workflow definitions
```

## Technology Stack

| Category | Technology | Purpose |
|----------|------------|---------|
| Infrastructure as Code | Terraform | Resource provisioning |
| Orchestration | Atmos | Configuration and workflow management |
| Containers | EKS, ECS | Container orchestration |
| Serverless | Lambda | Function-as-a-Service |
| Networking | VPC, Transit Gateway | Network infrastructure |
| Security | IAM, Secrets Manager | Identity and secrets management |
| Databases | RDS, DynamoDB | Data persistence |
| API Management | API Gateway | API endpoints |
| Certificate Management | ACM, cert-manager | TLS certificates |
| Service Mesh | Istio | Microservice communication |
| Autoscaling | Karpenter, KEDA | Automated scaling |

## For More Information

- [Component Catalog](terraform-component-catalog.md) - Detailed descriptions of components
- [Workflow Reference](workflows.md) - Available workflows and usage
- [Security Best Practices](security-best-practices-guide.md) - Security design and best practices
- [Environment Onboarding](environment-guide.md) - Adding new environments