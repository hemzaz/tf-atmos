# Atmos Multi-Account Architecture

This document contains Mermaid diagrams that illustrate the multi-account architecture patterns enabled by the Atmos framework.

## 1. AWS Multi-Account Organization Structure

```mermaid
graph TD
    classDef mgmt fill:#ffcccc,stroke:#333,stroke-width:1px
    classDef shared fill:#ccffcc,stroke:#333,stroke-width:1px
    classDef network fill:#ccccff,stroke:#333,stroke-width:1px
    classDef sec fill:#ffffcc,stroke:#333,stroke-width:1px
    classDef dev fill:#ccffff,stroke:#333,stroke-width:1px
    classDef stage fill:#ffccff,stroke:#333,stroke-width:1px
    classDef prod fill:#ffddbb,stroke:#333,stroke-width:1px
    
    Root[AWS Organization Root]
    Root --> Management[Management Account]
    Root --> SharedServices[Shared Services OU]
    Root --> Workloads[Workloads OU]
    Root --> Security[Security OU]
    Root --> Sandbox[Sandbox OU]
    
    Management --> Logging[Logging Account]
    Management --> Security[Security Account]
    
    SharedServices --> NetworkAccount[Network Account]
    SharedServices --> SharedTools[Shared Tools Account]
    SharedServices --> BackendAccount[Backend Account]
    
    Workloads --> Dev[Development OU]
    Workloads --> Staging[Staging OU]
    Workloads --> Production[Production OU]
    
    Dev --> DevAccount1[Dev Account 1]
    Dev --> DevAccount2[Dev Account 2]
    
    Staging --> StagingAccount1[Staging Account 1]
    Staging --> StagingAccount2[Staging Account 2]
    
    Production --> ProdAccount1[Production Account 1]
    Production --> ProdAccount2[Production Account 2]
    
    Sandbox --> SandboxAccount1[Sandbox Account 1]
    Sandbox --> SandboxAccount2[Sandbox Account 2]
    
    class Management,Logging mgmt
    class SharedServices,NetworkAccount,SharedTools,BackendAccount shared
    class NetworkAccount network
    class Security sec
    class Dev,DevAccount1,DevAccount2,Sandbox,SandboxAccount1,SandboxAccount2 dev
    class Staging,StagingAccount1,StagingAccount2 stage
    class Production,ProdAccount1,ProdAccount2 prod
```

## 2. Terraform Backend Cross-Account Access

```mermaid
graph TD
    DevAccount[Development Account] -->|Assumes Role| BackendRole[Backend Access Role]
    StagingAccount[Staging Account] -->|Assumes Role| BackendRole
    ProdAccount[Production Account] -->|Assumes Role| BackendRole
    
    BackendRole -->|Has Access To| S3Bucket[Terraform State S3 Bucket]
    BackendRole -->|Has Access To| DynamoDB[Terraform Lock DynamoDB Table]
    
    S3Bucket -->|Contains| StateFiles[Terraform State Files]
    StateFiles -->|Organized By| FolderStructure[tenant/account/environment/component]
    
    DynamoDB -->|Contains| LockItems[Lock Table Items]
    LockItems -->|Prevents| ConcurrentAccess[Concurrent Access Conflicts]
    
    subgraph "Backend Account"
        BackendRole
        S3Bucket
        DynamoDB
        StateFiles
        FolderStructure
        LockItems
        ConcurrentAccess
    end
    
    subgraph "Workload Accounts"
        DevAccount
        StagingAccount
        ProdAccount
    end
```

## 3. Networking Architecture

