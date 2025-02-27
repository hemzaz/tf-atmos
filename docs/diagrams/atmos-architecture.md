# Atmos Architecture Diagrams

This document contains Mermaid diagrams that visualize the architecture, workflows, and design of the Atmos framework with Terraform.

## 1. Atmos Framework Overview

```mermaid
graph TD
    User[User/Developer] -->|Uses| CLI[Atmos CLI]
    CLI -->|Executes| Workflows[Workflows]
    CLI -->|Processes| Stacks[Stack Configurations]
    CLI -->|Runs| Terraform[Terraform]
    
    Stacks -->|References| Catalog[Component Catalog]
    Stacks -->|Contains| VarFiles[Environment-specific Variables]
    
    Catalog -->|Defines| Components[Terraform Components]
    
    Components -->|Creates| Resources[AWS Resources]
    
    Workflows -->|Orchestrates| Operations[Infrastructure Operations]
    Operations -->|Uses| Terraform
    
    Backend[Terraform Backend] -.->|Stores State| S3[(S3 Bucket)]
    Backend -.->|Locks State| DynamoDB[(DynamoDB Table)]
    
    Terraform -->|Uses| Backend
    
    subgraph "Atmos Framework"
        CLI
        Workflows
        Stacks
        Catalog
    end
    
    subgraph "Infrastructure as Code"
        Components
        Terraform
        Backend
    end
    
    subgraph "AWS Cloud"
        Resources
        S3
        DynamoDB
    end
```

## 2. Multi-Environment Architecture

```mermaid
graph TD
    classDef dev fill:#baf,stroke:#333,stroke-width:1px
    classDef staging fill:#fba,stroke:#333,stroke-width:1px
    classDef prod fill:#fdc,stroke:#333,stroke-width:1px
    classDef shared fill:#dfd,stroke:#333,stroke-width:1px
    
    Atmos[Atmos Framework] -->|Manages| DevAccount[Development Account]
    Atmos -->|Manages| StagingAccount[Staging Account]
    Atmos -->|Manages| ProdAccount[Production Account]
    Atmos -->|Manages| SharedAccount[Shared Services Account]
    
    DevAccount -->|Contains| DevVPC[VPC]
    DevAccount -->|Contains| DevEKS[EKS]
    DevAccount -->|Contains| DevRDS[RDS]
    DevAccount -->|Contains| DevAPI[API Gateway]
    
    StagingAccount -->|Contains| StagingVPC[VPC]
    StagingAccount -->|Contains| StagingEKS[EKS]
    StagingAccount -->|Contains| StagingRDS[RDS]
    StagingAccount -->|Contains| StagingAPI[API Gateway]
    
    ProdAccount -->|Contains| ProdVPC[VPC]
    ProdAccount -->|Contains| ProdEKS[EKS]
    ProdAccount -->|Contains| ProdRDS[RDS]
    ProdAccount -->|Contains| ProdAPI[API Gateway]
    
    SharedAccount -->|Contains| TerraformBackend[Terraform Backend]
    SharedAccount -->|Contains| DNS[Route53 DNS]
    SharedAccount -->|Contains| Monitoring[CloudWatch Monitoring]
    SharedAccount -->|Contains| SecurityServices[Security Services]
    
    class DevVPC,DevEKS,DevRDS,DevAPI dev
    class StagingVPC,StagingEKS,StagingRDS,StagingAPI staging
    class ProdVPC,ProdEKS,ProdRDS,ProdAPI prod
    class TerraformBackend,DNS,Monitoring,SecurityServices shared
```

## 3. Stack and Component Structure

