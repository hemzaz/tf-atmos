---
tags:
  - component/aws-config
  - layer/security-and-compliance
  - provider/aws
---

# Component: `config`

This component provisions AWS Config across all accounts in an AWS Organization. AWS Config is a service that enables
you to assess, audit, and evaluate the configurations of your AWS resources. It continuously monitors and records
configuration changes to your AWS resources and provides a detailed view of the relationships between those resources.

## Component Features

This component is responsible for:

- **Configuration Recording**: Deploys Configuration Recorders in each account and region to track resource configurations
- **Centralized Aggregation**: Configures a designated account (typically `security`) as the central aggregation point for all AWS Config data
- **Compliance Monitoring**: Deploys conformance packs to monitor resources for compliance with best practices and industry standards (e.g., CMMC, CIS, HIPAA)
- **Configuration Storage**: Delivers configuration snapshots and history to a centralized S3 bucket (typically in the `audit` account)
- **Organization-wide Conformance Packs**: Deploys organization conformance packs from the management account that automatically apply to all member accounts
- **SNS Topic Encryption**: Creates encrypted SNS topics for AWS Config notifications (required for CMMC compliance)
- **Account Verification**: Optional safety check that validates Terraform is running in the correct AWS account
- **Flexible Account Map**: Supports both remote-state account-map lookups and static account map variables (default)

## New Features

This version includes several enhancements:

- **Local Conformance Pack Support**: Load conformance packs from local files in addition to remote URLs. This enables
  custom packs, air-gapped deployments, and version-controlled compliance rules.
- **Organization Conformance Packs**: Deploy conformance packs organization-wide from the management account using the
  `scope: organization` setting.
- **SNS Topic Encryption**: Built-in support for KMS encryption of AWS Config SNS topics (`sns_encryption_key_id`
  variable) for CMMC compliance.
- **Flexible Component Naming**: The `global_collector_component_name_pattern` variable allows customization of how
  the component looks up the global collector region's remote state.
- **GovCloud Support**: Full support for AWS GovCloud regions and partitions.

## Key AWS Config Capabilities

- **Configuration History**: Maintains a detailed history of changes to AWS resources, showing when changes were made, who made them, and what the changes were
- **Configuration Snapshots**: Takes periodic snapshots of resource configurations for point-in-time views
- **Compliance Monitoring**: Provides pre-built rules and checks for compliance with best practices and industry standards
- **Relationship Mapping**: Maps relationships between AWS resources to understand change impacts
- **Notifications and Alerts**: Sends notifications when configuration changes impact compliance or security posture

## Architecture

The component deploys a multi-account, multi-region architecture:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           AWS Organization                                   │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ Management Account (Organization Conformance Packs)                    │ │
│  │  - Deploys organization-wide conformance packs                         │ │
│  │  - Packs automatically apply to all member accounts                    │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ Security Account (Central Aggregator)                                  │ │
│  │  - AWS Config Aggregator (collects from ALL accounts)                  │ │
│  │  - Centralized compliance dashboard                                    │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                              ▲ ▲ ▲                                          │
│                              │ │ │ Aggregate Authorizations                 │
│                              │ │ │                                          │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ Audit Account                                                          │ │
│  │  - S3 Bucket (aws-config-bucket)                                       │ │
│  │  - Stores ALL Config data from all accounts ◄───────────────┐          │ │
│  └──────────────────────────────────────────────────────────────│──────────┘ │
│                                                                  │           │
│  ┌────────────────────────────────────────────────────────────┐ │           │
│  │ Each Member Account                                        │ │           │
│  │                                                            │ │           │
│  │  Global Collector Region (e.g., us-east-1):               │ │           │
│  │    ✓ Configuration Recorder                               │ │           │
│  │    ✓ IAM Role (created once per account)                  │ │           │
│  │    ✓ Tracks global resources (IAM, Route53, etc.)         │ │           │
│  │    ✓ Aggregate Authorization → Security Account           │─┘           │
│  │    ✓ Delivery Channel → S3 Bucket (audit) ────────────────────────────────┘
│  │                                                            │              │
│  │  Additional Regions (e.g., us-west-2):                    │              │
│  │    ✓ Configuration Recorder                               │              │
│  │    ✓ References IAM Role from global collector region     │              │
│  │    ✓ Tracks regional resources (EC2, VPC, RDS, etc.)      │              │
│  │    ✓ Delivery Channel → S3 Bucket (audit) ────────────────────────────────┘
│  └────────────────────────────────────────────────────────────┘              │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Architecture Benefits

- **Centralized Compliance**: Security team can view all resource configurations from one account
- **Cost Efficiency**: Single S3 bucket for all AWS Config data (in audit account)
- **Security Best Practices**: Aggregation in security account aligns with AWS Well-Architected Framework
- **Scalability**: Easy to add new accounts and regions without changing the aggregation setup
- **GovCloud Compatible**: Supports AWS GovCloud regions and partitions