```mermaid
graph TD
    classDef transit fill:#ffcccc,stroke:#333,stroke-width:1px
    classDef shared fill:#ccffcc,stroke:#333,stroke-width:1px
    classDef dev fill:#ccccff,stroke:#333,stroke-width:1px
    classDef stage fill:#ffffcc,stroke:#333,stroke-width:1px
    classDef prod fill:#ffccff,stroke:#333,stroke-width:1px
    
    TransitGateway[Transit Gateway] -->|Attachment| SharedVPC[Shared Services VPC]
    TransitGateway -->|Attachment| DevVPC[Development VPC]
    TransitGateway -->|Attachment| StageVPC[Staging VPC]
    TransitGateway -->|Attachment| ProdVPC[Production VPC]
    TransitGateway -->|Attachment| OnPremises[On-Premises Network]
    
    SharedVPC -->|Contains| SharedPublic[Public Subnets]
    SharedVPC -->|Contains| SharedPrivate[Private Subnets]
    SharedVPC -->|Contains| SharedEndpoints[VPC Endpoints]
    
    DevVPC -->|Contains| DevPublic[Public Subnets]
    DevVPC -->|Contains| DevPrivate[Private Subnets]
    DevVPC -->|Contains| DevEndpoints[VPC Endpoints]
    
    StageVPC -->|Contains| StagePublic[Public Subnets]
    StageVPC -->|Contains| StagePrivate[Private Subnets]
    StageVPC -->|Contains| StageEndpoints[VPC Endpoints]
    
    ProdVPC -->|Contains| ProdPublic[Public Subnets]
    ProdVPC -->|Contains| ProdPrivate[Private Subnets]
    ProdVPC -->|Contains| ProdEndpoints[VPC Endpoints]
    
    SharedPublic -->|Internet Access| IGW[Internet Gateway]
    DevPublic -->|Internet Access| IGW
    StagePublic -->|Internet Access| IGW
    ProdPublic -->|Internet Access| IGW
    
    OnPremises -->|Connected To| CustomerGateway[Customer Gateway]
    CustomerGateway -->|VPN Connection| TransitGateway
    
    class TransitGateway,OnPremises,CustomerGateway transit
    class SharedVPC,SharedPublic,SharedPrivate,SharedEndpoints shared
    class DevVPC,DevPublic,DevPrivate,DevEndpoints dev
    class StageVPC,StagePublic,StagePrivate,StageEndpoints stage
    class ProdVPC,ProdPublic,ProdPrivate,ProdEndpoints prod
```

## 4. DNS Architecture

```mermaid
graph TD
    classDef shared fill:#ccffcc,stroke:#333,stroke-width:1px
    classDef dev fill:#ccccff,stroke:#333,stroke-width:1px
    classDef stage fill:#ffffcc,stroke:#333,stroke-width:1px
    classDef prod fill:#ffccff,stroke:#333,stroke-width:1px
    
    RootZone[example.com Root Zone] -->|Delegation| DevZone[dev.example.com]
    RootZone -->|Delegation| StageZone[staging.example.com]
    RootZone -->|Delegation| ProdZone[example.com Production Records]
    
    DevZone -->|Contains| DevRecords[Development DNS Records]
    DevZone -->|Private Zone Association| DevVPC[Development VPC]
    
    StageZone -->|Contains| StageRecords[Staging DNS Records]
    StageZone -->|Private Zone Association| StageVPC[Staging VPC]
    
    ProdZone -->|Contains| ProdRecords[Production DNS Records]
    ProdZone -->|Private Zone Association| ProdVPC[Production VPC]
    
    DevVPC -->|Cross-Account Association| SharedVPC[Shared Services VPC]
    StageVPC -->|Cross-Account Association| SharedVPC
    ProdVPC -->|Cross-Account Association| SharedVPC
    
    subgraph "Shared Services Account"
        RootZone
        SharedVPC
    end
    
    subgraph "Development Account"
        DevZone
        DevRecords
        DevVPC
    end
    
    subgraph "Staging Account"
        StageZone
        StageRecords
        StageVPC
    end
    
    subgraph "Production Account"
        ProdZone
        ProdRecords
        ProdVPC
    end
    
    class RootZone,SharedVPC shared
    class DevZone,DevRecords,DevVPC dev
    class StageZone,StageRecords,StageVPC stage
    class ProdZone,ProdRecords,ProdVPC prod
```

## 5. Cross-Account IAM Access

```mermaid
graph TD
    classDef user fill:#bbdefb,stroke:#333,stroke-width:1px
    classDef group fill:#c8e6c9,stroke:#333,stroke-width:1px
    classDef role fill:#ffcc80,stroke:#333,stroke-width:1px
    classDef permission fill:#e1bee7,stroke:#333,stroke-width:1px
    
    User[IAM User] -->|Member Of| DevGroup[Developers Group]
    User -->|Member Of| OpsGroup[Operations Group]
    User -->|Member Of| AdminGroup[Administrators Group]
    
    DevGroup -->|Assume Role Permission| DevRole[Developer Role]
    OpsGroup -->|Assume Role Permission| OpsRole[Operations Role]
    AdminGroup -->|Assume Role Permission| AdminRole[Administrator Role]
    
    DevRole -->|In| DevAccount[Development Account]
    OpsRole -->|In| SharedAccount[Shared Services Account]
    OpsRole -->|In| DevAccount
    OpsRole -->|In| StagingAccount[Staging Account]
    OpsRole -->|In| ProdAccount[Production Account]
    AdminRole -->|In| ManagementAccount[Management Account]
    
    DevRole -->|Has| DevPerms[Developer Permissions]
    OpsRole -->|Has| OpsPerms[Operations Permissions]
    AdminRole -->|Has| AdminPerms[Administrator Permissions]
    
    DevPerms -->|Limited to| DevResources[Development Resources]
    OpsPerms -->|Access to| AllResources[All Environment Resources]
    AdminPerms -->|Organization-wide access to| OrgResources[Organization Resources]
    
    subgraph "Identity Account"
        User
        DevGroup
        OpsGroup
        AdminGroup
    end
    
    class User user
    class DevGroup,OpsGroup,AdminGroup group
    class DevRole,OpsRole,AdminRole role
    class DevPerms,OpsPerms,AdminPerms permission
```

