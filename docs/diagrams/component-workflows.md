# Atmos Component Workflows

This document contains Mermaid diagrams that illustrate the workflows for different Atmos components and their interactions.

## 1. Environment Onboarding Workflow

```mermaid
graph TD
    Start([Start]) --> CheckPrereq[Check Prerequisites]
    CheckPrereq --> InitBackend[Initialize Backend]
    InitBackend --> CreateNetworkStack[Create Network Stack]
    CreateNetworkStack --> CreateIAMStack[Create IAM Stack]
    CreateIAMStack --> CreateSecurityStack[Create Security Stack]
    CreateSecurityStack --> CreateDatabaseStack[Create Database Stack]
    CreateDatabaseStack --> CreateComputeStack[Create Compute Stack]
    CreateComputeStack --> CreateAppStack[Create Application Stack]
    CreateAppStack --> CreateMonitoringStack[Create Monitoring Stack]
    CreateMonitoringStack --> End([End])
    
    subgraph "Network Layer"
        CreateNetworkStack --> DeployVPC[Deploy VPC]
        DeployVPC --> DeploySubnets[Deploy Subnets]
        DeploySubnets --> DeployNATGateway[Deploy NAT Gateway]
        DeployNATGateway --> DeployRoutes[Deploy Route Tables]
        DeployRoutes --> NetworkComplete[Network Complete]
    end
    
    subgraph "IAM Layer"
        CreateIAMStack --> DeployRoles[Deploy IAM Roles]
        DeployRoles --> DeployPolicies[Deploy IAM Policies]
        DeployPolicies --> IAMComplete[IAM Complete]
    end
    
    subgraph "Security Layer"
        CreateSecurityStack --> DeploySecurityGroups[Deploy Security Groups]
        DeploySecurityGroups --> DeployKMS[Deploy KMS Keys]
        DeployKMS --> SecurityComplete[Security Complete]
    end
```

## 2. VPC Component Workflow

```mermaid
flowchart TD
    Start([Start]) --> InitTerraform[Initialize Terraform]
    InitTerraform --> LoadVPCConfig[Load VPC Configuration]
    LoadVPCConfig --> CreateVPC[Create VPC]
    
    CreateVPC --> CreateIGW[Create Internet Gateway]
    CreateVPC --> CreateSubnets[Create Subnets]
    
    CreateSubnets --> CreatePublicSubnets[Create Public Subnets]
    CreateSubnets --> CreatePrivateSubnets[Create Private Subnets]
    CreateSubnets --> CreateDatabaseSubnets[Create Database Subnets]
    
    CreateIGW --> AttachIGW[Attach IGW to VPC]
    
    CreatePublicSubnets --> ConfigurePublicRoutes[Configure Public Route Tables]
    AttachIGW --> ConfigurePublicRoutes
    
    CreatePrivateSubnets --> NATGatewayNeeded{NAT Gateway Needed?}
    NATGatewayNeeded -->|Yes| CreateNATGateway[Create NAT Gateway]
    NATGatewayNeeded -->|No| SkipNAT[Skip NAT Gateway]
    
    CreateNATGateway --> ConfigurePrivateRoutes[Configure Private Route Tables]
    SkipNAT --> ConfigurePrivateRoutes
    
    CreateDatabaseSubnets --> ConfigureDatabaseRoutes[Configure Database Route Tables]
    
    ConfigurePublicRoutes --> EndpointsNeeded{VPC Endpoints Needed?}
    ConfigurePrivateRoutes --> EndpointsNeeded
    ConfigureDatabaseRoutes --> EndpointsNeeded
    
    EndpointsNeeded -->|Yes| CreateVPCEndpoints[Create VPC Endpoints]
    EndpointsNeeded -->|No| SkipEndpoints[Skip VPC Endpoints]
    
    CreateVPCEndpoints --> ConfigureSecurityGroups[Configure Security Groups]
    SkipEndpoints --> ConfigureSecurityGroups
    
    ConfigureSecurityGroups --> SetupFlowLogs[Setup VPC Flow Logs]
    
    SetupFlowLogs --> TagResources[Tag All Resources]
    
    TagResources --> OutputValues[Output VPC Values]
    
    OutputValues --> End([End])
```