```mermaid
graph TD
    Atmos[Atmos Framework] -->|Defines| Stacks[Stack Configurations]
    
    Stacks -->|Contains| AccountStacks[Account Stacks]
    Stacks -->|Contains| CatalogStacks[Catalog Stacks]
    
    AccountStacks -->|Has| DevAccount[dev]
    AccountStacks -->|Has| StagingAccount[staging]
    AccountStacks -->|Has| ProdAccount[prod]
    
    DevAccount -->|Has| DevEnvironments[Environments]
    StagingAccount -->|Has| StagingEnvironments[Environments]
    ProdAccount -->|Has| ProdEnvironments[Environments]
    
    DevEnvironments -->|Contains| DevEnv1[dev-us-east-1]
    DevEnvironments -->|Contains| DevEnv2[dev-us-west-2]
    
    StagingEnvironments -->|Contains| StagingEnv[staging-us-east-1]
    
    ProdEnvironments -->|Contains| ProdEnv1[prod-us-east-1]
    ProdEnvironments -->|Contains| ProdEnv2[prod-us-west-2]
    
    DevEnv1 -->|Has| DevEnv1Components[Component Configs]
    DevEnv1Components -->|Imports from| CatalogStacks
    
    CatalogStacks -->|Defines| NetworkCatalog[network.yaml]
    CatalogStacks -->|Defines| ServicesCatalog[services.yaml]
    CatalogStacks -->|Defines| BackendCatalog[backend.yaml]
    CatalogStacks -->|Defines| IAMCatalog[iam.yaml]
    CatalogStacks -->|Defines| APIGatewayCatalog[apigateway.yaml]
    
    NetworkCatalog -->|References| Components[Terraform Components]
    ServicesCatalog -->|References| Components
    BackendCatalog -->|References| Components
    IAMCatalog -->|References| Components
    APIGatewayCatalog -->|References| Components
    
    Components -->|Contains| VPCComponent[vpc]
    Components -->|Contains| EKSComponent[eks]
    Components -->|Contains| RDSComponent[rds]
    Components -->|Contains| APIGatewayComponent[apigateway]
    Components -->|Contains| LambdaComponent[lambda]
    Components -->|Contains| MonitoringComponent[monitoring]
```

## 4. Terraform Backend Architecture

```mermaid
graph TD
    Atmos[Atmos Framework] -->|Configures| Backend[Terraform Backend]
    
    Backend -->|Uses| S3[S3 Bucket for State]
    Backend -->|Uses| DynamoDB[DynamoDB for Locking]
    
    Workflow[Bootstrap Workflow] -->|Creates| S3
    Workflow -->|Creates| DynamoDB
    
    S3 -->|Stores| TerraformState[Terraform State Files]
    TerraformState -->|Organized by| StateStructure[tenant/account/environment/component]
    
    DynamoDB -->|Contains| LockTable[Lock Table]
    LockTable -->|Prevents| StateLockingConflicts[Concurrent Modifications]
    
    S3 -->|Configured with| S3Config[Version Control, Encryption]
    DynamoDB -->|Configured with| DynamoConfig[Auto-scaling, Encryption]
    
    IAM[IAM Roles] -->|Controls access to| S3
    IAM -->|Controls access to| DynamoDB
    
    CrossAccount[Cross-Account Access] -->|Uses| IAM
```

## 5. Atmos Workflow Process

```mermaid
flowchart TD
    Start([Start]) --> UserCommand[User Executes Atmos Command]
    UserCommand --> AtmosInitialize[Atmos CLI Initializes]
    AtmosInitialize --> LoadConfig[Load Atmos Config]
    
    LoadConfig --> WorkflowCommand{Workflow Command?}
    
    WorkflowCommand -->|Yes| LoadWorkflow[Load Workflow Definition]
    LoadWorkflow --> ValidateArgs[Validate Arguments]
    ValidateArgs --> ExecuteSteps[Execute Workflow Steps]
    ExecuteSteps --> End([End])
    
    WorkflowCommand -->|No| TerraformCommand{Terraform Command?}
    
    TerraformCommand -->|Yes| ProcessStack[Process Stack Configuration]
    ProcessStack --> ResolveCatalog[Resolve Catalog References]
    ResolveCatalog --> MergeVars[Merge Variables]
    MergeVars --> EvaluateExpressions[Evaluate Atmos Expressions]
    EvaluateExpressions --> GenerateTFVars[Generate Terraform Variables]
    GenerateTFVars --> ExecuteTerraform[Execute Terraform Command]
    ExecuteTerraform --> End
    
    TerraformCommand -->|No| OtherCommand[Execute Other Atmos Command]
    OtherCommand --> End
```