> [!WARNING]
>
> #### AWS Config Limitations
>
> Be aware of these AWS Config limitations:
>
> - **Maximum 1000 AWS Config rules** per account can be evaluated
>   - Mitigate by removing duplicate rules across packs
>   - Remove rules that don't apply to any resources
>   - Consider scheduling pack deployment with Lambda for more than 1000 rules
>   - See the [Audit Manager docs](https://aws.amazon.com/blogs/mt/integrate-across-the-three-lines-model-part-2-transform-aws-config-conformance-packs-into-aws-audit-manager-assessments/) for converting conformance packs to custom Audit Manager assessments
> - **Maximum 50 conformance packs** per account
## Usage

## Prerequisites

Before deploying this AWS Config component:

1. **AWS Config Bucket**: The `aws-config-bucket` component must be provisioned first in the audit account:
   ```bash
   atmos terraform apply aws-config-bucket -s core-use1-audit
   ```

2. **Support IAM Role** (CIS AWS Foundations 1.20): A designated support IAM role should be deployed to every account:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "AllowSupport",
         "Effect": "Allow",
         "Action": ["support:*"],
         "Resource": "*"
       },
       {
         "Sid": "AllowTrustedAdvisor",
         "Effect": "Allow",
         "Action": "trustedadvisor:Describe*",
         "Resource": "*"
       }
     ]
   }
   ```

3. **Service Access Principals** (for organization-level conformance packs): Enable trusted access for AWS Config in
   your organization:

   **How to Verify:**
   ```bash
   aws organizations list-aws-service-access-for-organization | grep config
   ```

   **Enable if Disabled:**
   ```bash
   aws organizations enable-aws-service-access --service-principal config.amazonaws.com
   aws organizations enable-aws-service-access --service-principal config-multiaccountsetup.amazonaws.com
   ```

   Or if using our `account` component, add these principals to `aws_service_access_principals`.

## Usage

**Stack Level**: Regional

AWS Config is a regional service. The component must be deployed to each region where you want to track resources.

### Scope Configuration

The `default_scope` variable controls how conformance packs are deployed:

| Scope | Description | Use Case |
|-------|-------------|----------|
| `account` | Conformance packs deployed per-account | Member accounts |
| `organization` | Conformance packs deployed organization-wide | Management account only |

> [!TIP]
>
> #### Using Account Scope (Member Accounts)
>
> For member accounts, use `default_scope: account`. The component will:
> - Create a Configuration Recorder in each region
> - Create an IAM role only in the global collector region
> - Authorize the central aggregator account to collect data
> - Deploy account-level conformance packs

> [!TIP]
>
> #### Using Organization Scope (Management Account)
>
> For the management account, use `default_scope: organization`. The component will:
> - Deploy organization-wide conformance packs that apply to ALL member accounts
> - Require the `config-multiaccountsetup.amazonaws.com` service access principal

### Key Configuration Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `global_resource_collector_region` | Region that tracks global resources (IAM, Route53) | `us-east-1` |
| `central_resource_collector_account` | Account that aggregates all Config data | `security` |
| `create_iam_role` | Set to `true` - component auto-detects global collector region | `true` |
| `config_bucket_*` | References the S3 bucket in audit account | See example below |
| `sns_encryption_key_id` | KMS key for SNS topic encryption (CMMC compliance) | `alias/aws/sns` |
| `allowed_aws_services_for_sns_published` | Service principals granted `sns:Publish` on the Config SNS topic (set `["config.amazonaws.com"]` when using the service-linked role) | `[]` |
| `allowed_iam_arns_for_sns_publish` | IAM role/user ARNs granted `sns:Publish` on the Config SNS topic | `[]` |

### Catalog Configuration

#### Default Configuration (`stacks/catalog/aws-config/defaults.yaml`)

```yaml
components:
  terraform:
    aws-config/defaults:
      metadata:
        type: abstract
        component: "aws-config"
      vars:
        enabled: true
        default_scope: account
        create_iam_role: true
        az_abbreviation_type: fixed
        account_map_component_name: "account-map"
        account_map_tenant: core
        root_account_stage: root
        global_environment: gbl
        global_resource_collector_region: "us-east-1"
        central_resource_collector_account: security
        config_bucket_component_name: "aws-config-bucket"
        config_bucket_tenant: core
        config_bucket_env: ue1
        config_bucket_stage: audit
        sns_encryption_key_id: "alias/aws/sns"
        conformance_packs: []
```

#### Member Account Configuration (`stacks/catalog/aws-config/member-account.yaml`)

```yaml
import:
  - catalog/aws-config/defaults

components:
  terraform:
    aws-config:
      metadata:
        component: "aws-config"
        inherits:
          - "aws-config/defaults"
```

#### Organization Account Configuration (`stacks/catalog/aws-config/organization.yaml`)

```yaml
import:
  - catalog/aws-config/defaults

components:
  terraform:
    aws-config:
      metadata:
        component: "aws-config"
        inherits:
          - "aws-config/defaults"
      vars:
        default_scope: organization
        conformance_packs:
          - name: "Operational-Best-Practices-for-CIS-AWS-v1.4-Level2"
            conformance_pack: "https://raw.githubusercontent.com/awslabs/aws-config-rules/master/aws-config-conformance-packs/Operational-Best-Practices-for-CIS-AWS-v1.4-Level2.yaml"
            parameter_overrides: {}
