---
tags:
  - aws
  - iam
  - access-analyzer
  - security
  - compliance
  - organizations
---

# Component: `access-analyzer`

This component is responsible for configuring AWS Identity and Access Management Access Analyzer within an AWS
Organization.

IAM Access Analyzer helps identify resources in your organization and accounts that are shared with external entities,
as well as unused access permissions. This enables you to identify unintended access to your resources and data, which
is a critical security risk. Access Analyzer uses logic-based reasoning to analyze resource-based policies in your AWS
environment and generates findings for each instance of a resource shared outside your account.

## Key Features

- **External Access Analysis**: Identifies resources shared with external principals outside your organization
- **Unused Access Analysis**: Detects unused IAM roles, users, and permissions to implement least privilege
- **Policy Validation**: Validates IAM policies against policy grammar and AWS best practices
- **Custom Policy Checks**: Validates IAM policies against your specified security standards
- **Policy Generation**: Generates least-privilege IAM policies based on CloudTrail access activity

## Component Features

- **Delegated Administrator Model**: Uses AWS Organizations delegated administrator pattern for centralized management
- **Multi-Region Deployment**: Supports deployment across all AWS regions
- **External Access Analysis**: Identifies resources shared with external principals
- **Unused Access Analysis**: Detects unused IAM roles, users, and permissions with configurable threshold
- **Service-Linked Role**: Automatically creates the required service-linked role during delegation
- **Account Verification**: Optional safety check that validates Terraform is running in the correct AWS account
- **Flexible Account Map**: Supports both remote-state account-map lookups and static account map variables (default)

## Analyzer Types

This component creates two types of organization-wide analyzers:

| Analyzer Type | Purpose | Findings |
|---------------|---------|----------|
| `ORGANIZATION` | External access analysis | Public access, cross-account access, cross-organization access |
| `ORGANIZATION_UNUSED_ACCESS` | Unused access analysis | Unused roles, users, permissions (configurable threshold) |

## Supported Resources

External access analyzer monitors the following resource types:
- Amazon S3 buckets and access points
- IAM roles and policies
- AWS KMS keys
- AWS Lambda functions and layers
- Amazon SQS queues
- AWS Secrets Manager secrets
- Amazon SNS topics
- Amazon EBS volume snapshots
- Amazon RDS DB snapshots and cluster snapshots
- Amazon ECR repositories
- Amazon EFS file systems

## Regional Deployment

IAM Access Analyzer is a regional service. You must deploy analyzers to each region where you have resources that need
monitoring. The delegation from the management account only needs to happen once (globally), but analyzers must be
created in each region.

## Deployment Workflow

> **Important**: Step 1 must be completed successfully before Step 2 can run. The delegation and service-linked role
> created in Step 1 are prerequisites for creating organization-level analyzers in Step 2.

**Step 1 - Delegate Access Analyzer (Management Account)**: From the Organization management (root) account, delegate
administration to the security account. This step also creates the required service-linked role.

**Step 2 - Create Analyzers (Delegated Administrator)**: Deploy the external access and unused access analyzers in the
delegated administrator account for each region.

## Service-Linked Role

AWS Access Analyzer requires a service-linked role (`AWSServiceRoleForAccessAnalyzer`) in the organization management
account before organization-level analyzers can be created from the delegated administrator. This component
automatically creates this role when deploying to the root account with `organizations_delegated_administrator_enabled: true`.

The service-linked role creation can be controlled with the `service_linked_role_enabled` variable:
- `true` (default): Creates the service-linked role when delegating administration
- `false`: Skips creation (use if the role already exists or was created manually/by another process)

## Configuration

> **Note**: The examples below use Cloud Posse naming conventions (e.g., `core-security` for the security account,
> `core-gbl-root` for stack names). Adjust these values to match your organization's account and stack naming conventions.

### Defaults (Abstract Component)

