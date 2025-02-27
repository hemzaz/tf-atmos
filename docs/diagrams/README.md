# Atmos Architecture Diagrams

This directory contains Mermaid diagrams that visually represent the architecture, workflows, and design of the Atmos framework with Terraform.

## Available Diagrams

### Core Architecture
- [Atmos Architecture](atmos-architecture.md) - Comprehensive diagrams showing the Atmos framework architecture, components, and interactions

### Workflows
- [Component Workflows](component-workflows.md) - Detailed workflow diagrams for deploying and managing various components (VPC, EKS, API Gateway, etc.)

### Multi-Account Architecture 
- [Multi-Account Architecture](multi-account-architecture.md) - Diagrams illustrating multi-account AWS patterns implemented with Atmos

## How to Use These Diagrams

These diagrams serve multiple purposes:

1. **Understanding the Architecture** - Visual representation of how Atmos organizes and manages infrastructure
2. **Implementation Guide** - Step-by-step workflows for deploying components
3. **Design Reference** - Patterns for multi-account, multi-region infrastructure design
4. **Documentation Support** - Visual aids to complement text-based documentation

## Diagram Technologies

All diagrams are created using [Mermaid](https://mermaid-js.github.io/mermaid/), a JavaScript-based diagramming and charting tool that renders Markdown-inspired text definitions to create diagrams.

Mermaid diagrams can be viewed:
- Directly in GitHub when viewing the markdown files
- In any Markdown editor that supports Mermaid
- Using the Mermaid Live Editor: https://mermaid.live/

## Contributing to Diagrams

When contributing new diagrams or updating existing ones:

1. Follow the established style for consistency
2. Use descriptive labels for all components
3. Include a clear title and description
4. Group related components using subgraphs
5. Use color-coding to distinguish different types of resources
6. Ensure diagrams are readable at various zoom levels

## Diagram Categories

The diagrams are organized into three main categories:

### 1. Framework Architecture
- Atmos CLI and component structure
- Stack configuration organization
- Variable resolution process
- Terraform backend integration

### 2. Component Workflows
- Deployment sequences for components
- Infrastructure dependencies
- Cross-component integration
- Operational workflows (drift detection, import, etc.)

### 3. Multi-Account Architecture
- AWS Organizations structure
- Cross-account access patterns
- Networking architecture
- Security controls implementation