# AWS Infrastructure Architecture - Optimized Design

## High-Level Architecture Diagram

```mermaid
graph TB
    subgraph "Multi-Account Organization"
        subgraph "Management Account"
            ORG[AWS Organizations]
            BILLING[Consolidated Billing]
            SCT[Service Control Policies]
        end
        
        subgraph "Network Account"
            TGW[Transit Gateway]
            VPCEND[VPC Endpoints]
            DX[Direct Connect]
        end
        
        subgraph "Development Account"
            subgraph "Dev VPC - 10.0.0.0/16"
                DEV_PUB[Public Subnets<br/>10.0.1.0/24 - 10.0.3.0/24]
                DEV_PRIV[Private Subnets<br/>10.0.10.0/24 - 10.0.12.0/24]
                DEV_DB[Database Subnets<br/>10.0.20.0/24 - 10.0.22.0/24]
                DEV_NAT[Single NAT Gateway]
                DEV_ALB[Application Load Balancer]
            end
            
            subgraph "Dev Compute"
                DEV_EKS[EKS Cluster<br/>Spot: 70%<br/>On-Demand: 30%]
                DEV_NODES[Node Groups<br/>t3.medium spot<br/>Auto-shutdown]
            end
            
            subgraph "Dev Data"
                DEV_RDS[Aurora Serverless v2<br/>Min: 0.5 ACU<br/>Auto-pause: 10min]
                DEV_CACHE[ElastiCache<br/>t3.micro]
            end
        end
        
        subgraph "Staging Account"
            subgraph "Staging VPC - 10.1.0.0/16"
                STG_PUB[Public Subnets<br/>10.1.1.0/24 - 10.1.3.0/24]
                STG_PRIV[Private Subnets<br/>10.1.10.0/24 - 10.1.12.0/24]
                STG_DB[Database Subnets<br/>10.1.20.0/24 - 10.1.22.0/24]
                STG_NAT[Single NAT Gateway]
                STG_ALB[Application Load Balancer]
            end
            
            subgraph "Staging Compute"
                STG_EKS[EKS Cluster<br/>Spot: 50%<br/>Reserved: 30%<br/>On-Demand: 20%]
                STG_NODES[Node Groups<br/>t3.large mixed<br/>Business hours only]
            end
            
            subgraph "Staging Data"
                STG_RDS[Aurora MySQL<br/>db.t3.medium<br/>No Multi-AZ]
                STG_CACHE[ElastiCache<br/>cache.t3.small]
            end
        end
        
        subgraph "Production Account"
            subgraph "Prod VPC - 10.2.0.0/16"
                PRD_PUB[Public Subnets<br/>10.2.1.0/24 - 10.2.3.0/24]
                PRD_PRIV[Private Subnets<br/>10.2.10.0/24 - 10.2.12.0/24]
                PRD_DB[Database Subnets<br/>10.2.20.0/24 - 10.2.22.0/24]
                PRD_NAT[3x NAT Gateways<br/>One per AZ]
                PRD_ALB[Application Load Balancer<br/>Multi-AZ]
                PRD_NLB[Network Load Balancer]
            end
            
            subgraph "Prod Compute"
                PRD_EKS[EKS Cluster<br/>Reserved: 60%<br/>Savings Plans: 30%<br/>On-Demand: 10%]
                PRD_NODES[Node Groups<br/>m5.xlarge reserved<br/>Karpenter managed]
            end
            
            subgraph "Prod Data"
                PRD_RDS[Aurora MySQL<br/>db.r5.xlarge<br/>Multi-AZ<br/>2 Read Replicas]
                PRD_CACHE[ElastiCache Redis<br/>cache.r6g.large<br/>Cluster mode]
            end
        end
        
        subgraph "Shared Services Account"
            subgraph "Monitoring & Logging"
                CW[CloudWatch<br/>Dashboards]
                XRAY[X-Ray<br/>Tracing]
                ES[OpenSearch<br/>Log Analytics]
            end
            
            subgraph "Security & Compliance"
                SM[Secrets Manager]
                KMS[KMS Keys]
                CONFIG[AWS Config]
                GUARD[GuardDuty]
            end
            
            subgraph "Cost Management"
                COST[Cost Explorer]
                BUDGET[Budgets & Alerts]
                SAVINGS[Savings Plans]
                RI[Reserved Instances]
            end
        end
    end
    
    subgraph "External Services"
        CF[CloudFront CDN]
        R53[Route 53 DNS]
        S3[S3 Buckets<br/>Intelligent Tiering]
        ECR[ECR Registry]
    end
    
    %% Network Connections
    TGW -.-> DEV_PRIV
    TGW -.-> STG_PRIV
    TGW -.-> PRD_PRIV
    
    %% Internet Access
    DEV_NAT --> Internet
    STG_NAT --> Internet
    PRD_NAT --> Internet
    
    %% Load Balancer Connections
    CF --> PRD_ALB
    R53 --> CF
    
    %% VPC Endpoints
    VPCEND -.-> S3
    VPCEND -.-> ECR
    VPCEND -.-> SM
    
    classDef production fill:#ff9999
    classDef staging fill:#ffcc99
    classDef development fill:#99ccff
    classDef shared fill:#99ff99
    classDef external fill:#ffff99
    
    class PRD_EKS,PRD_RDS,PRD_CACHE,PRD_NAT production
    class STG_EKS,STG_RDS,STG_CACHE,STG_NAT staging
    class DEV_EKS,DEV_RDS,DEV_CACHE,DEV_NAT development
    class CW,XRAY,ES,SM,KMS,CONFIG,GUARD,COST,BUDGET,SAVINGS,RI shared
    class CF,R53,S3,ECR external
```

