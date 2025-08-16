# Agent-Specific Context Summaries

## Context for Backend Architect Agent

### Your Focus Areas
- Design scalable API architecture supporting GraphQL, REST, and WebSocket
- Create data models for service catalog, cost management, and compliance
- Build integration patterns with existing Terraform/Atmos infrastructure
- Design event-driven architecture for platform events

### Key Context
```yaml
existing_infrastructure:
  terraform_components: 17
  atmos_workflows: 16
  python_cli: gaia
  current_gap: No platform APIs exist

your_deliverables:
  - GraphQL schema for platform operations
  - REST API specifications (OpenAPI 3.0)
  - WebSocket event definitions
  - Database schemas (PostgreSQL)
  - Integration patterns with Atmos
  - Service mesh configuration

integration_points:
  atmos_api:
    endpoint: http://platform-api:8000/api/v1/atmos
    operations: [provision, destroy, plan, apply]
  
  service_catalog:
    storage: PostgreSQL
    cache: Redis
    search: Elasticsearch

performance_requirements:
  api_latency_p99: < 200ms
  throughput: 10000 req/sec
  availability: 99.95%
```

### Critical Decisions Needed
1. API versioning strategy (header vs URL)
2. Event sourcing vs state-based architecture
3. Synchronous vs asynchronous provisioning
4. Multi-tenant data isolation approach

---

## Context for Frontend Developer Agent

### Your Focus Areas
- Build accessible Backstage UI components (WCAG 2.1 AA)
- Create responsive design for desktop and mobile
- Implement real-time updates via WebSocket
- Design intuitive service catalog interface

### Key Context
```yaml
ui_requirements:
  framework: React (Backstage)
  accessibility: WCAG 2.1 AA mandatory
  design_system: Material-UI based
  responsive: Mobile-first approach

key_interfaces:
  service_catalog:
    - Browse/search services
    - One-click provisioning
    - Cost estimation display
    - Approval workflows
  
  developer_dashboard:
    - Resource overview
    - Deployment status
    - Cost tracking
    - Compliance alerts

accessibility_requirements:
  - Keyboard navigation: Full support
  - Screen readers: NVDA/JAWS tested
  - Color contrast: 4.5:1 minimum
  - Focus indicators: Visible always
  - Alt text: All images
  - ARIA labels: All interactive elements

real_time_features:
  - Deployment progress
  - Cost alerts
  - Compliance violations
  - Resource provisioning status
```

### Critical Decisions Needed
1. Component library architecture
2. State management approach (Redux vs Context)
3. Real-time update strategy
4. Progressive enhancement approach

---

## Context for Deployment Engineer Agent

### Your Focus Areas
- Containerize all platform components
- Design CI/CD pipelines for platform and services
- Implement blue-green and canary deployments
- Create local development environment

### Key Context
```yaml
deployment_targets:
  local:
    orchestration: Docker Compose
    services: [postgres, redis, minio, localstack]
    resources: 8GB RAM, 4 CPU cores
  
  production:
    orchestration: Kubernetes/EKS
    services: [RDS, ElastiCache, S3, AWS Services]
    scaling: Horizontal auto-scaling

existing_cicd:
  current:
    - Atlantis for Terraform PRs
    - Jenkins pipelines
    - Pre-commit hooks
  
  needed:
    - GitOps with ArgoCD
    - Progressive delivery with Flagger
    - Automated rollbacks

container_requirements:
  base_images: Distroless/Alpine
  security_scanning: Trivy/Snyk
  registry: ECR with vulnerability scanning
  orchestration: Helm charts

deployment_strategies:
  blue_green: Required for critical services
  canary: 10% -> 50% -> 100% progression
  feature_flags: LaunchDarkly integration
  rollback: Automated on metrics degradation
```

### Critical Decisions Needed
1. GitOps tool selection (ArgoCD vs Flux)
2. Service mesh choice (Istio vs Linkerd)
3. Secrets management approach
4. Multi-region deployment strategy

---

## Context for Cloud Architect Agent