## 3. API Gateway Component Workflow

```mermaid
flowchart TD
    Start([Start]) --> InitTerraform[Initialize Terraform]
    InitTerraform --> LoadAPIConfig[Load API Gateway Configuration]
    
    LoadAPIConfig --> APIType{API Type?}
    
    APIType -->|REST API| CreateRESTAPI[Create REST API]
    APIType -->|HTTP API| CreateHTTPAPI[Create HTTP API]
    
    CreateRESTAPI --> ConfigureRESTEndpoints[Configure REST Endpoints]
    CreateHTTPAPI --> ConfigureHTTPRoutes[Configure HTTP Routes]
    
    ConfigureRESTEndpoints --> AuthType{Authorization Type?}
    ConfigureHTTPRoutes --> AuthType
    
    AuthType -->|Cognito| SetupCognitoAuth[Setup Cognito Authorizer]
    AuthType -->|JWT| SetupJWTAuth[Setup JWT Authorizer]
    AuthType -->|Lambda| SetupLambdaAuth[Setup Lambda Authorizer]
    AuthType -->|IAM| SetupIAMAuth[Setup IAM Authorization]
    AuthType -->|None| SkipAuth[Skip Authorization]
    
    SetupCognitoAuth --> IntegrationType{Integration Type?}
    SetupJWTAuth --> IntegrationType
    SetupLambdaAuth --> IntegrationType
    SetupIAMAuth --> IntegrationType
    SkipAuth --> IntegrationType
    
    IntegrationType -->|Lambda| SetupLambdaIntegration[Setup Lambda Integration]
    IntegrationType -->|HTTP| SetupHTTPIntegration[Setup HTTP Integration]
    IntegrationType -->|VPC Link| SetupVPCLinkIntegration[Setup VPC Link Integration]
    IntegrationType -->|AWS Service| SetupServiceIntegration[Setup AWS Service Integration]
    IntegrationType -->|Mock| SetupMockIntegration[Setup Mock Integration]
    
    SetupLambdaIntegration --> CustomDomainNeeded{Custom Domain?}
    SetupHTTPIntegration --> CustomDomainNeeded
    SetupVPCLinkIntegration --> CustomDomainNeeded
    SetupServiceIntegration --> CustomDomainNeeded
    SetupMockIntegration --> CustomDomainNeeded
    
    CustomDomainNeeded -->|Yes| SetupCustomDomain[Setup Custom Domain]
    CustomDomainNeeded -->|No| SkipCustomDomain[Skip Custom Domain]
    
    SetupCustomDomain --> APIKeysNeeded{API Keys?}
    SkipCustomDomain --> APIKeysNeeded
    
    APIKeysNeeded -->|Yes| SetupAPIKeys[Setup API Keys & Usage Plans]
    APIKeysNeeded -->|No| SkipAPIKeys[Skip API Keys]
    
    SetupAPIKeys --> ConfigureLogging[Configure Logging]
    SkipAPIKeys --> ConfigureLogging
    
    ConfigureLogging --> CreateDeployment[Create Deployment/Stage]
    
    CreateDeployment --> ConfigureCORS[Configure CORS]
    
    ConfigureCORS --> CreateDashboard[Create CloudWatch Dashboard]
    
    CreateDashboard --> TagResources[Tag All Resources]
    
    TagResources --> OutputValues[Output API Values]
    
    OutputValues --> End([End])
```

## 4. EKS Component Workflow