## Cost Optimization Architecture

```mermaid
graph LR
    subgraph "Cost Optimization Components"
        subgraph "Compute Optimization"
            SPOT[Spot Instances<br/>Dev: 70%<br/>Staging: 50%<br/>Prod: 20%]
            RI_COMP[Reserved Instances<br/>3-year term<br/>Production only]
            SP[Savings Plans<br/>Compute SP<br/>1-year term]
            KARP[Karpenter<br/>Dynamic provisioning<br/>Bin packing]
        end
        
        subgraph "Auto-Scaling"
            HPA[Horizontal Pod Autoscaler<br/>CPU/Memory triggers]
            VPA[Vertical Pod Autoscaler<br/>Right-sizing pods]
            KEDA[KEDA Autoscaler<br/>Event-driven scaling]
            CA[Cluster Autoscaler<br/>Node scaling]
        end
        
        subgraph "Storage Optimization"
            GP3[GP3 Volumes<br/>20% cheaper than GP2]
            S3_LIFE[S3 Lifecycle<br/>IA: 30 days<br/>Glacier: 90 days]
            SNAP[Snapshot Management<br/>Auto-cleanup: 30 days]
            INTEL[Intelligent Tiering<br/>Automatic optimization]
        end
        
        subgraph "Database Optimization"
            AURORA_SL[Aurora Serverless<br/>Dev/Staging<br/>Auto-pause]
            READ_REP[Read Replicas<br/>Auto-scaling<br/>Cross-AZ]
            BACKUP[Backup Optimization<br/>7-day retention<br/>Cross-region]
        end
        
        subgraph "Network Optimization"
            NAT_OPT[NAT Gateway<br/>Single for non-prod<br/>Multi-AZ for prod]
            VPC_EP[VPC Endpoints<br/>S3, DynamoDB, ECR<br/>Reduce transfer costs]
            CDN[CloudFront<br/>Edge caching<br/>Compression]
        end
        
        subgraph "Automation"
            SCHED[Instance Scheduler<br/>Start/Stop EC2/RDS<br/>Business hours only]
            CLEANUP[Resource Cleanup<br/>Weekly execution<br/>Unused resources]
            ANOMALY[Anomaly Detection<br/>Cost spikes<br/>Auto-alerts]
        end
    end
    
    SPOT --> KARP
    KARP --> CA
    CA --> HPA
    HPA --> KEDA
    
    SCHED --> AURORA_SL
    CLEANUP --> SNAP
    ANOMALY --> BUDGET[Budget Alerts]
```

## Kubernetes Architecture (EKS)