## 6. Environment Onboarding Process

```mermaid
sequenceDiagram
    autonumber
    participant User as User/Developer
    participant Atmos as Atmos CLI
    participant Workflow as Onboarding Workflow
    participant Terraform as Terraform
    participant AWS as AWS Cloud
    
    User->>Atmos: Execute onboard-environment workflow
    Atmos->>Workflow: Load workflow definition
    Workflow->>Atmos: Request required arguments
    Atmos->>User: Prompt for tenant, account, environment
    User->>Atmos: Provide required arguments
    
    Atmos->>Workflow: Execute with provided arguments
    
    Workflow->>Atmos: Generate environment config files
    Workflow->>Atmos: Apply backend component
    Atmos->>Terraform: terraform init & apply backend
    Terraform->>AWS: Create S3 bucket & DynamoDB table
    AWS-->>Terraform: Confirm creation
    
    Workflow->>Atmos: Apply network component
    Atmos->>Terraform: terraform init & apply network
    Terraform->>AWS: Create VPC & networking resources
    AWS-->>Terraform: Confirm creation
    
    Workflow->>Atmos: Apply IAM component
    Atmos->>Terraform: terraform init & apply iam
    Terraform->>AWS: Create IAM roles & policies
    AWS-->>Terraform: Confirm creation
    
    Workflow->>Atmos: Apply additional components
    Atmos->>Terraform: terraform init & apply remaining components
    Terraform->>AWS: Create remaining resources
    AWS-->>Terraform: Confirm creation
    
    Workflow-->>Atmos: Onboarding complete
    Atmos-->>User: Environment successfully onboarded
```

## 7. Component Dependency Graph

```mermaid
graph TD
    %% Primary Infrastructure Components
    Backend[Backend] -->|Depends on| Nothing[No Dependencies]
    
    VPC[VPC] -->|Depends on| Backend
    
    IAM[IAM] -->|Depends on| Backend
    
    SecurityGroups[Security Groups] -->|Depends on| VPC
    
    %% Database Components
    RDS[RDS] -->|Depends on| VPC
    RDS -->|Depends on| SecurityGroups
    
    DynamoDB[DynamoDB] -->|Depends on| VPC
    DynamoDB -->|Depends on| IAM
    
    %% Compute Components
    EC2[EC2] -->|Depends on| VPC
    EC2 -->|Depends on| SecurityGroups
    EC2 -->|Depends on| IAM
    
    ECS[ECS] -->|Depends on| VPC
    ECS -->|Depends on| SecurityGroups
    ECS -->|Depends on| IAM
    
    EKS[EKS] -->|Depends on| VPC
    EKS -->|Depends on| SecurityGroups
    EKS -->|Depends on| IAM
    
    Lambda[Lambda] -->|Depends on| IAM
    Lambda -->|Depends on| VPC
    
    %% Network Components
    ACM[ACM] -->|Depends on| DNS
    
    DNSa[DNS] -->|Depends on| Backend
    
    %% Application Components
    APIGateway[API Gateway] -->|Depends on| Lambda
    APIGateway -->|Depends on| VPC
    APIGateway -->|Depends on| ACM
    APIGateway -->|Depends on| DNS
    
    %% Monitoring Components
    Monitoring[Monitoring] -->|Depends on| All[All Components]
```

## 8. Atmos Variable Resolution Process