```mermaid
flowchart TD
    Start([Start]) --> InitTerraform[Initialize Terraform]
    InitTerraform --> LoadEKSConfig[Load EKS Configuration]
    
    LoadEKSConfig --> CreateIAMRoles[Create IAM Roles]
    CreateIAMRoles --> CreateSecurityGroups[Create Security Groups]
    
    CreateSecurityGroups --> NeedsPrivateCluster{Private Cluster?}
    
    NeedsPrivateCluster -->|Yes| ConfigurePrivateCluster[Configure Private Cluster]
    NeedsPrivateCluster -->|No| ConfigurePublicCluster[Configure Public Cluster]
    
    ConfigurePrivateCluster --> CreateVPCEndpoints[Create VPC Endpoints]
    ConfigurePublicCluster --> SkipVPCEndpoints[Skip VPC Endpoints]
    
    CreateVPCEndpoints --> CreateEKSCluster[Create EKS Cluster]
    SkipVPCEndpoints --> CreateEKSCluster
    
    CreateEKSCluster --> NodeGroupType{Node Group Type?}
    
    NodeGroupType -->|Managed| CreateManagedNodeGroups[Create Managed Node Groups]
    NodeGroupType -->|Self-Managed| CreateSelfManagedNodes[Create Self-Managed Nodes]
    NodeGroupType -->|Fargate| ConfigureFargate[Configure Fargate Profiles]
    
    CreateManagedNodeGroups --> ConfigureClusterAutoscaler[Configure Cluster Autoscaler]
    CreateSelfManagedNodes --> ConfigureClusterAutoscaler
    ConfigureFargate --> ConfigureClusterAutoscaler
    
    ConfigureClusterAutoscaler --> AddonsNeeded{Add-ons Needed?}
    
    AddonsNeeded -->|Yes| InstallAddons[Install EKS Add-ons]
    AddonsNeeded -->|No| SkipAddons[Skip Add-ons]
    
    InstallAddons --> ConfigureAWSLoadBalancerController[Configure AWS Load Balancer Controller]
    SkipAddons --> ConfigureAWSLoadBalancerController
    
    ConfigureAWSLoadBalancerController --> ConfigureClusterLogging[Configure Cluster Logging]
    
    ConfigureClusterLogging --> ConfigureKubernetesProviders[Configure Kubernetes Providers]
    
    ConfigureKubernetesProviders --> CreateKubeconfig[Create Kubeconfig]
    
    CreateKubeconfig --> TagResources[Tag All Resources]
    
    TagResources --> OutputValues[Output EKS Values]
    
    OutputValues --> End([End])
```

## 5. RDS Component Workflow

```mermaid
flowchart TD
    Start([Start]) --> InitTerraform[Initialize Terraform]
    InitTerraform --> LoadRDSConfig[Load RDS Configuration]
    
    LoadRDSConfig --> EngineType{Engine Type?}
    
    EngineType -->|MySQL| ConfigureMySQL[Configure MySQL]
    EngineType -->|PostgreSQL| ConfigurePostgreSQL[Configure PostgreSQL]
    EngineType -->|Aurora| ConfigureAurora[Configure Aurora]
    EngineType -->|SQL Server| ConfigureSQLServer[Configure SQL Server]
    EngineType -->|Oracle| ConfigureOracle[Configure Oracle]
    EngineType -->|MariaDB| ConfigureMariaDB[Configure MariaDB]
    
    ConfigureMySQL --> CreateSubnetGroup[Create DB Subnet Group]
    ConfigurePostgreSQL --> CreateSubnetGroup
    ConfigureAurora --> CreateSubnetGroup
    ConfigureSQLServer --> CreateSubnetGroup
    ConfigureOracle --> CreateSubnetGroup
    ConfigureMariaDB --> CreateSubnetGroup
    
    CreateSubnetGroup --> CreateParameterGroup[Create Parameter Group]
    
    CreateParameterGroup --> CreateOptionGroup[Create Option Group]
    
    CreateOptionGroup --> MultiAZ{Multi-AZ?}
    
    MultiAZ -->|Yes| ConfigureMultiAZ[Configure Multi-AZ]
    MultiAZ -->|No| ConfigureSingleAZ[Configure Single-AZ]
    
    ConfigureMultiAZ --> BackupStrategy{Backup Strategy?}
    ConfigureSingleAZ --> BackupStrategy
    
    BackupStrategy -->|Automated| ConfigureAutomatedBackups[Configure Automated Backups]
    BackupStrategy -->|Snapshots| ConfigureSnapshots[Configure DB Snapshots]
    
    ConfigureAutomatedBackups --> ConfigureBackupWindow[Configure Backup Window]
    ConfigureSnapshots --> ConfigureBackupWindow
    
    ConfigureBackupWindow --> ConfigureMaintenanceWindow[Configure Maintenance Window]
    
    ConfigureMaintenanceWindow --> StorageType{Storage Type?}
    
    StorageType -->|Standard| ConfigureStandardStorage[Configure Standard Storage]
    StorageType -->|GP2| ConfigureGP2Storage[Configure GP2 Storage]
    StorageType -->|io1| ConfigureIO1Storage[Configure io1 Storage]
    
    ConfigureStandardStorage --> ConfigureStorage[Configure Storage]
    ConfigureGP2Storage --> ConfigureStorage
    ConfigureIO1Storage --> ConfigureStorage
    
    ConfigureStorage --> ConfigureCloudwatchLogs[Configure CloudWatch Logs]
    
    ConfigureCloudwatchLogs --> ConfigureEncryption[Configure Encryption]
    
    ConfigureEncryption --> CreateSecurityGroup[Create Security Group]
    
    CreateSecurityGroup --> CreateDBInstance[Create DB Instance]
    
    CreateDBInstance --> TagResources[Tag All Resources]
    
    TagResources --> OutputValues[Output RDS Values]
    
    OutputValues --> End([End])
```

