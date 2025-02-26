# Centralized DNS Management in AWS

### Overview
This document outlines the design, configuration, and best practices for managing DNS in a multi-account AWS environment. The primary objective is to centralize private domain management within a shared services account, enabling secure and controlled DNS management for separate development (`dev`), staging (`stg`), and production (`prod`) accounts.
---

## 1. Design and Account Structure
### Account Layout
1. **Shared Services Account**:
   - Centralizes DNS management and hosts all private DNS zones, including the root domain (`company.local`) and environment-specific subdomains (`dev.company.local`, `stg.company.local`, and `prod.company.local`).
   - Manages permissions and access for environment accounts.
2. **Environment-Specific Accounts**:
   - Separate accounts for `dev`, `stg`, and `prod` environments.
   - Each account has isolated access to its respective DNS zone within the shared services account.

### Key Considerations
1. **Centralized Control**: The shared services account maintains primary control over all DNS zones, simplifying governance and minimizing unauthorized access risks.
2. **Environment-Specific Access**: The `prod` zone is highly restricted, allowing updates only via Terraform and `externalDNS` automation, while `dev` and `stg` have more flexible access to accommodate frequent changes.
---

## 2. AWS Resources and Configuration
This section details the AWS resources required to implement centralized DNS management effectively, with a focus on private zones and resolver rules for cross-account communication.
### Route 53 Hosted Zones
1. **Private Hosted Zones**:
   - Create a private hosted zone for each environment-specific domain: `dev.company.local`, `stg.company.local`, and `prod.company.local`.
   - These private zones allow VPC-based DNS resolution within each environment.
2. **VPC Associations**:
   - Associate private hosted zones with the correct VPCs across accounts using **AWS Resource Access Manager (RAM)**, ensuring cross-account environments can resolve DNS queries efficiently.

### Route 53 Resolver Endpoints (Optional)
For hybrid or on-premises integrations, set up **Route 53 Resolver Endpoints**:
- **Inbound and Outbound Endpoints**: Allow DNS resolution between AWS environments and on-premises resources.
- **Resolver Rules**: Use RAM to share resolver rules across accounts, enabling each environment account to query the centralized DNS configuration as needed.
---

## 3. IAM and Access Management
IAM access management ensures secure and isolated access to DNS resources across accounts.
### Cross-Account Role Design
1. **Shared Services Account**:
   - Create roles such as `DevZoneAccess`, `StgZoneAccess`, and `ProdZoneAccess` in the shared services account.
   - Each role grants read/write access to a specific subdomain (e.g., `dev.company.local`, `stg.company.local`, `prod.company.local`) with only necessary permissions.
2. **Environment Accounts (dev, stg, prod)**:
   - Define IAM roles in each environment account that allow assumption of the corresponding roles in the shared services account.
   - Only `prod`-related resources (e.g., `externalDNS` and Terraform automation) have update permissions for `prod.company.local`.

### Route 53 Resolver Rule Sharing via RAM
For cross-account DNS resolution, use RAM to share resolver rules:
1. **Define Resolver Rules** in the shared services account for each environment.
2. **Share Resolver Rules** across accounts, allowing other environment accounts to access the necessary DNS resources securely.

### IAM Policies and Permissions
**IAM Policies in the Shared Services Account**:
   - Define policies that restrict actions on each zone. For example:
     - `DevZoneAccess` allows full access to `dev.company.local`.
     - `StgZoneAccess` allows full access to `stg.company.local`.
     - `ProdZoneAccess` allows limited updates on `prod.company.local`, specifically for `externalDNS` and Terraform.
   - **Conditional Policies**: Use IAM conditions (e.g., `aws:SourceAccount` and `aws:ResourceAccount`) to specify access control for each environment.
**Environment Account Policies**:
   - Each environment account policy should include `sts:AssumeRole` permissions to allow interaction with the roles created in the shared services account.

### IRSA for Kubernetes (if applicable)
If `externalDNS` is deployed in a Kubernetes cluster:
1. Set up **IAM Role for Service Account (IRSA)** in the `prod-cluster` to interact with the `prod.company.local` zone securely.
2. Define specific permissions on the `prod.company.local` zone for `externalDNS` to dynamically update records.
---

## 4. Infrastructure as Code (IaC) Considerations
### Separating State Files
To ensure modularity and ease of management:
1. **Account-Level Separation**:
   - Maintain separate state files for the shared services and each environment account (`dev`, `stg`, `prod`).
2. **Environment-Based Modules**:
   - Each environment (e.g., `dev`, `stg`, `prod`) should have its own state file to allow independent updates without impacting others.

### Modular IaC Structure
Define reusable Terraform modules to structure resources:
1. **DNS Zone Module**:
   - Centralized module for creating Route 53 private zones and managing associations.
2. **IAM Roles Module**:
   - Separate modules for creating and managing cross-account roles and permissions.
3. **Route 53 Resolver Module (if applicable)**:
   - Modular setup for Route 53 Resolver endpoints and rule sharing across accounts using RAM.

### Example Module Structure:
- **Root Module**:
  - Calls submodules for zone creation, IAM roles, and resolver configurations.
- **Zone-Specific Modules**:
  - Separate modules for each zone (`dev.company.local`, `stg.company.local`, `prod.company.local`), allowing environment-specific customization.
---

## 5. Client-Provided Data
To implement this DNS architecture, gather the following data from the client:
1. **Domain Names**: Root domain (`company.local`) and environment-specific subdomains.
2. **CIDR Ranges**: Provide VPC CIDRs for each environment if private hosted zones are needed.
3. **SSL Certificates**: AWS ACM certificates for each environment to secure traffic if needed.
4. **Routing Preferences**: Specify routing policies (e.g., latency-based routing for `prod` or failover configurations).
5. **Automation Tools**: Confirm the use of Terraform or `externalDNS` for record management in `prod`.
---

## Sources
[1] https://aws.amazon.com/blogs/networking-and-content-delivery/centralized-dns-management-of-hybrid-cloud-with-amazon-route-53-and-aws-transit-gateway/
[2] https://docs.aws.amazon.com/whitepapers/latest/hybrid-cloud-dns-options-for-vpc/scaling-dns-management-across-multiple-accounts-and-vpcs.html
[3] https://aws.amazon.com/blogs/security/simplify-dns-management-in-a-multiaccount-environment-with-route-53-resolver/