```mermaid
graph TB
    subgraph "EKS Control Plane (Managed)"
        API[API Server]
        ETCD[etcd]
        SCHED[Scheduler]
        CM[Controller Manager]
    end
    
    subgraph "Node Groups"
        subgraph "System Node Group"
            SYS1[Node 1<br/>Reserved Instance]
            SYS2[Node 2<br/>Reserved Instance]
            SYS3[Node 3<br/>Reserved Instance]
        end
        
        subgraph "Application Node Group"
            APP1[Node 1<br/>Spot Instance]
            APP2[Node 2<br/>Spot Instance]
            APP3[Node 3<br/>On-Demand]
        end
        
        subgraph "Batch Node Group"
            BATCH1[Node 1<br/>Spot Instance]
            BATCH2[Node 2<br/>Spot Instance]
        end
    end
    
    subgraph "Add-ons & Controllers"
        subgraph "Networking"
            ALB_CTRL[AWS Load Balancer Controller]
            ISTIO[Istio Service Mesh]
            EXTDNS[External DNS]
        end
        
        subgraph "Scaling"
            KARPENTER[Karpenter]
            KEDA_CTRL[KEDA]
            HPA_CTRL[HPA Controller]
        end
        
        subgraph "Security"
            CERT[Cert Manager]
            SECRETS[External Secrets Operator]
            POL[Network Policies]
        end
        
        subgraph "Observability"
            PROM[Prometheus]
            FLUENTBIT[Fluent Bit]
            ADOT[ADOT Collector]
        end
    end
    
    API --> SYS1
    API --> APP1
    API --> BATCH1
    
    KARPENTER --> APP1
    KARPENTER --> BATCH1
    
    ALB_CTRL --> ISTIO
    CERT --> SECRETS
    PROM --> ADOT
```

## Data Flow Architecture

```mermaid
sequenceDiagram
    participant User
    participant CloudFront
    participant ALB
    participant EKS
    participant RDS
    participant ElastiCache
    participant S3
    
    User->>CloudFront: HTTPS Request
    CloudFront->>CloudFront: Check Cache
    alt Cache Hit
        CloudFront->>User: Cached Response
    else Cache Miss
        CloudFront->>ALB: Forward Request
        ALB->>EKS: Route to Pod
        EKS->>ElastiCache: Check Cache
        alt Data in Cache
            ElastiCache->>EKS: Return Cached Data
        else Data not in Cache
            EKS->>RDS: Query Database
            RDS->>EKS: Return Data
            EKS->>ElastiCache: Update Cache
        end
        EKS->>S3: Store Static Assets
        S3->>CloudFront: Serve Assets
        EKS->>ALB: Response
        ALB->>CloudFront: Response
        CloudFront->>CloudFront: Update Cache
        CloudFront->>User: Response
    end
```

## Disaster Recovery Architecture

```mermaid
graph TB
    subgraph "Primary Region (us-west-2)"
        subgraph "Production"
            PRIM_EKS[EKS Cluster]
            PRIM_RDS[Aurora MySQL<br/>Writer]
            PRIM_S3[S3 Bucket<br/>Versioning Enabled]
        end
        
        subgraph "Backup"
            VELERO[Velero<br/>K8s Backup]
            SNAPSHOT[RDS Snapshots<br/>Daily]
        end
    end
    
    subgraph "DR Region (us-east-1)"
        subgraph "Standby"
            DR_EKS[EKS Cluster<br/>Minimal Size]
            DR_RDS[Aurora MySQL<br/>Read Replica]
            DR_S3[S3 Bucket<br/>Cross-Region Replication]
        end
        
        subgraph "DR Activation"
            PROMOTE[Promote Read Replica]
            SCALE[Scale EKS Nodes]
            DNS_SWITCH[Update Route 53]
        end
    end
    
    PRIM_RDS -.->|Async Replication| DR_RDS
    PRIM_S3 -.->|Cross-Region Replication| DR_S3
    VELERO -->|Backup to S3| PRIM_S3
    SNAPSHOT -->|Copy Snapshots| DR_RDS
    
    DR_RDS -->|On Failure| PROMOTE
    DR_EKS -->|On Failure| SCALE
    PROMOTE --> DNS_SWITCH
    SCALE --> DNS_SWITCH
```

## Security Architecture