## 6. Lambda Component Workflow

```mermaid
flowchart TD
    Start([Start]) --> InitTerraform[Initialize Terraform]
    InitTerraform --> LoadLambdaConfig[Load Lambda Configuration]
    
    LoadLambdaConfig --> FunctionType{Function Type?}
    
    FunctionType -->|ZIP| ConfigureZIPFunction[Configure ZIP Function]
    FunctionType -->|Container| ConfigureContainerFunction[Configure Container Function]
    
    ConfigureZIPFunction --> PackagingType{Packaging Method?}
    ConfigureContainerFunction --> BuildContainer[Build Container Image]
    
    PackagingType -->|Inline| CreateInlineCode[Create Inline Code]
    PackagingType -->|S3| UploadToS3[Upload to S3]
    PackagingType -->|Local Zip| CreateLocalZip[Create Local ZIP]
    
    CreateInlineCode --> ConfigureRuntime[Configure Runtime]
    UploadToS3 --> ConfigureRuntime
    CreateLocalZip --> ConfigureRuntime
    BuildContainer --> SkipRuntime[Skip Runtime Config]
    
    ConfigureRuntime --> CreateLambdaRole[Create IAM Role]
    SkipRuntime --> CreateLambdaRole
    
    CreateLambdaRole --> ConfigureConcurrency{Configure Concurrency?}
    
    ConfigureConcurrency -->|Yes| SetReservedConcurrency[Set Reserved Concurrency]
    ConfigureConcurrency -->|Provisioned| SetProvisionedConcurrency[Set Provisioned Concurrency]
    ConfigureConcurrency -->|No| SkipConcurrency[Skip Concurrency Settings]
    
    SetReservedConcurrency --> ConfigureVPCAccess{VPC Access?}
    SetProvisionedConcurrency --> ConfigureVPCAccess
    SkipConcurrency --> ConfigureVPCAccess
    
    ConfigureVPCAccess -->|Yes| SetupVPCConfig[Setup VPC Configuration]
    ConfigureVPCAccess -->|No| SkipVPCConfig[Skip VPC Configuration]
    
    SetupVPCConfig --> ConfigureEnvironment[Configure Environment Variables]
    SkipVPCConfig --> ConfigureEnvironment
    
    ConfigureEnvironment --> ConfigureMemorySize[Configure Memory Size]
    
    ConfigureMemorySize --> ConfigureTimeout[Configure Timeout]
    
    ConfigureTimeout --> EventTriggers{Event Triggers?}
    
    EventTriggers -->|API Gateway| SetupAPIGatewayTrigger[Setup API Gateway Trigger]
    EventTriggers -->|EventBridge| SetupEventBridgeTrigger[Setup EventBridge Trigger]
    EventTriggers -->|S3| SetupS3Trigger[Setup S3 Trigger]
    EventTriggers -->|SQS| SetupSQSTrigger[Setup SQS Trigger]
    EventTriggers -->|SNS| SetupSNSTrigger[Setup SNS Trigger]
    EventTriggers -->|DynamoDB| SetupDynamoDBTrigger[Setup DynamoDB Trigger]
    EventTriggers -->|None| SkipTriggers[Skip Triggers]
    
    SetupAPIGatewayTrigger --> ConfigureLogging[Configure CloudWatch Logs]
    SetupEventBridgeTrigger --> ConfigureLogging
    SetupS3Trigger --> ConfigureLogging
    SetupSQSTrigger --> ConfigureLogging
    SetupSNSTrigger --> ConfigureLogging
    SetupDynamoDBTrigger --> ConfigureLogging
    SkipTriggers --> ConfigureLogging
    
    ConfigureLogging --> ConfigureXRay{X-Ray Tracing?}
    
    ConfigureXRay -->|Yes| EnableXRay[Enable X-Ray Tracing]
    ConfigureXRay -->|No| SkipXRay[Skip X-Ray Tracing]
    
    EnableXRay --> CreateLambdaFunction[Create Lambda Function]
    SkipXRay --> CreateLambdaFunction
    
    CreateLambdaFunction --> CreateLambdaAlias[Create Lambda Alias]
    
    CreateLambdaAlias --> TagResources[Tag All Resources]
    
    TagResources --> OutputValues[Output Lambda Values]
    
    OutputValues --> End([End])
```