## 6. Centralized Logging Architecture

```mermaid
graph TD
    classDef dev fill:#bbdefb,stroke:#333,stroke-width:1px
    classDef stage fill:#c8e6c9,stroke:#333,stroke-width:1px
    classDef prod fill:#ffcc80,stroke:#333,stroke-width:1px
    classDef log fill:#e1bee7,stroke:#333,stroke-width:1px
    classDef security fill:#ffcdd2,stroke:#333,stroke-width:1px
    
    DevLogs[Development Account Logs] -->|Streams to| CentralLogAccount[Central Logging Account]
    StageLogs[Staging Account Logs] -->|Streams to| CentralLogAccount
    ProdLogs[Production Account Logs] -->|Streams to| CentralLogAccount
    
    DevLogs -->|Contains| DevCloudTrail[CloudTrail Logs]
    DevLogs -->|Contains| DevCloudWatch[CloudWatch Logs]
    DevLogs -->|Contains| DevVPCFlow[VPC Flow Logs]
    DevLogs -->|Contains| DevS3Access[S3 Access Logs]
    DevLogs -->|Contains| DevALBLogs[ALB Access Logs]
    
    StageLogs -->|Contains| StageCloudTrail[CloudTrail Logs]
    StageLogs -->|Contains| StageCloudWatch[CloudWatch Logs]
    StageLogs -->|Contains| StageVPCFlow[VPC Flow Logs]
    StageLogs -->|Contains| StageS3Access[S3 Access Logs]
    StageLogs -->|Contains| StageALBLogs[ALB Access Logs]
    
    ProdLogs -->|Contains| ProdCloudTrail[CloudTrail Logs]
    ProdLogs -->|Contains| ProdCloudWatch[CloudWatch Logs]
    ProdLogs -->|Contains| ProdVPCFlow[VPC Flow Logs]
    ProdLogs -->|Contains| ProdS3Access[S3 Access Logs]
    ProdLogs -->|Contains| ProdALBLogs[ALB Access Logs]
    
    CentralLogAccount -->|Stores in| LoggingBucket[Centralized S3 Bucket]
    CentralLogAccount -->|Aggregates in| CloudWatchLogs[Centralized CloudWatch Logs]
    
    LoggingBucket -->|Lifecycle Policy| ArchiveBucket[Log Archive Bucket]
    LoggingBucket -->|Analyzed by| SecurityAccount[Security Account]
    CloudWatchLogs -->|Analyzed by| SecurityAccount
    
    SecurityAccount -->|Uses| SIEM[SIEM Solution]
    SecurityAccount -->|Configures| Alerts[Security Alerts]
    SecurityAccount -->|Runs| Compliance[Compliance Checks]
    
    class DevLogs,DevCloudTrail,DevCloudWatch,DevVPCFlow,DevS3Access,DevALBLogs dev
    class StageLogs,StageCloudTrail,StageCloudWatch,StageVPCFlow,StageS3Access,StageALBLogs stage
    class ProdLogs,ProdCloudTrail,ProdCloudWatch,ProdVPCFlow,ProdS3Access,ProdALBLogs prod
    class CentralLogAccount,LoggingBucket,CloudWatchLogs,ArchiveBucket log
    class SecurityAccount,SIEM,Alerts,Compliance security
```

## 7. Shared Services Architecture

