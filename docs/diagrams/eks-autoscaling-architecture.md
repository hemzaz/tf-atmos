# EKS Autoscaling Architecture

This document provides architectural diagrams for AWS EKS autoscaling using Karpenter and KEDA.

## 1. Autoscaling Components Overview

```mermaid
graph TD
    classDef podScaler fill:#3F8624,stroke:#2E5B1A,color:white;
    classDef nodeScaler fill:#FF9900,stroke:#232F3E,color:white;
    classDef k8sComponent fill:#326CE5,stroke:#2152A3,color:white;
    classDef awsComponent fill:#FF9900,stroke:#232F3E,color:white;
    classDef workload fill:#6B6B6B,stroke:#4A4A4A,color:white;

    KEDA[KEDA] -->|Creates| HPA[Horizontal Pod Autoscaler]:::k8sComponent
    KEDA:::podScaler --> EM[External Metrics]
    EM --> SQS[AWS SQS]:::awsComponent
    EM --> CW[AWS CloudWatch]:::awsComponent
    EM --> DDB[AWS DynamoDB]:::awsComponent
    
    HPA -->|Scales| Pods[Application Pods]:::workload
    Pods -->|May become<br>unschedulable| K[Karpenter]:::nodeScaler
    
    K -->|Creates| Nodes[EC2 Nodes]:::awsComponent
    K -->|References| NP[NodePool]:::k8sComponent
    K -->|References| ENC[EC2NodeClass]:::k8sComponent
    
    NP -->|Defines| Reqs[Node Requirements]
    ENC -->|Configures| EC2Cfg[EC2 Config]
    
    Nodes -->|Run| Pods
    
    subgraph "Pod Scaling"
        KEDA
        HPA
        EM
        Pods
    end
    
    subgraph "Node Scaling"
        K
        NP
        ENC
        Nodes
    end
    
    subgraph "AWS Resources"
        SQS
        CW
        DDB
    end
</figure>
```

## 2. Karpenter Provisioning Flow

```mermaid
sequenceDiagram
    participant App as Application
    participant API as Kubernetes API
    participant K as Karpenter
    participant NP as NodePool
    participant ENC as EC2NodeClass
    participant AWS as AWS EC2 API
    
    App->>API: Create Pod
    activate API
    API->>API: Cannot schedule Pod
    API->>K: Pod Pending (Unschedulable)
    deactivate API
    
    activate K
    K->>NP: Get Node Requirements
    NP-->>K: Node Constraints
    
    K->>ENC: Get EC2 Configuration
    ENC-->>K: EC2 Instance Settings
    
    K->>K: Create optimized LaunchTemplate
    K->>AWS: Launch EC2 Instance(s)
    deactivate K
    
    activate AWS
    AWS-->>K: Instance Launching
    AWS->>API: Node Joins Cluster
    deactivate AWS
    
    activate API
    API->>API: Schedule Pod to New Node
    API-->>App: Pod Running
    deactivate API
</figure>
```

## 3. KEDA Scaling Flow

```mermaid
sequenceDiagram
    participant Source as Event Source (SQS/CloudWatch)
    participant KEDA as KEDA Operator
    participant Metrics as Metrics Adapter
    participant HPA as Horizontal Pod Autoscaler
    participant API as Kubernetes API
    participant Deployment as Application Deployment
    
    KEDA->>KEDA: Watch ScaledObjects
    
    activate KEDA
    KEDA->>HPA: Create/Update HPA for Deployment
    KEDA->>Metrics: Register External Metrics
    deactivate KEDA
    
    loop Every pollingInterval
        activate Metrics
        Metrics->>Source: Query Metrics/Events
        Source-->>Metrics: Return Current Values
        Metrics->>HPA: Expose Metrics
        deactivate Metrics
        
        activate HPA
        HPA->>HPA: Compare metrics to targets
        HPA->>API: Scale Deployment Replicas
        deactivate HPA
        
        activate API
        API->>Deployment: Update Replica Count
        API-->>HPA: Deployment Scaled
        deactivate API
    end
</figure>
```

## 4. Combined Autoscaling Process