```yaml
components:
  terraform:
    aws-access-analyzer/defaults:
      metadata:
        component: aws-access-analyzer
        type: abstract
      vars:
        enabled: true
        global_environment: gbl
        account_map_tenant: core
        root_account_stage: root
        # The account name of your delegated administrator (typically your security account)
        # Adjust to match your organization's account naming convention
        delegated_administrator_account_name: core-security
        accessanalyzer_service_principal: "access-analyzer.amazonaws.com"
        accessanalyzer_organization_enabled: false
        accessanalyzer_organization_unused_access_enabled: false
        organizations_delegated_administrator_enabled: false
        service_linked_role_enabled: true
```

### Root Account Configuration (Step 1)

```yaml
import:
  - catalog/aws-access-analyzer/defaults

components:
  terraform:
    # Step 1: Deploy to root account to delegate administration and create service-linked role
    aws-access-analyzer/root:
      metadata:
        component: aws-access-analyzer
        inherits:
          - aws-access-analyzer/defaults
      vars:
        organizations_delegated_administrator_enabled: true
        # Set to false if the service-linked role already exists
        service_linked_role_enabled: true
```

### Delegated Administrator Configuration (Step 2)

```yaml
import:
  - catalog/aws-access-analyzer/defaults

components:
  terraform:
    # Step 2: Deploy to delegated administrator (security) account to create analyzers
    aws-access-analyzer/delegated-administrator:
      metadata:
        component: aws-access-analyzer
        inherits:
          - aws-access-analyzer/defaults
      vars:
        accessanalyzer_organization_enabled: true
        accessanalyzer_organization_unused_access_enabled: true
        # Number of days without use before generating unused access findings (default: 30)
        unused_access_age: 30
```

## Provisioning

> **Note**: Replace the stack names below (e.g., `core-gbl-root`, `core-use1-security`) with your actual stack names
> based on your Atmos stack configuration.

**Step 1:** Delegate Access Analyzer to the security account (run once from root/management account):

```bash
# Replace with your root account stack name
atmos terraform apply aws-access-analyzer/root -s core-gbl-root
```

This step:
- Creates the service-linked role for Access Analyzer (if `service_linked_role_enabled: true`)
- Delegates Access Analyzer administration to the security account

**Step 2:** Create analyzers in the delegated administrator (security) account for each region:

```bash
# Replace with your security account stack names for each region
atmos terraform apply aws-access-analyzer/delegated-administrator -s core-use1-security
atmos terraform apply aws-access-analyzer/delegated-administrator -s core-usw2-security
```

This step creates the organization-wide analyzers:
- External access analyzer (type: `ORGANIZATION`)
- Unused access analyzer (type: `ORGANIZATION_UNUSED_ACCESS`)

## Cost Considerations