## 7. Route53 DNS Component Workflow

```mermaid
flowchart TD
    Start([Start]) --> InitTerraform[Initialize Terraform]
    InitTerraform --> LoadDNSConfig[Load DNS Configuration]
    
    LoadDNSConfig --> CreateHostedZones[Create Hosted Zones]
    
    CreateHostedZones --> ZoneType{Zone Type?}
    
    ZoneType -->|Public| CreatePublicZones[Create Public Zones]
    ZoneType -->|Private| CreatePrivateZones[Create Private Zones]
    
    CreatePublicZones --> ConfigureNS[Configure NS Records]
    CreatePrivateZones --> AssociateVPCs[Associate with VPCs]
    
    ConfigureNS --> RecordSets{Record Sets Needed?}
    AssociateVPCs --> RecordSets
    
    RecordSets -->|Yes| CreateRecordSets[Create Record Sets]
    RecordSets -->|No| SkipRecordSets[Skip Record Sets]
    
    CreateRecordSets --> RecordType{Record Type?}
    
    RecordType -->|A/AAAA| CreateARecords[Create A/AAAA Records]
    RecordType -->|CNAME| CreateCNAMERecords[Create CNAME Records]
    RecordType -->|MX| CreateMXRecords[Create MX Records]
    RecordType -->|TXT| CreateTXTRecords[Create TXT Records]
    RecordType -->|SRV| CreateSRVRecords[Create SRV Records]
    RecordType -->|CAA| CreateCAARecords[Create CAA Records]
    RecordType -->|Alias| CreateAliasRecords[Create Alias Records]
    
    CreateARecords --> RoutingPolicy{Routing Policy?}
    CreateCNAMERecords --> RoutingPolicy
    CreateMXRecords --> RoutingPolicy
    CreateTXTRecords --> RoutingPolicy
    CreateSRVRecords --> RoutingPolicy
    CreateCAARecords --> RoutingPolicy
    CreateAliasRecords --> RoutingPolicy
    SkipRecordSets --> HealthChecksNeeded
    
    RoutingPolicy -->|Simple| ConfigureSimpleRouting[Configure Simple Routing]
    RoutingPolicy -->|Weighted| ConfigureWeightedRouting[Configure Weighted Routing]
    RoutingPolicy -->|Latency| ConfigureLatencyRouting[Configure Latency Routing]
    RoutingPolicy -->|Failover| ConfigureFailoverRouting[Configure Failover Routing]
    RoutingPolicy -->|Geolocation| ConfigureGeolocationRouting[Configure Geolocation Routing]
    RoutingPolicy -->|Multivalue| ConfigureMultivalueRouting[Configure Multivalue Routing]
    
    ConfigureSimpleRouting --> HealthChecksNeeded{Health Checks?}
    ConfigureWeightedRouting --> HealthChecksNeeded
    ConfigureLatencyRouting --> HealthChecksNeeded
    ConfigureFailoverRouting --> HealthChecksNeeded
    ConfigureGeolocationRouting --> HealthChecksNeeded
    ConfigureMultivalueRouting --> HealthChecksNeeded
    
    HealthChecksNeeded -->|Yes| CreateHealthChecks[Create Health Checks]
    HealthChecksNeeded -->|No| SkipHealthChecks[Skip Health Checks]
    
    CreateHealthChecks --> AssociateWithRecords[Associate Health Checks with Records]
    SkipHealthChecks --> TrafficPoliciesNeeded
    
    AssociateWithRecords --> TrafficPoliciesNeeded{Traffic Policies?}
    
    TrafficPoliciesNeeded -->|Yes| CreateTrafficPolicies[Create Traffic Policies]
    TrafficPoliciesNeeded -->|No| SkipTrafficPolicies[Skip Traffic Policies]
    
    CreateTrafficPolicies --> QueryLoggingNeeded{Query Logging?}
    SkipTrafficPolicies --> QueryLoggingNeeded
    
    QueryLoggingNeeded -->|Yes| EnableQueryLogging[Enable Query Logging]
    QueryLoggingNeeded -->|No| SkipQueryLogging[Skip Query Logging]
    
    EnableQueryLogging --> TagResources[Tag All Resources]
    SkipQueryLogging --> TagResources
    
    TagResources --> OutputValues[Output DNS Values]
    
    OutputValues --> End([End])
```