```mermaid
graph TD
    classDef shared fill:#bbdefb,stroke:#333,stroke-width:1px
    classDef consumer fill:#c8e6c9,stroke:#333,stroke-width:1px
    
    SharedServices[Shared Services Account] -->|Provides| SharedInfra[Shared Infrastructure]
    
    SharedInfra -->|Includes| DNS[Route53 DNS]
    SharedInfra -->|Includes| Monitoring[Centralized Monitoring]
    SharedInfra -->|Includes| Backend[Terraform Backend]
    SharedInfra -->|Includes| ServiceCatalog[Service Catalog]
    SharedInfra -->|Includes| CodeArtifact[Code Artifact Repository]
    SharedInfra -->|Includes| ECR[Container Registry]
    SharedInfra -->|Includes| SSO[Single Sign-On]
    SharedInfra -->|Includes| SecretsMgr[Secrets Manager]
    SharedInfra -->|Includes| Networking[Shared Networking]
    
    DevAccount[Development Account] -->|Consumes| DNS
    StagingAccount[Staging Account] -->|Consumes| DNS
    ProdAccount[Production Account] -->|Consumes| DNS
    
    DevAccount -->|Consumes| Monitoring
    StagingAccount -->|Consumes| Monitoring
    ProdAccount -->|Consumes| Monitoring
    
    DevAccount -->|Consumes| Backend
    StagingAccount -->|Consumes| Backend
    ProdAccount -->|Consumes| Backend
    
    DevAccount -->|Consumes| ServiceCatalog
    StagingAccount -->|Consumes| ServiceCatalog
    ProdAccount -->|Consumes| ServiceCatalog
    
    DevAccount -->|Consumes| CodeArtifact
    StagingAccount -->|Consumes| CodeArtifact
    ProdAccount -->|Consumes| CodeArtifact
    
    DevAccount -->|Consumes| ECR
    StagingAccount -->|Consumes| ECR
    ProdAccount -->|Consumes| ECR
    
    DevAccount -->|Consumes| SSO
    StagingAccount -->|Consumes| SSO
    ProdAccount -->|Consumes| SSO
    
    DevAccount -->|Consumes| SecretsMgr
    StagingAccount -->|Consumes| SecretsMgr
    ProdAccount -->|Consumes| SecretsMgr
    
    DevAccount -->|Consumes| Networking
    StagingAccount -->|Consumes| Networking
    ProdAccount -->|Consumes| Networking
    
    class SharedServices,SharedInfra,DNS,Monitoring,Backend,ServiceCatalog,CodeArtifact,ECR,SSO,SecretsMgr,Networking shared
    class DevAccount,StagingAccount,ProdAccount consumer
```

## 8. Security Controls Architecture

```mermaid
graph TD
    classDef security fill:#ffcdd2,stroke:#333,stroke-width:1px
    classDef control fill:#c8e6c9,stroke:#333,stroke-width:1px
    classDef resource fill:#bbdefb,stroke:#333,stroke-width:1px
    
    SecurityAccount[Security Account] -->|Manages| SecurityControls[Security Controls]
    
    SecurityControls -->|Includes| IAMPolicies[IAM Policies]
    SecurityControls -->|Includes| SCPs[Service Control Policies]
    SecurityControls -->|Includes| GuardDuty[GuardDuty]
    SecurityControls -->|Includes| SecurityHub[Security Hub]
    SecurityControls -->|Includes| Config[AWS Config]
    SecurityControls -->|Includes| Firewall[AWS Network Firewall]
    SecurityControls -->|Includes| CloudTrail[CloudTrail]
    SecurityControls -->|Includes| IAMAccessAnalyzer[IAM Access Analyzer]
    SecurityControls -->|Includes| Inspector[Inspector]
    SecurityControls -->|Includes| Macie[Macie]
    
    IAMPolicies -->|Applied to| Accounts[All Accounts]
    SCPs -->|Enforces| OrganizationPolicies[Organization Policies]
    GuardDuty -->|Monitors| AWSResources[AWS Resources]
    SecurityHub -->|Aggregates| SecurityFindings[Security Findings]
    Config -->|Tracks| ResourceCompliance[Resource Compliance]
    Firewall -->|Protects| NetworkTraffic[Network Traffic]
    CloudTrail -->|Logs| APIActivity[API Activity]
    IAMAccessAnalyzer -->|Analyzes| AccessPaths[Resource Access]
    Inspector -->|Scans| Vulnerabilities[Vulnerabilities]
    Macie -->|Discovers| SensitiveData[Sensitive Data]
    
    class SecurityAccount,SecurityControls security
    class IAMPolicies,SCPs,GuardDuty,SecurityHub,Config,Firewall,CloudTrail,IAMAccessAnalyzer,Inspector,Macie control
    class Accounts,OrganizationPolicies,AWSResources,SecurityFindings,ResourceCompliance,NetworkTraffic,APIActivity,AccessPaths,Vulnerabilities,SensitiveData resource
```

## 9. CI/CD Pipeline Architecture