```mermaid
graph TD
    classDef trigger fill:#1F78B4,stroke:#12537E,color:white;
    classDef kedaComponent fill:#3F8624,stroke:#2E5B1A,color:white;
    classDef karpenterComponent fill:#FF9900,stroke:#232F3E,color:white;
    classDef k8sComponent fill:#326CE5,stroke:#2152A3,color:white;
    classDef awsComponent fill:#FF9900,stroke:#232F3E,color:white;

    Start[External Event]:::trigger -->|Triggers| KEDA[KEDA ScaledObject]:::kedaComponent
    KEDA -->|Updates| HPA[HPA]:::k8sComponent
    HPA -->|Scales| Deploy[Deployment]:::k8sComponent
    Deploy -->|Creates| Pods[Pending Pods]:::k8sComponent
    
    Pods -->|Triggers| Karpenter[Karpenter]:::karpenterComponent
    Karpenter -->|Consults| NP[NodePool]:::k8sComponent
    Karpenter -->|Consults| ENC[EC2NodeClass]:::k8sComponent
    
    Karpenter -->|Provisions| Nodes[EC2 Nodes]:::awsComponent
    Nodes -->|Enables scheduling of| Pods
    
    NP -->|Defines| Req[Pod Requirements]
    ENC -->|Defines| AWS[AWS Configuration]
    
    subgraph "Pod Autoscaling (KEDA)"
        KEDA
        HPA
        Deploy
    end
    
    subgraph "Node Autoscaling (Karpenter)"
        Karpenter
        NP
        ENC
    end
</figure>
```

## 5. Resource Optimization Flow

```mermaid
graph TD
    classDef scaleUp fill:#3F8624,stroke:#2E5B1A,color:white;
    classDef scaleDown fill:#D9822B,stroke:#A35E1C,color:white;
    classDef state fill:#1F78B4,stroke:#12537E,color:white;
    classDef action fill:#7A4C9F,stroke:#5A3976,color:white;

    Start[Normal State]:::state -->|Traffic Increases| IncMetric[Metrics Increase]:::scaleUp
    IncMetric -->|KEDA Detects| ScalePods[Scale Pods Up]:::action
    ScalePods -->|Create Pods| NeedNodes[Need More Nodes?]
    
    NeedNodes -->|Yes| Provision[Karpenter Provisions Nodes]:::action
    NeedNodes -->|No| Schedule[Schedule Pods on Existing Nodes]:::action
    
    Provision --> Schedule
    Schedule -->|Pods Running| HighLoad[High Load State]:::state
    
    HighLoad -->|Traffic Decreases| DecMetric[Metrics Decrease]:::scaleDown
    DecMetric -->|KEDA Detects| ReducePods[Scale Pods Down]:::action
    ReducePods -->|Remove Pods| EmptyNode[Nodes Underutilized?]
    
    EmptyNode -->|Yes| Deprovision[Karpenter Consolidates/Removes Nodes]:::action
    EmptyNode -->|No| LowLoad[Lower Load State]:::state
    
    Deprovision --> LowLoad
    LowLoad -->|Minimum reached| Start
</figure>
```

## 6. Multi-Environment Autoscaling Architecture

```mermaid
graph TD
    classDef dev fill:#3F8624,stroke:#2E5B1A,color:white;
    classDef prod fill:#D9822B,stroke:#A35E1C,color:white;
    classDef shared fill:#1F78B4,stroke:#12537E,color:white;
    classDef component fill:#7A4C9F,stroke:#5A3976,color:white;

    subgraph "Management Account"
        TFState[Terraform State]:::shared
        Config[Atmos Configuration]:::shared
    end
    
    Config --> |Define| Components[Addon Components]:::component
    Components --> |Define| DevAddons[Development Addons]:::dev
    Components --> |Define| ProdAddons[Production Addons]:::prod
    
    subgraph "Development Account"
        DevKEDA[KEDA]:::dev
        DevKarpenter[Karpenter]:::dev
        DevAddons --> DevKEDA
        DevAddons --> DevKarpenter
        
        DevKarpenter --> |Provision| DevNodes[Dev EC2 Nodes]:::dev
        DevKEDA --> |Scale| DevPods[Dev Pods]:::dev
    end
    
    subgraph "Production Account"
        ProdKEDA[KEDA]:::prod
        ProdKarpenter[Karpenter]:::prod
        ProdAddons --> ProdKEDA
        ProdAddons --> ProdKarpenter
        
        ProdKarpenter --> |Provision| ProdNodes[Prod EC2 Nodes]:::prod
        ProdKEDA --> |Scale| ProdPods[Prod Pods]:::prod
    end
    
    Components --> |Store| TFState
</figure>
```