```

### Conformance Packs

Conformance packs define a collection of AWS Config rules for compliance monitoring. This component supports loading
conformance packs from **both remote URLs and local files**.

#### Local File Support (New Feature)

The component now supports loading conformance packs from the local filesystem in addition to remote URLs. This enables:

- **Custom conformance packs**: Create organization-specific compliance rules
- **Modified AWS packs**: Customize AWS-provided packs for your requirements
- **Air-gapped environments**: Deploy in environments without internet access
- **Version control**: Track conformance pack changes alongside infrastructure code

The component automatically detects whether the `conformance_pack` value is a URL (starts with `http://` or `https://`)
or a local file path. Local paths are resolved relative to the component's root directory.

#### Conformance Pack Examples

```yaml
conformance_packs:
  # Remote URL (AWS Labs managed packs)
  - name: "CIS-AWS-v1.4-Level2"
    conformance_pack: "https://raw.githubusercontent.com/awslabs/aws-config-rules/master/aws-config-conformance-packs/Operational-Best-Practices-for-CIS-AWS-v1.4-Level2.yaml"
    parameter_overrides:
      AccessKeysRotatedParamMaxAccessKeyAge: "45"

  # Local file (relative to component directory)
  - name: "Custom-CMMC-Pack"
    conformance_pack: "conformance-packs/custom-cmmc-pack.yaml"
    parameter_overrides: {}

  # Another local file example
  - name: "CMMC-Level2-Best-Practices"
    conformance_pack: "conformance-packs/cmmc-l2-v2-AWS-Best-Practices.yaml"
    parameter_overrides:
      IamPasswordPolicyParamMaxPasswordAge: "60"

  # Override scope for specific pack
  - name: "Org-Wide-Security-Pack"
    conformance_pack: "https://example.com/pack.yaml"
    scope: "organization"  # Override default_scope
    parameter_overrides: {}
```

#### Creating Custom Conformance Packs

To create a custom conformance pack:

1. Create a `conformance-packs/` directory in your component:
   ```
   components/terraform/aws-config/
   ├── conformance-packs/
   │   ├── custom-security-rules.yaml
   │   └── cmmc-l2-v2-customized.yaml
   ├── main.tf
   ├── variables.tf
   └── ...
   ```

2. Define rules in CloudFormation format:
   ```yaml
   # conformance-packs/custom-security-rules.yaml
   Parameters:
     MaxAccessKeyAge:
       Default: '90'
       Type: String
   Resources:
     AccessKeysRotated:
       Type: AWS::Config::ConfigRule
       Properties:
         ConfigRuleName: custom-access-keys-rotated
         InputParameters:
           maxAccessKeyAge:
             Ref: MaxAccessKeyAge
         Source:
           Owner: AWS
           SourceIdentifier: ACCESS_KEYS_ROTATED
   ```

3. Reference the local file in your configuration:
   ```yaml
   conformance_packs:
     - name: "Custom-Security-Rules"
       conformance_pack: "conformance-packs/custom-security-rules.yaml"
       parameter_overrides:
         MaxAccessKeyAge: "45"
   ```

### SNS Topic Encryption

AWS Config creates an SNS topic for notifications. For CMMC compliance, this topic must be encrypted:

```yaml
# Option 1: AWS Managed Key (Recommended)
sns_encryption_key_id: "alias/aws/sns"

# Option 2: Customer Managed KMS Key
sns_encryption_key_id: "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
```