```mermaid
graph TD
    classDef tools fill:#bbdefb,stroke:#333,stroke-width:1px
    classDef artifact fill:#c8e6c9,stroke:#333,stroke-width:1px
    classDef deploy fill:#ffcc80,stroke:#333,stroke-width:1px
    classDef env fill:#e1bee7,stroke:#333,stroke-width:1px
    
    Developer[Developer] -->|Commits Code| Git[Git Repository]
    
    Git -->|Triggers| Pipeline[CI/CD Pipeline]
    
    Pipeline -->|Build Phase| CodeBuild[AWS CodeBuild]
    Pipeline -->|Test Phase| Testing[Automated Testing]
    Pipeline -->|Deploy Phase| CodeDeploy[AWS CodeDeploy]
    
    CodeBuild -->|Produces| Artifacts[Build Artifacts]
    Testing -->|Validates| Artifacts
    
    Artifacts -->|Stored in| S3[S3 Artifact Bucket]
    Artifacts -->|Stored in| ECR[ECR Container Registry]
    
    S3 -->|Used by| CodeDeploy
    ECR -->|Used by| CodeDeploy
    
    CodeDeploy -->|Deploys to| DevAccount[Development Account]
    CodeDeploy -->|Deploys to| StagingAccount[Staging Account]
    CodeDeploy -->|Deploys to| ProdAccount[Production Account]
    
    AtmosWorkflow[Atmos Workflow] -->|Manages| TerraformApply[Terraform Apply]
    TerraformApply -->|Updates| DevAccount
    TerraformApply -->|Updates| StagingAccount
    TerraformApply -->|Updates| ProdAccount
    
    class Git,Pipeline,CodeBuild,Testing,CodeDeploy,AtmosWorkflow,TerraformApply tools
    class Artifacts,S3,ECR artifact
    class Developer deploy
    class DevAccount,StagingAccount,ProdAccount env
```

## 10. Multi-Region Architecture

```mermaid
graph TD
    classDef primary fill:#bbdefb,stroke:#333,stroke-width:1px
    classDef secondary fill:#c8e6c9,stroke:#333,stroke-width:1px
    classDef global fill:#ffcc80,stroke:#333,stroke-width:1px
    
    GlobalServices[Global AWS Services] -->|Used by| PrimaryRegion[Primary Region]
    GlobalServices -->|Used by| SecondaryRegion[Secondary Region]
    
    GlobalServices -->|Includes| Route53[Route53]
    GlobalServices -->|Includes| IAM[IAM]
    GlobalServices -->|Includes| CloudFront[CloudFront]
    GlobalServices -->|Includes| WAF[WAF]
    
    PrimaryRegion -->|Contains| PrimaryVPC[Primary VPC]
    PrimaryRegion -->|Contains| PrimaryRDS[Primary RDS]
    PrimaryRegion -->|Contains| PrimaryEKS[Primary EKS]
    PrimaryRegion -->|Contains| PrimaryLambda[Primary Lambda]
    
    SecondaryRegion -->|Contains| SecondaryVPC[Secondary VPC]
    SecondaryRegion -->|Contains| SecondaryRDS[Secondary RDS]
    SecondaryRegion -->|Contains| SecondaryEKS[Secondary EKS]
    SecondaryRegion -->|Contains| SecondaryLambda[Secondary Lambda]
    
    PrimaryVPC -->|Peered with| SecondaryVPC
    PrimaryRDS -->|Replicates to| SecondaryRDS
    
    Route53 -->|DNS Failover| PrimaryELB[Primary Load Balancer]
    Route53 -->|DNS Failover| SecondaryELB[Secondary Load Balancer]
    
    PrimaryELB -->|Routes to| PrimaryEKS
    SecondaryELB -->|Routes to| SecondaryEKS
    
    CloudFront -->|Origin| PrimaryELB
    CloudFront -->|Origin| SecondaryELB
    
    DynamoDB[DynamoDB Global Tables] -->|Replicates between| PrimaryRegion
    DynamoDB -->|Replicates between| SecondaryRegion
    
    S3Replication[S3 Cross-Region Replication] -->|Copies from| PrimaryS3[Primary S3 Bucket]
    S3Replication -->|Copies to| SecondaryS3[Secondary S3 Bucket]
    
    class PrimaryRegion,PrimaryVPC,PrimaryRDS,PrimaryEKS,PrimaryLambda,PrimaryELB,PrimaryS3 primary
    class SecondaryRegion,SecondaryVPC,SecondaryRDS,SecondaryEKS,SecondaryLambda,SecondaryELB,SecondaryS3 secondary
    class GlobalServices,Route53,IAM,CloudFront,WAF,DynamoDB,S3Replication global
```