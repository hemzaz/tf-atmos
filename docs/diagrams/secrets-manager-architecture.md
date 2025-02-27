# AWS Secrets Manager Architecture and Workflows

This document provides architectural diagrams for AWS Secrets Manager integration with the Atmos framework.

## 1. Secret Management Architecture

```mermaid
graph TD
    classDef awsService fill:#FF9900,stroke:#232F3E,color:white;
    classDef application fill:#3F8624,stroke:#2E5B1A,color:white;
    classDef component fill:#1F78B4,stroke:#12537E,color:white;
    classDef data fill:#6B6B6B,stroke:#4A4A4A,color:white;
    classDef workflow fill:#A6761D,stroke:#7C571A,color:white;

    User[Developer/Operator] --> AtmosConfig[Atmos Configuration]
    AtmosConfig --> SecretsDef[Secret Definitions]
    
    subgraph "AWS Account"
        SecretsDef --> TerraformComp[Terraform Secrets Manager Component]:::component
        TerraformComp --> CreateSecrets[Create/Update Secrets]:::workflow
        
        CreateSecrets --> SecretsManager[AWS Secrets Manager]:::awsService
        
        SecretsManager --> Encryption{Encryption}
        Encryption --> KMS[AWS KMS]:::awsService
        
        SecretsManager --> Rotation{Rotation}
        Rotation --> RotationLambda[Rotation Lambda]:::awsService
        
        KMS --> EncryptedSecrets[(Encrypted Secrets)]:::data
    end
    
    subgraph "Access Patterns"
        EC2[EC2 Instance]:::application
        Lambda[Lambda Function]:::application
        ECS[ECS Container]:::application
        EKS[Kubernetes Pod]:::application
        App[Application]:::application
        
        EC2 --> IAMRole1[IAM Role]
        Lambda --> IAMRole2[IAM Role]
        ECS --> IAMRole3[IAM Role]
        EKS --> IAMRole4[IAM Role]
        App --> IAMRole5[IAM Role]
        
        IAMRole1 --> GetSecret1[GetSecretValue API]:::workflow
        IAMRole2 --> GetSecret2[GetSecretValue API]:::workflow
        IAMRole3 --> GetSecret3[GetSecretValue API]:::workflow
        IAMRole4 --> GetSecret4[GetSecretValue API]:::workflow
        IAMRole5 --> GetSecret5[GetSecretValue API]:::workflow
        
        GetSecret1 --> SecretsManager
        GetSecret2 --> SecretsManager
        GetSecret3 --> SecretsManager
        GetSecret4 --> SecretsManager
        GetSecret5 --> SecretsManager
    end
```

## 2. Secret Hierarchy and Organization

```mermaid
graph TD
    classDef context fill:#4472C4,stroke:#31538D,color:white;
    classDef environment fill:#70AD47,stroke:#507E33,color:white;
    classDef path fill:#ED7D31,stroke:#B85D23,color:white;
    classDef secret fill:#5B9BD5,stroke:#406E94,color:white;

    Root[Secrets Manager] --> Context1[Context: myapp]:::context
    Root --> Context2[Context: infra]:::context
    
    Context1 --> Env1[Environment: dev]:::environment
    Context1 --> Env2[Environment: prod]:::environment
    Context2 --> Env3[Environment: shared]:::environment
    
    Env1 --> Path1[Path: database]:::path
    Env1 --> Path2[Path: api]:::path
    Env2 --> Path3[Path: database]:::path
    Env2 --> Path4[Path: api]:::path
    Env3 --> Path5[Path: network]:::path
    
    Path1 --> Secret1[Secret: credentials]:::secret
    Path1 --> Secret2[Secret: connection]:::secret
    Path2 --> Secret3[Secret: api-key]:::secret
    Path2 --> Secret4[Secret: oauth-config]:::secret
    Path3 --> Secret5[Secret: credentials]:::secret
    Path3 --> Secret6[Secret: connection]:::secret
    Path4 --> Secret7[Secret: api-key]:::secret
    Path4 --> Secret8[Secret: oauth-config]:::secret
    Path5 --> Secret9[Secret: vpn-config]:::secret
```