## Deployment
Note also that AWS states "AWS Config does not support encrypted Amazon SNS topics"
([Permissions for the Amazon SNS Topic](https://docs.aws.amazon.com/config/latest/developerguide/sns-topic-policy.html)).
If notifications fail on an encrypted topic, set `sns_encryption_key_id: ""` to
create the topic unencrypted, as Control Tower does for its own Config topic.
allowed_aws_services_for_sns_published: ["config.amazonaws.com"]
The module puts the SNS topic on the AWS default topic policy, which grants
account principals only. That is enough when the recorder runs on the
customer-managed IAM role created by this component (`create_iam_role: true`),
because that role holds `sns:Publish`. It is **not** enough when the recorder
runs on the AWS Config service-linked role: the service-linked role has no
`sns:Publish` permission, so AWS Config publishes as the `config.amazonaws.com`
service principal and the delivery channel reports
`AuthorizationError: An exception occurred while trying to publish to your Amazon SNS topic`
while S3 delivery continues to succeed. Grant the service principal explicitly:
#### Service-linked role and the SNS topic

### Provisioning Order

> [!IMPORTANT]
>
> #### Critical: Deploy Member Accounts BEFORE Organization Account
>
> Organization conformance packs require all member accounts to have configuration recorders already set up.
> Always deploy member accounts first, then the organization/management account last.

#### Step 1: Deploy to Member Accounts (Global Collector Region First)

All member accounts can be deployed in parallel:

```bash
# Core tenant accounts
atmos terraform apply aws-config -s core-use1-audit
atmos terraform apply aws-config -s core-use1-security
atmos terraform apply aws-config -s core-use1-network
atmos terraform apply aws-config -s core-use1-identity
atmos terraform apply aws-config -s core-use1-dns
atmos terraform apply aws-config -s core-use1-automation

# Platform tenant accounts (if applicable)
atmos terraform apply aws-config -s plat-use1-dev
atmos terraform apply aws-config -s plat-use1-staging
atmos terraform apply aws-config -s plat-use1-prod
```

#### Step 2: Deploy to Organization/Management Account (LAST)

```bash
atmos terraform apply aws-config -s core-use1-root
```

### Multi-Region Deployment

AWS Config is regional. For multi-region coverage, deploy to each region:

#### How Multi-Region Works

- **Global Collector Region** (e.g., `us-east-1`): Creates the IAM role, tracks global resources
- **Additional Regions** (e.g., `us-west-2`): References IAM role via remote state, tracks regional resources only

#### Prerequisites for Additional Regions

Add the aws-config import to regional baseline files:

```yaml
# stacks/orgs/acme/core/security/us-west-2/baseline.yaml
import:
  - orgs/acme/core/security/_defaults
  - mixins/region/us-west-2
  - catalog/aws-config/member-account  # Add this
```

#### Deploy Additional Regions

Follow the same order: member accounts first, then organization account.

```bash
# Step 1: Member accounts in us-west-2
atmos terraform apply aws-config -s core-usw2-audit
atmos terraform apply aws-config -s core-usw2-security
# ... all other member accounts

# Step 2: Organization account in us-west-2 (LAST)
atmos terraform apply aws-config -s core-usw2-root
```

## Known Issues and False Positives

### IAM Inline Policy Check - Service-Linked Roles

The `IAM_NO_INLINE_POLICY_CHECK` rule flags AWS Service-Linked Roles (SLRs) as NON_COMPLIANT. This is a **known false
positive**.

**Why This Happens:**
- AWS Service-Linked Roles are automatically created and managed by AWS services
- These roles **must** have inline policies by AWS design
- The rule cannot distinguish between user-created roles and AWS-managed SLRs

**Common SLRs That Trigger This Finding:**

| Service-Linked Role | Service |
|---------------------|---------|
| `AWSServiceRoleForAmazonGuardDuty` | GuardDuty |
| `AWSServiceRoleForConfig` | AWS Config |
| `AWSServiceRoleForSecurityHub` | Security Hub |
| `AWSServiceRoleForAccessAnalyzer` | IAM Access Analyzer |
| `AWSServiceRoleForAmazonMacie` | Macie |
| `AWSServiceRoleForInspector2` | Inspector |

**Recommended Action:**
- Document these as accepted false positives
- Focus remediation on NON_COMPLIANT findings for user-created roles (not starting with `AWSServiceRole`)
- Validate findings with: `aws iam get-role --role-name <role> --query 'Role.Path'`
  - Service-linked roles have path: `/aws-service-role/<service>/`

**For CMMC/Compliance Auditors:**
- Service-linked roles are AWS-managed and out of customer control
- CMMC framework recognizes AWS-managed resources as acceptable exceptions
- Document the exception with proper justification

### Verification Commands

```bash
# Verify SNS topic encryption
aws sns get-topic-attributes \
  --topic-arn arn:aws:sns:us-east-1:123456789012:config-topic \
  --query 'Attributes.KmsMasterKeyId'

# List service-linked roles
aws iam list-roles --query 'Roles[?starts_with(RoleName, `AWSServiceRole`)].RoleName'

# Check if role is service-linked
aws iam get-role --role-name AWSServiceRoleForAmazonGuardDuty --query 'Role.Path'
```


<!-- markdownlint-disable -->
## Requirements
|----|-------|

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.4.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 4.0.0 |
| <a name="requirement_awsutils"></a> [awsutils](#requirement\_awsutils) | >= 0.16.0 |

## Providers
|----|-------|

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 4.0.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
|----|------|-------|
|------|--------|---------|
| <a name="module_account_map"></a> [account\_map](#module\_account\_map) | cloudposse/stack-config/yaml//modules/remote-state | 1.8.0 |
| <a name="module_aws_config"></a> [aws\_config](#module\_aws\_config) | cloudposse/config/aws | 1.5.3 |
| <a name="module_aws_config_label"></a> [aws\_config\_label](#module\_aws\_config\_label) | cloudposse/label/null | 0.25.0 |
| <a name="module_config_bucket"></a> [config\_bucket](#module\_config\_bucket) | cloudposse/stack-config/yaml//modules/remote-state | 1.8.0 |
| <a name="module_conformance_pack"></a> [conformance\_pack](#module\_conformance\_pack) | cloudposse/config/aws//modules/conformance-pack | 1.5.3 |
| <a name="module_global_collector_region"></a> [global\_collector\_region](#module\_global\_collector\_region) | cloudposse/stack-config/yaml//modules/remote-state | 1.8.0 |
| <a name="module_org_conformance_pack"></a> [org\_conformance\_pack](#module\_org\_conformance\_pack) | ./modules/org-conformance-pack | n/a |
| <a name="module_this"></a> [this](#module\_this) | cloudposse/label/null | 0.25.0 |
| <a name="module_utils"></a> [utils](#module\_utils) | cloudposse/utils/aws | 1.4.0 |

## Resources

| Name | Type |
|----|----|
|------|------|
| [terraform_data.account_verification](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [aws_caller_identity.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|----|-----------|----|-------|:------:|
|------|-------------|------|---------|:--------:|
| <a name="input_account_map"></a> [account\_map](#input\_account\_map) | Static account map configuration. Only used when `account_map_enabled` is `false`.<br/>Map keys use `tenant-stage` format (e.g., `core-security`, `core-audit`, `plat-prod`). | <pre>object({<br/>    full_account_map              = map(string)<br/>    audit_account_account_name    = optional(string, "")<br/>    root_account_account_name     = optional(string, "")<br/>    identity_account_account_name = optional(string, "")<br/>    aws_partition                 = optional(string, "aws")<br/>    iam_role_arn_templates        = optional(map(string), {})<br/>  })</pre> | <pre>{<br/>  "audit_account_account_name": "",<br/>  "aws_partition": "aws",<br/>  "full_account_map": {},<br/>  "iam_role_arn_templates": {},<br/>  "identity_account_account_name": "",<br/>  "root_account_account_name": ""<br/>}</pre> | no |
| <a name="input_account_map_component_name"></a> [account\_map\_component\_name](#input\_account\_map\_component\_name) | The name of the account-map component | `string` | `"account-map"` | no |
| <a name="input_account_map_enabled"></a> [account\_map\_enabled](#input\_account\_map\_enabled) | Enable the account map component. When true, the component fetches account mappings from the<br/>`account-map` component via remote state. When false (default), the component uses the static `account_map` variable instead. | `bool` | `false` | no |
| <a name="input_account_map_tenant"></a> [account\_map\_tenant](#input\_account\_map\_tenant) | The tenant where the `account_map` component required by remote-state is deployed | `string` | `"core"` | no |
| <a name="input_account_verification_enabled"></a> [account\_verification\_enabled](#input\_account\_verification\_enabled) | Enable account verification. When true (default), the component verifies that Terraform is executing<br/>in the correct AWS account by comparing the current account ID against the expected account from the<br/>account\_map based on the component's tenant-stage context. | `bool` | `true` | no |
| <a name="input_additional_tag_map"></a> [additional\_tag\_map](#input\_additional\_tag\_map) | Additional key-value pairs to add to each map in `tags_as_list_of_maps`. Not added to `tags` or `id`.<br/>This is for some rare cases where resources want additional configuration of tags<br/>and therefore take a list of maps with tag key, value, and additional configuration. | `map(string)` | `{}` | no |
| <a name="input_allowed_aws_services_for_sns_published"></a> [allowed\_aws\_services\_for\_sns\_published](#input\_allowed\_aws\_services\_for\_sns\_published) | AWS service principals granted `sns:Publish` on the AWS Config SNS topic.<br/>Passed through to `cloudposse/config/aws`.<br/><br/>Required when the configuration recorder runs on the AWS Config<br/>service-linked role (`create_iam_role = false` with no customer-managed role):<br/>the service-linked role has no `sns:Publish` permission, so AWS Config<br/>publishes as the `config.amazonaws.com` service principal, which the default<br/>topic policy does not allow. Set to `["config.amazonaws.com"]` in that case.<br/>See https://docs.aws.amazon.com/config/latest/developerguide/sns-topic-policy.html | `list(string)` | `[]` | no |
| <a name="input_allowed_iam_arns_for_sns_publish"></a> [allowed\_iam\_arns\_for\_sns\_publish](#input\_allowed\_iam\_arns\_for\_sns\_publish) | IAM role/user ARNs granted `sns:Publish` on the AWS Config SNS topic.<br/>Passed through to `cloudposse/config/aws`. | `list(string)` | `[]` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Additional attributes (e.g. `workers` or `cluster`) to add to `id`,<br/>in the order they appear in the list. New attributes are appended to the<br/>end of the list. The elements of the list are joined by the `delimiter`<br/>and treated as a single ID element. | `list(string)` | `[]` | no |
| <a name="input_az_abbreviation_type"></a> [az\_abbreviation\_type](#input\_az\_abbreviation\_type) | AZ abbreviation type, `fixed` or `short` | `string` | `"fixed"` | no |
| <a name="input_central_resource_collector_account"></a> [central\_resource\_collector\_account](#input\_central\_resource\_collector\_account) | The name of the account that is the centralized aggregation account. | `string` | n/a | yes |
| <a name="input_config_bucket_component_name"></a> [config\_bucket\_component\_name](#input\_config\_bucket\_component\_name) | The name of the config-bucket component | `string` | `"config-bucket"` | no |
| <a name="input_config_bucket_env"></a> [config\_bucket\_env](#input\_config\_bucket\_env) | The environment of the AWS Config S3 Bucket | `string` | n/a | yes |
| <a name="input_config_bucket_stage"></a> [config\_bucket\_stage](#input\_config\_bucket\_stage) | The stage of the AWS Config S3 Bucket | `string` | n/a | yes |
| <a name="input_config_bucket_tenant"></a> [config\_bucket\_tenant](#input\_config\_bucket\_tenant) | (Optional) The tenant of the AWS Config S3 Bucket | `string` | `""` | no |
| <a name="input_config_component_name"></a> [config\_component\_name](#input\_config\_component\_name) | The name of the aws config component (i.e., this component) | `string` | `"aws-config"` | no |
| <a name="input_conformance_packs"></a> [conformance\_packs](#input\_conformance\_packs) | List of conformance packs. Each conformance pack is a map with the following keys: name, conformance\_pack, parameter\_overrides.<br/><br/>For example:<br/>conformance\_packs = [<br/>  {<br/>    name                  = "Operational-Best-Practices-for-CIS-AWS-v1.4-Level1"<br/>    conformance\_pack      = "https://raw.githubusercontent.com/awslabs/aws-config-rules/master/aws-config-conformance-packs/Operational-Best-Practices-for-CIS-AWS-v1.4-Level1.yaml"<br/>    parameter\_overrides   = {<br/>      "AccessKeysRotatedParamMaxAccessKeyAge" = "45"<br/>    }<br/>  },<br/>  {<br/>    name                  = "Operational-Best-Practices-for-CIS-AWS-v1.4-Level2"<br/>    conformance\_pack      = "https://raw.githubusercontent.com/awslabs/aws-config-rules/master/aws-config-conformance-packs/Operational-Best-Practices-for-CIS-AWS-v1.4-Level2.yaml"<br/>    parameter\_overrides   = {<br/>      "IamPasswordPolicyParamMaxPasswordAge" = "45"<br/>    }<br/>  }<br/>]<br/><br/>Complete list of AWS Conformance Packs managed by AWSLabs can be found here:<br/>https://github.com/awslabs/aws-config-rules/tree/master/aws-config-conformance-packs | <pre>list(object({<br/>    name                = string<br/>    conformance_pack    = string<br/>    parameter_overrides = map(any)<br/>    scope               = optional(string, null)<br/>  }))</pre> | `[]` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object for setting entire context at once.<br/>See description of individual variables for details.<br/>Leave string and numeric variables as `null` to use default value.<br/>Individual variable settings (non-null) override settings in context object,<br/>except for attributes, tags, and additional\_tag\_map, which are merged. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_create_iam_role"></a> [create\_iam\_role](#input\_create\_iam\_role) | Flag to indicate whether an IAM Role should be created to grant the proper permissions for AWS Config | `bool` | `false` | no |
| <a name="input_default_scope"></a> [default\_scope](#input\_default\_scope) | The default scope of the conformance pack. Valid values are `account` and `organization`. | `string` | `"account"` | no |
| <a name="input_delegated_accounts"></a> [delegated\_accounts](#input\_delegated\_accounts) | The account IDs of other accounts that will send their AWS Configuration or Security Hub data to this account | `set(string)` | `null` | no |
| <a name="input_delimiter"></a> [delimiter](#input\_delimiter) | Delimiter to be used between ID elements.<br/>Defaults to `-` (hyphen). Set to `""` to use no delimiter at all. | `string` | `null` | no |
| <a name="input_descriptor_formats"></a> [descriptor\_formats](#input\_descriptor\_formats) | Describe additional descriptors to be output in the `descriptors` output map.<br/>Map of maps. Keys are names of descriptors. Values are maps of the form<br/>`{<br/>  format = string<br/>  labels = list(string)<br/>}`<br/>(Type is `any` so the map values can later be enhanced to provide additional options.)<br/>`format` is a Terraform format string to be passed to the `format()` function.<br/>`labels` is a list of labels, in order, to pass to `format()` function.<br/>Label values will be normalized before being passed to `format()` so they will be<br/>identical to how they appear in `id`.<br/>Default is `{}` (`descriptors` output will be empty). | `any` | `{}` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Usually used for region e.g. 'uw2', 'us-west-2', OR role 'prod', 'staging', 'dev', 'UAT' | `string` | `null` | no |
| <a name="input_global_collector_component_name_pattern"></a> [global\_collector\_component\_name\_pattern](#input\_global\_collector\_component\_name\_pattern) | A string formatting pattern used to construct or look up the name of the<br/>global AWS Config collector region component.<br/><br/>This pattern should align with the regional naming convention of the<br/>aws-config component. For example, if the pattern is "%s-%s" and you pass<br/>("aws-config", "use1"), the resulting component name will be "aws-config-use1".<br/><br/>Adjust this pattern if your environment uses a different naming convention<br/>for regional AWS Config components. | `string` | `"%s-%s"` | no |
| <a name="input_global_environment"></a> [global\_environment](#input\_global\_environment) | Global environment name | `string` | `"gbl"` | no |
| <a name="input_global_resource_collector_region"></a> [global\_resource\_collector\_region](#input\_global\_resource\_collector\_region) | The region that collects AWS Config data for global resources such as IAM | `string` | n/a | yes |
| <a name="input_iam_role_arn"></a> [iam\_role\_arn](#input\_iam\_role\_arn) | The ARN for an IAM Role AWS Config uses to make read or write requests to the delivery channel and to describe the<br/>AWS resources associated with the account. This is only used if create\_iam\_role is false.<br/><br/>If you want to use an existing IAM Role, set the variable to the ARN of the existing role and set create\_iam\_role to `false`.<br/><br/>See the AWS Docs for further information:<br/>http://docs.aws.amazon.com/config/latest/developerguide/iamrole-permissions.html | `string` | `null` | no |
| <a name="input_id_length_limit"></a> [id\_length\_limit](#input\_id\_length\_limit) | Limit `id` to this many characters (minimum 6).<br/>Set to `0` for unlimited length.<br/>Set to `null` for keep the existing setting, which defaults to `0`.<br/>Does not affect `id_full`. | `number` | `null` | no |
| <a name="input_label_key_case"></a> [label\_key\_case](#input\_label\_key\_case) | Controls the letter case of the `tags` keys (label names) for tags generated by this module.<br/>Does not affect keys of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper`.<br/>Default value: `title`. | `string` | `null` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | The order in which the labels (ID elements) appear in the `id`.<br/>Defaults to ["namespace", "environment", "stage", "name", "attributes"].<br/>You can omit any of the 6 labels ("tenant" is the 6th), but at least one must be present. | `list(string)` | `null` | no |
| <a name="input_label_value_case"></a> [label\_value\_case](#input\_label\_value\_case) | Controls the letter case of ID elements (labels) as included in `id`,<br/>set as tag values, and output by this module individually.<br/>Does not affect values of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper` and `none` (no transformation).<br/>Set this to `title` and set `delimiter` to `""` to yield Pascal Case IDs.<br/>Default value: `lower`. | `string` | `null` | no |
| <a name="input_labels_as_tags"></a> [labels\_as\_tags](#input\_labels\_as\_tags) | Set of labels (ID elements) to include as tags in the `tags` output.<br/>Default is to include all labels.<br/>Tags with empty values will not be included in the `tags` output.<br/>Set to `[]` to suppress all generated tags.<br/>**Notes:**<br/>  The value of the `name` tag, if included, will be the `id`, not the `name`.<br/>  Unlike other `null-label` inputs, the initial setting of `labels_as_tags` cannot be<br/>  changed in later chained modules. Attempts to change it will be silently ignored. | `set(string)` | <pre>[<br/>  "default"<br/>]</pre> | no |
| <a name="input_managed_rules"></a> [managed\_rules](#input\_managed\_rules) | A list of AWS Managed Rules that should be enabled on the account.<br/><br/>See the following for a list of possible rules to enable:<br/>https://docs.aws.amazon.com/config/latest/developerguide/managed-rules-by-aws-config.html<br/><br/>Example:<pre>managed_rules = {<br/>  access-keys-rotated = {<br/>    identifier  = "ACCESS_KEYS_ROTATED"<br/>    description = "Checks whether the active access keys are rotated within the number of days specified in maxAccessKeyAge. The rule is NON_COMPLIANT if the access keys have not been rotated for more than maxAccessKeyAge number of days."<br/>    input_parameters = {<br/>      maxAccessKeyAge : "90"<br/>    }<br/>    enabled = true<br/>    tags = {}<br/>  }<br/>}</pre> | <pre>map(object({<br/>    description      = string<br/>    identifier       = string<br/>    input_parameters = any<br/>    tags             = map(string)<br/>    enabled          = bool<br/>  }))</pre> | `{}` | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Usually the component or solution name, e.g. 'app' or 'jenkins'.<br/>This is the only ID element not also included as a `tag`.<br/>The "name" tag is set to the full `id` string. There is no tag with the value of the `name` input. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Usually an abbreviation of your organization name, e.g. 'eg' or 'cp', to help ensure generated IDs are globally unique | `string` | `null` | no |
| <a name="input_privileged"></a> [privileged](#input\_privileged) | True if the default provider already has access to the backend | `bool` | `false` | no |
| <a name="input_recording_mode"></a> [recording\_mode](#input\_recording\_mode) | The mode for AWS Config to record configuration changes.<br/><br/>recording\_frequency:<br/>  The default frequency with which AWS Config records configuration changes (CONTINUOUS or DAILY).<br/>recording\_mode\_override:<br/>  Override the recording frequency for specific resource types.<br/><br/>Use DAILY recording for high-churn or ephemeral resource types to reduce costs.<br/>Resources created and destroyed within a 24-hour period generate zero CIs under DAILY.<br/><br/>See: https://docs.aws.amazon.com/config/latest/developerguide/select-resources-recording-frequency.html<br/><br/>Example:<pre>recording_mode = {<br/>  recording_frequency = "CONTINUOUS"<br/>  recording_mode_override = {<br/>    description         = "Record high-churn resource types daily instead of continuously"<br/>    recording_frequency = "DAILY"<br/>    resource_types      = ["AWS::EC2::Instance", "AWS::EC2::EC2Fleet", "AWS::EC2::LaunchTemplate"]<br/>  }<br/>}</pre> | <pre>object({<br/>    recording_frequency = string<br/>    recording_mode_override = optional(object({<br/>      description         = string<br/>      recording_frequency = string<br/>      resource_types      = list(string)<br/>    }))<br/>  })</pre> | `null` | no |
| <a name="input_regex_replace_chars"></a> [regex\_replace\_chars](#input\_regex\_replace\_chars) | Terraform regular expression (regex) string.<br/>Characters matching the regex will be removed from the ID elements.<br/>If not set, `"/[^a-zA-Z0-9-]/"` is used to remove all characters other than hyphens, letters and digits. | `string` | `null` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS Region | `string` | n/a | yes |
| <a name="input_root_account_stage"></a> [root\_account\_stage](#input\_root\_account\_stage) | The stage name for the Organization root (master) account | `string` | `"root"` | no |
| <a name="input_sns_encryption_key_id"></a> [sns\_encryption\_key\_id](#input\_sns\_encryption\_key\_id) | The ID of an AWS-managed customer master key (CMK) for Amazon SNS or a custom CMK.<br/><br/>Use "alias/aws/sns" for AWS managed key (recommended for compliance).<br/>Use a custom KMS key ARN or alias for organization-specific encryption requirements.<br/><br/>IMPORTANT: This is required for CMMC compliance (cmmc-2-v2-sns-encrypted-kms rule).<br/>The SNS topic created by AWS Config must be encrypted with KMS. | `string` | `"alias/aws/sns"` | no |
| <a name="input_stage"></a> [stage](#input\_stage) | ID element. Usually used to indicate role, e.g. 'prod', 'staging', 'source', 'build', 'test', 'deploy', 'release' | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags (e.g. `{'BusinessUnit': 'XYZ'}`).<br/>Neither the tag keys nor the tag values will be modified by this module. | `map(string)` | `{}` | no |
| <a name="input_tenant"></a> [tenant](#input\_tenant) | ID element \_(Rarely used, not included by default)\_. A customer identifier, indicating who this instance of a resource is for | `string` | `null` | no |

## Outputs

| Name | Description |
|----|-----------|
|------|-------------|
| <a name="output_aws_config_configuration_recorder_id"></a> [aws\_config\_configuration\_recorder\_id](#output\_aws\_config\_configuration\_recorder\_id) | The ID of the AWS Config Recorder |
| <a name="output_aws_config_iam_role"></a> [aws\_config\_iam\_role](#output\_aws\_config\_iam\_role) | The ARN of the IAM Role used for AWS Config |
| <a name="output_storage_bucket_arn"></a> [storage\_bucket\_arn](#output\_storage\_bucket\_arn) | Storage Config bucket ARN |
| <a name="output_storage_bucket_id"></a> [storage\_bucket\_id](#output\_storage\_bucket\_id) | Storage Config bucket ID |
<!-- markdownlint-restore -->



## References


- [AWS Config Documentation](https://docs.aws.amazon.com/config/index.html) - Official AWS Config documentation

- [CloudPosse terraform-aws-config Module](https://github.com/cloudposse/terraform-aws-config) - The underlying Terraform module used by this component

- [Conformance Packs Documentation](https://docs.aws.amazon.com/config/latest/developerguide/conformance-packs.html) - AWS documentation for conformance packs

- [AWS Managed Sample Conformance Packs](https://github.com/awslabs/aws-config-rules/tree/master/aws-config-conformance-packs) - Pre-built conformance packs for CIS, HIPAA, NIST, PCI-DSS, and more

- [AWS Config Managed Rules](https://docs.aws.amazon.com/config/latest/developerguide/managed-rules-by-aws-config.html) - List of all AWS managed Config rules

- [AWS Service-Linked Roles](https://docs.aws.amazon.com/IAM/latest/UserGuide/using-service-linked-roles.html) - Understanding AWS service-linked roles and their inline policies

- [Organization Conformance Packs](https://docs.aws.amazon.com/config/latest/developerguide/conformance-pack-organization-apis.html) - Deploying conformance packs across an AWS Organization

- [Multi-Account Multi-Region Data Aggregation](https://docs.aws.amazon.com/config/latest/developerguide/aggregate-data.html) - Setting up AWS Config aggregators across accounts and regions

- [CIS AWS Foundations Benchmark](https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-cis-controls.html) - CIS benchmark controls for AWS

- [CMMC Compliance on AWS](https://aws.amazon.com/compliance/cmmc/) - AWS resources for CMMC compliance




[<img src="https://cloudposse.com/logo-300x69.svg" height="32" align="right"/>](https://cpco.io/homepage?utm_source=github&utm_medium=readme&utm_campaign=cloudposse-terraform-components/aws-config&utm_content=)