## 8. Atmos Drift Detection Workflow

```mermaid
sequenceDiagram
    autonumber
    participant User as User
    participant Atmos as Atmos CLI
    participant Workflow as Drift Detection Workflow
    participant Terraform as Terraform
    participant AWS as AWS Cloud
    
    User->>Atmos: Run drift detection workflow
    Atmos->>Workflow: Initialize drift detection
    
    Workflow->>Atmos: Get list of environments
    Atmos->>Workflow: Return environments list
    
    loop For each environment
        Workflow->>Atmos: Get environment components
        Atmos->>Workflow: Return component list
        
        loop For each component
            Workflow->>Terraform: Run terraform plan
            Terraform->>AWS: Retrieve current state
            AWS->>Terraform: Return current state
            Terraform->>Terraform: Compare with declared state
            Terraform->>Workflow: Return drift status
            
            alt Drift detected
                Workflow->>Atmos: Log drift detection
            else No drift
                Workflow->>Atmos: Log component in sync
            end
        end
    end
    
    Workflow->>Atmos: Generate drift report
    Atmos->>User: Present drift report
```

## 9. Infrastructure Dependency Graph

```mermaid
graph TD
    classDef requiredLayer fill:#f9d,stroke:#333,stroke-width:1px
    classDef networkLayer fill:#bbf,stroke:#333,stroke-width:1px
    classDef securityLayer fill:#fbb,stroke:#333,stroke-width:1px
    classDef databaseLayer fill:#bfb,stroke:#333,stroke-width:1px
    classDef computeLayer fill:#fbf,stroke:#333,stroke-width:1px
    classDef appLayer fill:#fdb,stroke:#333,stroke-width:1px
    classDef monitoringLayer fill:#bff,stroke:#333,stroke-width:1px
    
    Backend[Backend] --> VPC[VPC]
    Backend --> IAM[IAM]
    
    VPC --> SecurityGroups[Security Groups]
    VPC --> VPCEndpoints[VPC Endpoints]
    
    IAM --> RolesPolicies[Roles & Policies]
    
    SecurityGroups --> RDS[RDS]
    SecurityGroups --> ElastiCache[ElastiCache]
    SecurityGroups --> EC2[EC2]
    SecurityGroups --> EKS[EKS]
    SecurityGroups --> ECS[ECS]
    
    VPC --> RDS
    VPC --> ElastiCache
    VPC --> EC2
    VPC --> EKS
    VPC --> ECS
    
    IAM --> EC2
    IAM --> EKS
    IAM --> ECS
    IAM --> Lambda[Lambda]
    
    VPC --> Lambda
    
    DNS[Route53] --> ACM[ACM]
    
    EC2 --> LoadBalancer[Load Balancer]
    ECS --> LoadBalancer
    EKS --> LoadBalancer
    
    LoadBalancer --> APIGateway[API Gateway]
    Lambda --> APIGateway
    ACM --> APIGateway
    
    RDS --> Application[Application Layer]
    ElastiCache --> Application
    LoadBalancer --> Application
    APIGateway --> Application
    
    VPC --> Monitoring[Monitoring]
    EC2 --> Monitoring
    RDS --> Monitoring
    APIGateway --> Monitoring
    Lambda --> Monitoring
    
    class Backend requiredLayer
    class VPC,VPCEndpoints networkLayer
    class IAM,SecurityGroups,RolesPolicies,ACM securityLayer
    class RDS,ElastiCache databaseLayer
    class EC2,EKS,ECS,Lambda computeLayer
    class LoadBalancer,APIGateway,DNS,Application appLayer
    class Monitoring monitoringLayer
```