## 3. Secret Creation Workflow

```mermaid
sequenceDiagram
    participant User as Developer/Operator
    participant Atmos as Atmos CLI
    participant Terraform as Terraform Component
    participant AWS as AWS Secrets Manager
    participant KMS as AWS KMS

    User->>Atmos: atmos terraform apply secretsmanager
    Atmos->>Terraform: Process component configuration
    
    Terraform->>Terraform: Generate random passwords if needed
    
    Terraform->>AWS: Create/update secrets
    AWS->>KMS: Request encryption
    KMS-->>AWS: Return encrypted data
    AWS-->>Terraform: Return secret ARNs and metadata
    
    Terraform->>Terraform: Configure rotation if enabled
    Terraform->>AWS: Set up rotation configuration
    
    Terraform->>Terraform: Apply IAM policies if specified
    Terraform->>AWS: Attach resource policies
    
    Terraform-->>Atmos: Return outputs
    Atmos-->>User: Display results
```

## 4. Secret Access Workflow

```mermaid
sequenceDiagram
    participant App as Application
    participant IAM as IAM Service
    participant SM as AWS Secrets Manager
    participant KMS as AWS KMS
    
    App->>IAM: Authenticate with IAM role
    IAM-->>App: Return temporary credentials
    
    App->>SM: GetSecretValue API call
    SM->>IAM: Validate permissions
    IAM-->>SM: Authorization result
    
    alt Authorized
        SM->>KMS: Request decryption
        KMS->>IAM: Validate KMS permissions
        IAM-->>KMS: Authorization result
        
        alt KMS Authorized
            KMS-->>SM: Return decrypted data
            SM-->>App: Return secret value
        else KMS Not Authorized
            KMS-->>SM: Access denied
            SM-->>App: Access denied (KMS)
        end
    else Not Authorized
        SM-->>App: Access denied (Secrets Manager)
    end
    
    App->>App: Use secret value in application
```

## 5. Cross-Account Secret Access

```mermaid
graph TD
    classDef account1 fill:#FF9900,stroke:#232F3E,color:white;
    classDef account2 fill:#3F8624,stroke:#2E5B1A,color:white;
    classDef service fill:#1F78B4,stroke:#12537E,color:white;
    classDef policy fill:#A6761D,stroke:#7C571A,color:white;

    subgraph "Account A - Secret Owner":::account1
        SecretManager[AWS Secrets Manager]:::service
        Secret[(Secret)]
        ResourcePolicy[Resource Policy]:::policy
        
        SecretManager --> Secret
        ResourcePolicy --> SecretManager
    end
    
    subgraph "Account B - Secret Consumer":::account2
        App[Application]:::service
        IAMRole[IAM Role]:::policy
        
        App --> IAMRole
        IAMRole --> CrossAccountAccess[Cross-Account API Call]
    end
    
    CrossAccountAccess --> SecretManager
    ResourcePolicy -.-> CrossAccountAccess
```

## 6. Integration with Other Components

```mermaid
graph TB
    classDef secretsComp fill:#FF9900,stroke:#232F3E,color:white;
    classDef otherComp fill:#1F78B4,stroke:#12537E,color:white;
    classDef output fill:#3F8624,stroke:#2E5B1A,color:white;
    
    SecretsManager[Secrets Manager Component]:::secretsComp
    
    RDS[RDS Component]:::otherComp
    Lambda[Lambda Component]:::otherComp
    ECS[ECS Component]:::otherComp
    APIGateway[API Gateway Component]:::otherComp
    
    SecretsManager --> GeneratedPasswords[Generated Passwords]:::output
    SecretsManager --> SecretARNs[Secret ARNs]:::output
    
    GeneratedPasswords --> RDS
    SecretARNs --> Lambda
    SecretARNs --> ECS
    SecretARNs --> APIGateway
    
    RDS --> DBEndpoint[DB Endpoint]:::output
    DBEndpoint --> SecretsManager
```