### Your Focus Areas
- Design enterprise-grade AWS infrastructure
- Implement security and compliance controls
- Optimize costs and resource utilization
- Ensure high availability and disaster recovery

### Key Context
```yaml
aws_foundation:
  existing:
    - VPC with public/private subnets
    - EKS clusters with addons
    - RDS for databases
    - IAM roles and policies
    - Secrets Manager/SSM
  
  required:
    - Multi-region setup
    - WAF and DDoS protection
    - Cost allocation tags
    - Backup and DR strategy

security_requirements:
  compliance: [SOC2, HIPAA, PCI-DSS]
  encryption: At rest and in transit
  network: Zero-trust architecture
  secrets: Vault or AWS Secrets Manager
  audit: CloudTrail and Config

scalability_targets:
  users: 10,000 concurrent
  requests: 1M per day
  storage: 100TB
  compute: Auto-scaling 10-1000 nodes

cost_optimization:
  - Reserved instances
  - Spot instances for batch
  - S3 lifecycle policies
  - Right-sizing recommendations
  - FinOps dashboard

high_availability:
  rpo: 1 hour
  rto: 15 minutes
  backup: Daily with 30-day retention
  multi_az: Required
  multi_region: Active-passive
```

### Critical Decisions Needed
1. Multi-account strategy
2. Network topology (Transit Gateway vs VPC Peering)
3. Disaster recovery approach
4. Cost allocation model

---

## Context for DX Optimizer Agent

### Your Focus Areas
- Create frictionless developer workflows
- Design golden path templates
- Build comprehensive documentation
- Optimize onboarding experience

### Key Context
```yaml
current_dx_gaps:
  - No self-service portal
  - CLI-only interaction
  - Deep Terraform knowledge required
  - 2-day service provisioning time
  - No golden paths

target_metrics:
  onboarding_time: < 1 day
  first_deployment: < 30 minutes
  self_service_ratio: > 90%
  satisfaction_score: > 4.5/5

golden_paths_needed:
  microservice:
    - Node.js API
    - Python FastAPI
    - Java Spring Boot
  
  serverless:
    - Lambda functions
    - Step Functions
    - EventBridge flows
  
  data:
    - RDS databases
    - DynamoDB tables
    - S3 data lakes

documentation_requirements:
  formats:
    - Interactive tutorials
    - Video walkthroughs
    - API playground
    - Example repositories
  
  maintenance:
    - Auto-generated from code
    - Version controlled
    - Searchable
    - Community contributions

developer_tools:
  - CLI with autocomplete
  - IDE plugins (VSCode, IntelliJ)
  - Local development environment
  - ChatOps integration
  - API SDKs (Python, JS, Go, Java)
```

### Critical Decisions Needed
1. Template engine selection
2. Documentation platform (TechDocs vs custom)
3. Onboarding automation approach
4. Feedback collection mechanism

---

## Shared Context for All Agents

### Platform Vision
Build a world-class Internal Developer Platform that abstracts infrastructure complexity while providing developers with self-service capabilities, maintaining enterprise-grade security, compliance, and cost efficiency.

### Non-Negotiable Requirements
1. **Accessibility**: WCAG 2.1 AA compliance
2. **Security**: Zero-trust, encryption everywhere
3. **Multi-tenancy**: Complete isolation between tenants
4. **Observability**: Full stack monitoring and tracing
5. **Documentation**: Comprehensive and up-to-date

### Integration Points
- All agents must provide OpenAPI/GraphQL schemas
- Use semantic versioning for all APIs
- Implement health check endpoints
- Provide Prometheus metrics
- Support distributed tracing with OpenTelemetry

### Timeline
- Week 1-4: Foundation
- Week 5-8: Integration
- Week 9-12: Enhancement
- Week 13+: Production rollout

### Communication Channels
- Architecture decisions: ADRs in Git
- Daily sync: Slack #idp-development
- Weekly review: Video conference
- Documentation: Confluence/GitHub Wiki

### Success Criteria
- Platform adoption > 80%
- Developer satisfaction > 4.5/5
- MTTR < 1 hour
- Deployment frequency > 10/day
- Infrastructure cost reduction > 25%