## 10. Terraform State Management Workflow

```mermaid
flowchart TD
    Start([Start]) --> InitBackend[Initialize S3 Backend]
    InitBackend --> BackendExists{Backend Exists?}
    
    BackendExists -->|Yes| UseExistingBackend[Use Existing Backend]
    BackendExists -->|No| BootstrapBackend[Bootstrap New Backend]
    
    BootstrapBackend --> CreateS3Bucket[Create S3 Bucket]
    CreateS3Bucket --> ConfigureS3Versioning[Configure S3 Versioning]
    ConfigureS3Versioning --> ConfigureS3Encryption[Configure S3 Encryption]
    ConfigureS3Encryption --> CreateDynamoDBTable[Create DynamoDB Table]
    CreateDynamoDBTable --> ConfigureDynamoDBEncryption[Configure DynamoDB Encryption]
    ConfigureDynamoDBEncryption --> EnableKeyRotation[Enable KMS Key Rotation]
    EnableKeyRotation --> UseExistingBackend
    
    UseExistingBackend --> ConfigureLocking[Configure State Locking]
    
    ConfigureLocking --> StatePath{State Organization}
    
    StatePath -->|By Component| OrganizeByComponent[tenant/account/env/component]
    StatePath -->|By Environment| OrganizeByEnvironment[tenant/account/env]
    
    OrganizeByComponent --> ConfigureBackendBlock[Configure Backend Block]
    OrganizeByEnvironment --> ConfigureBackendBlock
    
    ConfigureBackendBlock --> UseIAMRoles[Use IAM Roles for Access]
    
    UseIAMRoles --> SetupCrossAccount[Setup Cross-Account Access]
    
    SetupCrossAccount --> ImportExists{Import Needed?}
    
    ImportExists -->|Yes| ImportResources[Import Existing Resources]
    ImportExists -->|No| SkipImport[Skip Import]
    
    ImportResources --> TerraformInit[Run Terraform Init]
    SkipImport --> TerraformInit
    
    TerraformInit --> TerraformApply[Run Terraform Apply]
    
    TerraformApply --> StateBackupNeeded{State Backup?}
    
    StateBackupNeeded -->|Yes| BackupState[Backup Terraform State]
    StateBackupNeeded -->|No| SkipBackup[Skip Backup]
    
    BackupState --> End([End])
    SkipBackup --> End
```