```mermaid
graph TB
    subgraph "Security Layers"
        subgraph "Edge Security"
            WAF[AWS WAF<br/>OWASP Rules]
            SHIELD[AWS Shield<br/>DDoS Protection]
            CF_SEC[CloudFront<br/>Geo-blocking]
        end
        
        subgraph "Network Security"
            NACL[Network ACLs<br/>Subnet Level]
            SG[Security Groups<br/>Instance Level]
            PRIV[Private Subnets<br/>No Internet Gateway]
        end
        
        subgraph "Application Security"
            ISTIO_SEC[Istio mTLS<br/>Service-to-Service]
            RBAC[K8s RBAC<br/>Fine-grained Access]
            POD_SEC[Pod Security Policies]
        end
        
        subgraph "Data Security"
            KMS_ENC[KMS Encryption<br/>At Rest]
            TLS[TLS 1.3<br/>In Transit]
            SECRETS_MGR[Secrets Manager<br/>Rotation]
        end
        
        subgraph "Compliance & Monitoring"
            CONFIG[AWS Config<br/>Compliance Rules]
            GUARD[GuardDuty<br/>Threat Detection]
            TRAIL[CloudTrail<br/>Audit Logs]
        end
    end
    
    WAF --> CF_SEC
    CF_SEC --> SHIELD
    SHIELD --> NACL
    NACL --> SG
    SG --> PRIV
    PRIV --> ISTIO_SEC
    ISTIO_SEC --> RBAC
    RBAC --> POD_SEC
    POD_SEC --> KMS_ENC
    KMS_ENC --> TLS
    TLS --> SECRETS_MGR
    
    CONFIG --> GUARD
    GUARD --> TRAIL
```

## Cost Breakdown by Environment

| Component | Development | Staging | Production |
|-----------|------------|---------|------------|
| **Compute (EKS)** | | | |
| Instance Strategy | 70% Spot, 30% On-Demand | 50% Spot, 30% RI, 20% On-Demand | 60% RI, 30% SP, 10% On-Demand |
| Node Count | 1-10 (auto-scale) | 2-15 (auto-scale) | 3-30 (auto-scale) |
| Instance Types | t3.medium | t3.large | m5.xlarge |
| Monthly Cost | ~$300 | ~$800 | ~$4,000 |
| **Database (RDS)** | | | |
| Type | Aurora Serverless v2 | Aurora MySQL | Aurora MySQL Multi-AZ |
| Instance Class | 0.5-2 ACU | db.t3.medium | db.r5.xlarge |
| Read Replicas | 0 | 0 | 2 |
| Monthly Cost | ~$100 | ~$200 | ~$1,500 |
| **Storage** | | | |
| EBS Type | gp3 | gp3 | gp3 + io2 |
| S3 Lifecycle | Aggressive | Moderate | Conservative |
| Monthly Cost | ~$50 | ~$150 | ~$500 |
| **Network** | | | |
| NAT Gateways | 1 | 1 | 3 |
| Data Transfer | Minimal | Moderate | High |
| Monthly Cost | ~$45 | ~$45 | ~$135 |
| **Total Monthly** | **~$495** | **~$1,195** | **~$6,135** |

## Implementation Timeline

```mermaid
gantt
    title Infrastructure Optimization Timeline
    dateFormat  YYYY-MM-DD
    section Phase 1 - Quick Wins
    GP3 Volume Migration           :done, p1-1, 2025-01-15, 3d
    S3 Intelligent Tiering         :done, p1-2, 2025-01-15, 2d
    Delete Unused Resources        :active, p1-3, 2025-01-18, 2d
    Dev Auto-Shutdown              :active, p1-4, 2025-01-20, 3d
    Spot Instances (Dev)           :p1-5, 2025-01-23, 5d
    
    section Phase 2 - Core Optimizations
    Deploy Karpenter               :p2-1, 2025-01-28, 5d
    Aurora Serverless (Dev/Stg)   :p2-2, 2025-02-02, 4d
    VPC Endpoints                  :p2-3, 2025-02-06, 3d
    KEDA Implementation            :p2-4, 2025-02-09, 5d
    NAT Gateway Consolidation      :p2-5, 2025-02-14, 2d
    
    section Phase 3 - Advanced
    Reserved Instances Purchase    :p3-1, 2025-02-16, 3d
    Savings Plans                  :p3-2, 2025-02-19, 2d
    CloudFront CDN                 :p3-3, 2025-02-21, 4d
    ElastiCache Implementation     :p3-4, 2025-02-25, 5d
    Istio Optimization             :p3-5, 2025-03-02, 3d
    
    section Phase 4 - Continuous
    FinOps Dashboard               :p4-1, 2025-03-05, 5d
    Cost Anomaly Detection         :p4-2, 2025-03-10, 3d
    Automated Rightsizing          :p4-3, 2025-03-13, 5d
    Quarterly Reviews              :milestone, p4-4, 2025-03-31, 0d
```

---

**Document Version**: 1.0  
**Created**: 2025-08-16  
**Architecture Review Cycle**: Quarterly  
**Next Review**: Q2 2025