- **External Access Analyzer**: No additional charge (included with AWS account)
- **Unused Access Analyzer**: Charged per IAM role or user analyzed per month
- See [IAM Access Analyzer pricing](https://aws.amazon.com/iam/access-analyzer/pricing/) for current rates

## References

### AWS Documentation
- [What is IAM Access Analyzer?](https://docs.aws.amazon.com/IAM/latest/UserGuide/what-is-access-analyzer.html)
- [Getting Started with Access Analyzer](https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-getting-started.html)
- [Access Analyzer Findings](https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-findings.html)
- [Unused Access Analysis](https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-unused-access.html)
- [Service-Linked Role for Access Analyzer](https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-getting-started.html#access-analyzer-permissions)
- [Delegated Administrator for Access Analyzer](https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-settings.html#access-analyzer-delegated-administrator)

### Terraform Resources
- [aws_accessanalyzer_analyzer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/accessanalyzer_analyzer)
- [aws_iam_service_linked_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_service_linked_role)
- [aws_organizations_delegated_administrator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_delegated_administrator)

### Additional Resources
- [IAM Access Analyzer Product Page](https://aws.amazon.com/iam/access-analyzer/)
- [IAM Access Analyzer Pricing](https://aws.amazon.com/iam/access-analyzer/pricing/)
- [Setting up Access Analyzer for Organization](https://repost.aws/knowledge-center/iam-access-analyzer-organization)


<!-- markdownlint-disable -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.4.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 4.9.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 4.9.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_account_map"></a> [account\_map](#module\_account\_map) | cloudposse/stack-config/yaml//modules/remote-state | 1.8.0 |
| <a name="module_this"></a> [this](#module\_this) | cloudposse/label/null | 0.25.0 |

## Resources

| Name | Type |
|------|------|
| [aws_accessanalyzer_analyzer.organization](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/accessanalyzer_analyzer) | resource |
| [aws_accessanalyzer_analyzer.organization_unused_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/accessanalyzer_analyzer) | resource |
| [aws_iam_service_linked_role.access_analyzer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_service_linked_role) | resource |
| [aws_organizations_delegated_administrator.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_delegated_administrator) | resource |
| [terraform_data.account_verification](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [aws_caller_identity.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_accessanalyzer_organization_enabled"></a> [accessanalyzer\_organization\_enabled](#input\_accessanalyzer\_organization\_enabled) | Flag to enable the Organization Access Analyzer | `bool` | n/a | yes |
| <a name="input_accessanalyzer_organization_unused_access_enabled"></a> [accessanalyzer\_organization\_unused\_access\_enabled](#input\_accessanalyzer\_organization\_unused\_access\_enabled) | Flag to enable the Organization unused access Access Analyzer | `bool` | n/a | yes |
| <a name="input_accessanalyzer_service_principal"></a> [accessanalyzer\_service\_principal](#input\_accessanalyzer\_service\_principal) | The Access Analyzer service principal for which you want to make the member account a delegated administrator | `string` | `"access-analyzer.amazonaws.com"` | no |
| <a name="input_account_map"></a> [account\_map](#input\_account\_map) | Static account map configuration. Only used when `account_map_enabled` is `false`.<br/>Map keys use `tenant-stage` format (e.g., `core-security`, `core-audit`, `plat-prod`). | <pre>object({<br/>    full_account_map              = map(string)<br/>    audit_account_account_name    = optional(string, "")<br/>    root_account_account_name     = optional(string, "")<br/>    identity_account_account_name = optional(string, "")<br/>    aws_partition                 = optional(string, "aws")<br/>    iam_role_arn_templates        = optional(map(string), {})<br/>  })</pre> | <pre>{<br/>  "audit_account_account_name": "",<br/>  "aws_partition": "aws",<br/>  "full_account_map": {},<br/>  "iam_role_arn_templates": {},<br/>  "identity_account_account_name": "",<br/>  "root_account_account_name": ""<br/>}</pre> | no |
| <a name="input_account_map_component_name"></a> [account\_map\_component\_name](#input\_account\_map\_component\_name) | The name of the account-map component | `string` | `"account-map"` | no |
| <a name="input_account_map_enabled"></a> [account\_map\_enabled](#input\_account\_map\_enabled) | Enable the account map component. When true, the component fetches account mappings from the<br/>`account-map` component via remote state. When false (default), the component uses the static `account_map` variable instead. | `bool` | `false` | no |
| <a name="input_account_map_tenant"></a> [account\_map\_tenant](#input\_account\_map\_tenant) | The tenant where the `account_map` component required by remote-state is deployed | `string` | `"core"` | no |
| <a name="input_account_verification_enabled"></a> [account\_verification\_enabled](#input\_account\_verification\_enabled) | Enable account verification. When true (default), the component verifies that Terraform is executing<br/>in the correct AWS account by comparing the current account ID against the expected account from the<br/>account\_map based on the component's tenant-stage context. | `bool` | `true` | no |
| <a name="input_additional_tag_map"></a> [additional\_tag\_map](#input\_additional\_tag\_map) | Additional key-value pairs to add to each map in `tags_as_list_of_maps`. Not added to `tags` or `id`.<br/>This is for some rare cases where resources want additional configuration of tags<br/>and therefore take a list of maps with tag key, value, and additional configuration. | `map(string)` | `{}` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Additional attributes (e.g. `workers` or `cluster`) to add to `id`,<br/>in the order they appear in the list. New attributes are appended to the<br/>end of the list. The elements of the list are joined by the `delimiter`<br/>and treated as a single ID element. | `list(string)` | `[]` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object for setting entire context at once.<br/>See description of individual variables for details.<br/>Leave string and numeric variables as `null` to use default value.<br/>Individual variable settings (non-null) override settings in context object,<br/>except for attributes, tags, and additional\_tag\_map, which are merged. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_delegated_administrator_account_name"></a> [delegated\_administrator\_account\_name](#input\_delegated\_administrator\_account\_name) | The name of the account that is the AWS Organization Delegated Administrator account | `string` | `"core-security"` | no |
| <a name="input_delimiter"></a> [delimiter](#input\_delimiter) | Delimiter to be used between ID elements.<br/>Defaults to `-` (hyphen). Set to `""` to use no delimiter at all. | `string` | `null` | no |
| <a name="input_descriptor_formats"></a> [descriptor\_formats](#input\_descriptor\_formats) | Describe additional descriptors to be output in the `descriptors` output map.<br/>Map of maps. Keys are names of descriptors. Values are maps of the form<br/>`{<br/>  format = string<br/>  labels = list(string)<br/>}`<br/>(Type is `any` so the map values can later be enhanced to provide additional options.)<br/>`format` is a Terraform format string to be passed to the `format()` function.<br/>`labels` is a list of labels, in order, to pass to `format()` function.<br/>Label values will be normalized before being passed to `format()` so they will be<br/>identical to how they appear in `id`.<br/>Default is `{}` (`descriptors` output will be empty). | `any` | `{}` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Usually used for region e.g. 'uw2', 'us-west-2', OR role 'prod', 'staging', 'dev', 'UAT' | `string` | `null` | no |
| <a name="input_global_environment"></a> [global\_environment](#input\_global\_environment) | Global environment name | `string` | `"gbl"` | no |
| <a name="input_id_length_limit"></a> [id\_length\_limit](#input\_id\_length\_limit) | Limit `id` to this many characters (minimum 6).<br/>Set to `0` for unlimited length.<br/>Set to `null` for keep the existing setting, which defaults to `0`.<br/>Does not affect `id_full`. | `number` | `null` | no |
| <a name="input_label_key_case"></a> [label\_key\_case](#input\_label\_key\_case) | Controls the letter case of the `tags` keys (label names) for tags generated by this module.<br/>Does not affect keys of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper`.<br/>Default value: `title`. | `string` | `null` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | The order in which the labels (ID elements) appear in the `id`.<br/>Defaults to ["namespace", "environment", "stage", "name", "attributes"].<br/>You can omit any of the 6 labels ("tenant" is the 6th), but at least one must be present. | `list(string)` | `null` | no |
| <a name="input_label_value_case"></a> [label\_value\_case](#input\_label\_value\_case) | Controls the letter case of ID elements (labels) as included in `id`,<br/>set as tag values, and output by this module individually.<br/>Does not affect values of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper` and `none` (no transformation).<br/>Set this to `title` and set `delimiter` to `""` to yield Pascal Case IDs.<br/>Default value: `lower`. | `string` | `null` | no |
| <a name="input_labels_as_tags"></a> [labels\_as\_tags](#input\_labels\_as\_tags) | Set of labels (ID elements) to include as tags in the `tags` output.<br/>Default is to include all labels.<br/>Tags with empty values will not be included in the `tags` output.<br/>Set to `[]` to suppress all generated tags.<br/>**Notes:**<br/>  The value of the `name` tag, if included, will be the `id`, not the `name`.<br/>  Unlike other `null-label` inputs, the initial setting of `labels_as_tags` cannot be<br/>  changed in later chained modules. Attempts to change it will be silently ignored. | `set(string)` | <pre>[<br/>  "default"<br/>]</pre> | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Usually the component or solution name, e.g. 'app' or 'jenkins'.<br/>This is the only ID element not also included as a `tag`.<br/>The "name" tag is set to the full `id` string. There is no tag with the value of the `name` input. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Usually an abbreviation of your organization name, e.g. 'eg' or 'cp', to help ensure generated IDs are globally unique | `string` | `null` | no |
| <a name="input_organizations_delegated_administrator_enabled"></a> [organizations\_delegated\_administrator\_enabled](#input\_organizations\_delegated\_administrator\_enabled) | Flag to enable the Organization delegated administrator | `bool` | n/a | yes |
| <a name="input_privileged"></a> [privileged](#input\_privileged) | true if the default provider already has access to the backend | `bool` | `false` | no |
| <a name="input_regex_replace_chars"></a> [regex\_replace\_chars](#input\_regex\_replace\_chars) | Terraform regular expression (regex) string.<br/>Characters matching the regex will be removed from the ID elements.<br/>If not set, `"/[^a-zA-Z0-9-]/"` is used to remove all characters other than hyphens, letters and digits. | `string` | `null` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS Region | `string` | n/a | yes |
| <a name="input_root_account_stage"></a> [root\_account\_stage](#input\_root\_account\_stage) | The stage name for the Organization root (management) account. This is used to lookup account IDs from account names<br/>using the `account-map` component. | `string` | `"root"` | no |
| <a name="input_service_linked_role_enabled"></a> [service\_linked\_role\_enabled](#input\_service\_linked\_role\_enabled) | Create the service-linked role `access-analyzer.amazonaws.com` in the management account | `bool` | `true` | no |
| <a name="input_stage"></a> [stage](#input\_stage) | ID element. Usually used to indicate role, e.g. 'prod', 'staging', 'source', 'build', 'test', 'deploy', 'release' | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags (e.g. `{'BusinessUnit': 'XYZ'}`).<br/>Neither the tag keys nor the tag values will be modified by this module. | `map(string)` | `{}` | no |
| <a name="input_tenant"></a> [tenant](#input\_tenant) | ID element \_(Rarely used, not included by default)\_. A customer identifier, indicating who this instance of a resource is for | `string` | `null` | no |
| <a name="input_unused_access_age"></a> [unused\_access\_age](#input\_unused\_access\_age) | The specified access age in days for which to generate findings for unused access | `number` | `30` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_aws_organizations_delegated_administrator_id"></a> [aws\_organizations\_delegated\_administrator\_id](#output\_aws\_organizations\_delegated\_administrator\_id) | AWS Organizations Delegated Administrator ID |
| <a name="output_aws_organizations_delegated_administrator_status"></a> [aws\_organizations\_delegated\_administrator\_status](#output\_aws\_organizations\_delegated\_administrator\_status) | AWS Organizations Delegated Administrator status |
| <a name="output_organization_accessanalyzer_id"></a> [organization\_accessanalyzer\_id](#output\_organization\_accessanalyzer\_id) | Organization Access Analyzer ID |
| <a name="output_organization_unused_access_accessanalyzer_id"></a> [organization\_unused\_access\_accessanalyzer\_id](#output\_organization\_unused\_access\_accessanalyzer\_id) | Organization unused access Access Analyzer ID |
| <a name="output_service_linked_role_arn"></a> [service\_linked\_role\_arn](#output\_service\_linked\_role\_arn) | ARN of the Access Analyzer service-linked role |
| <a name="output_service_linked_role_name"></a> [service\_linked\_role\_name](#output\_service\_linked\_role\_name) | Name of the Access Analyzer service-linked role |
<!-- markdownlint-restore -->




[<img src="https://cloudposse.com/logo-300x69.svg" height="32" align="right"/>](https://cpco.io/homepage?utm_source=github&utm_medium=readme&utm_campaign=cloudposse-terraform-components/aws-access-analyzer&utm_content=)