```mermaid
flowchart TD
    AtmosCommand[Atmos Command Execution] --> LoadStackConfig[Load Stack Configuration]
    LoadStackConfig --> ProcessImports[Process Imports from Catalog]
    
    ProcessImports --> MergeVars[Merge Variables]
    
    subgraph "Variable Resolution Priority"
        direction TB
        StackVars[Stack Config Variables] --> |Overrides| CatalogVars[Catalog Variables]
        CatalogVars --> |Overrides| DefaultVars[Default Variables]
    end
    
    MergeVars --> ResolveVarRefs[Resolve Variable References]
    
    ResolveVarRefs --> ProcessAtmosExpressions[Process Atmos Expressions]
    
    subgraph "Expression Types"
        direction TB
        Deep["Deep Merge: deep_merge(var1, var2)"]
        Output["Component Output: output.component.value"]
        Env["Environment Variables: env:VAR_NAME"]
        SSM["SSM Parameters: ssm:/path/to/param"]
        Math["Math Functions: cidrsubnet(), etc."]
    end
    
    ProcessAtmosExpressions --> GenerateContext[Generate Terraform Context]
    GenerateContext --> ExecuteTerraform[Execute Terraform Command]
```

## 9. Atmos Multi-Account Security Model

```mermaid
graph TD
    classDef admin fill:#f66,stroke:#333,stroke-width:1px
    classDef limited fill:#6f6,stroke:#333,stroke-width:1px
    
    Developer[Developer] -->|Assumes| DeveloperRole[Developer Role]
    Admin[Administrator] -->|Assumes| AdminRole[Administrator Role]
    CI[CI/CD Pipeline] -->|Assumes| CIRole[CI/CD Role]
    
    DeveloperRole -->|Access to| DevAccount[Development Account]
    DeveloperRole -->|Limited Access to| StagingAccount[Staging Account]
    DeveloperRole -->|No Access to| ProdAccount[Production Account]
    
    AdminRole -->|Full Access to| DevAccount
    AdminRole -->|Full Access to| StagingAccount
    AdminRole -->|Full Access to| ProdAccount
    
    CIRole -->|Deployment Access to| DevAccount
    CIRole -->|Deployment Access to| StagingAccount
    CIRole -->|Deployment Access to| ProdAccount
    
    SharedAccount[Shared Services Account] -->|Hosts| TerraformBackend[Terraform Backend]
    
    DevAccount -->|Backend Access via| BackendRole[Backend Access Role]
    StagingAccount -->|Backend Access via| BackendRole
    ProdAccount -->|Backend Access via| BackendRole
    
    BackendRole -->|Read/Write Access to| TerraformBackend
    
    class AdminRole,CIRole admin
    class DeveloperRole limited
```

## 10. Atmos Deployment Workflow

```mermaid
sequenceDiagram
    autonumber
    participant User as User/Developer
    participant Atmos as Atmos CLI
    participant Stack as Stack Configuration
    participant TF as Terraform
    participant Backend as Terraform Backend
    participant AWS as AWS Cloud
    
    User->>Atmos: atmos terraform plan component -s tenant-account-env
    Atmos->>Stack: Load stack configuration
    Stack->>Atmos: Return merged configuration
    Atmos->>TF: Generate Terraform variables
    Atmos->>TF: Execute terraform init
    TF->>Backend: Initialize backend connection
    TF->>AWS: Fetch current state
    TF->>TF: Generate execution plan
    TF->>User: Display execution plan
    
    User->>Atmos: atmos terraform apply component -s tenant-account-env
    Atmos->>Stack: Load stack configuration
    Stack->>Atmos: Return merged configuration
    Atmos->>TF: Generate Terraform variables
    Atmos->>TF: Execute terraform apply
    TF->>Backend: Lock state for updates
    TF->>AWS: Apply changes to resources
    AWS-->>TF: Confirm resource creation/updates
    TF->>Backend: Write updated state
    TF->>Backend: Unlock state
    TF->>User: Display execution results
```