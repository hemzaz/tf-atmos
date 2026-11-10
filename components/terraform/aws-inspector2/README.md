---
tags:
  - component/aws-inspector2
  - layer/security-and-compliance
  - provider/aws
---

# Component: `inspector2`

This component is responsible for configuring Inspector V2 within an AWS Organization.

## Component Features

- **Delegated Administrator Model**: Uses AWS Organizations delegated administrator pattern for centralized management
- **Multi-Region Deployment**: Supports deployment across all AWS regions
- **Auto-enablement**: Automatically enables EC2, ECR, and Lambda scanning for organization members
- **Member Management**: Configurable member association with exclusion list support
- **Account Verification**: Optional safety check that validates Terraform is running in the correct AWS account
- **Flexible Account Map**: Supports both remote-state account-map lookups and static account map variables (default)
## Usage

**Stack Level**: Regional

## Deployment Overview

The deployment of this component requires multiple runs with different variable settings to properly configure the AWS
Organization. First, you delegate Inspector V2 central management to the Administrator account (usually `security`
account). After the Administrator account is delegated, we configure it to manage Inspector V2 across all the
Organization accounts and send all their findings to that account.

In the examples below, we assume that the AWS Organization Management account is `root` and the AWS Organization
Delegated Administrator account is `security`.

### Deploy to Organization Management Account

First, the component is deployed to the AWS Organization Management account `root` in each region in order to configure
the [AWS Delegated Administrator account](https://docs.aws.amazon.com/inspector/latest/user/designating-admin.html) that
operates Amazon Inspector V2.

```yaml
components:
  terraform:
    aws-inspector2/root:
      metadata:
        component: aws-inspector2
      vars:
        enabled: true
```

### Deploy Organization Settings in Delegated Administrator Account

Now the component can be deployed to the Delegated Administrator Account `security` to create the organization-wide
configuration for all the Organization accounts. Note that `var.admin_delegated` set to `true` indicates that the
delegation has already been performed from the Organization Management account, and only the resources required for
organization-wide configuration will be created.

```yaml
components:
  terraform:
    aws-inspector2/org-settings:
      metadata:
        component: aws-inspector2
      vars:
        enabled: true
        admin_delegated: true
```


<!-- markdownlint-disable -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.4.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0.0 |
| <a name="requirement_awsutils"></a> [awsutils](#requirement\_awsutils) | >= 0.16.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.0.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_account_map"></a> [account\_map](#module\_account\_map) | cloudposse/stack-config/yaml//modules/remote-state | 1.8.0 |
| <a name="module_this"></a> [this](#module\_this) | cloudposse/label/null | 0.25.0 |

## Resources

| Name | Type |
|------|------|
| [aws_inspector2_delegated_admin_account.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/inspector2_delegated_admin_account) | resource |
| [aws_inspector2_enabler.delegated_admin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/inspector2_enabler) | resource |
| [aws_inspector2_enabler.member_accounts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/inspector2_enabler) | resource |
| [aws_inspector2_member_association.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/inspector2_member_association) | resource |
| [aws_inspector2_organization_configuration.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/inspector2_organization_configuration) | resource |
| [terraform_data.account_verification](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [aws_caller_identity.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_account_map"></a> [account\_map](#input\_account\_map) | Static account map configuration. Only used when `account_map_enabled` is `false`.<br/>Map keys use `tenant-stage` format (e.g., `core-security`, `core-audit`, `plat-prod`). | <pre>object({<br/>    full_account_map              = map(string)<br/>    audit_account_account_name    = optional(string, "")<br/>    root_account_account_name     = optional(string, "")<br/>    identity_account_account_name = optional(string, "")<br/>    aws_partition                 = optional(string, "aws")<br/>    iam_role_arn_templates        = optional(map(string), {})<br/>  })</pre> | <pre>{<br/>  "audit_account_account_name": "",<br/>  "aws_partition": "aws",<br/>  "full_account_map": {},<br/>  "iam_role_arn_templates": {},<br/>  "identity_account_account_name": "",<br/>  "root_account_account_name": ""<br/>}</pre> | no |
| <a name="input_account_map_component_name"></a> [account\_map\_component\_name](#input\_account\_map\_component\_name) | The name of the account-map component | `string` | `"account-map"` | no |
| <a name="input_account_map_enabled"></a> [account\_map\_enabled](#input\_account\_map\_enabled) | Enable the account map component. When true, the component fetches account mappings from the<br/>`account-map` component via remote state. When false (default), the component uses the static `account_map` variable instead. | `bool` | `false` | no |
| <a name="input_account_map_tenant"></a> [account\_map\_tenant](#input\_account\_map\_tenant) | The tenant where the `account_map` component required by remote-state is deployed | `string` | `"core"` | no |
| <a name="input_account_verification_enabled"></a> [account\_verification\_enabled](#input\_account\_verification\_enabled) | Enable account verification. When true (default), the component verifies that Terraform is executing<br/>in the correct AWS account by comparing the current account ID against the expected account from the<br/>account\_map based on the component's tenant-stage context. | `bool` | `true` | no |
| <a name="input_additional_tag_map"></a> [additional\_tag\_map](#input\_additional\_tag\_map) | Additional key-value pairs to add to each map in `tags_as_list_of_maps`. Not added to `tags` or `id`.<br/>This is for some rare cases where resources want additional configuration of tags<br/>and therefore take a list of maps with tag key, value, and additional configuration. | `map(string)` | `{}` | no |
| <a name="input_admin_delegated"></a> [admin\_delegated](#input\_admin\_delegated) | A flag to indicate if the AWS Organization-wide settings should be created. This can only be done after the Inspector V2<br/>  Administrator account has already been delegated from the AWS Org Management account (usually 'root'). See the<br/>  Deployment section of the README for more information. | `bool` | `false` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Additional attributes (e.g. `workers` or `cluster`) to add to `id`,<br/>in the order they appear in the list. New attributes are appended to the<br/>end of the list. The elements of the list are joined by the `delimiter`<br/>and treated as a single ID element. | `list(string)` | `[]` | no |
| <a name="input_auto_enable_ec2"></a> [auto\_enable\_ec2](#input\_auto\_enable\_ec2) | Whether Amazon EC2 scans are automatically enabled for new members of the Amazon Inspector organization. | `bool` | `true` | no |
| <a name="input_auto_enable_ecr"></a> [auto\_enable\_ecr](#input\_auto\_enable\_ecr) | Whether Amazon ECR scans are automatically enabled for new members of the Amazon Inspector organization. | `bool` | `true` | no |
| <a name="input_auto_enable_lambda"></a> [auto\_enable\_lambda](#input\_auto\_enable\_lambda) | Whether Lambda Function scans are automatically enabled for new members of the Amazon Inspector organization. | `bool` | `true` | no |
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
| <a name="input_member_association_excludes"></a> [member\_association\_excludes](#input\_member\_association\_excludes) | List of account names to exclude from Amazon Inspector member association | `list(string)` | `[]` | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Usually the component or solution name, e.g. 'app' or 'jenkins'.<br/>This is the only ID element not also included as a `tag`.<br/>The "name" tag is set to the full `id` string. There is no tag with the value of the `name` input. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Usually an abbreviation of your organization name, e.g. 'eg' or 'cp', to help ensure generated IDs are globally unique | `string` | `null` | no |
| <a name="input_organization_management_account_name"></a> [organization\_management\_account\_name](#input\_organization\_management\_account\_name) | The name of the AWS Organization management account | `string` | `null` | no |
| <a name="input_privileged"></a> [privileged](#input\_privileged) | true if the default provider already has access to the backend | `bool` | `false` | no |
| <a name="input_regex_replace_chars"></a> [regex\_replace\_chars](#input\_regex\_replace\_chars) | Terraform regular expression (regex) string.<br/>Characters matching the regex will be removed from the ID elements.<br/>If not set, `"/[^a-zA-Z0-9-]/"` is used to remove all characters other than hyphens, letters and digits. | `string` | `null` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS Region | `string` | n/a | yes |
| <a name="input_root_account_stage"></a> [root\_account\_stage](#input\_root\_account\_stage) | The stage name for the Organization root (management) account. This is used to lookup account IDs from account names<br/>using the `account-map` component. | `string` | `"root"` | no |
| <a name="input_stage"></a> [stage](#input\_stage) | ID element. Usually used to indicate role, e.g. 'prod', 'staging', 'source', 'build', 'test', 'deploy', 'release' | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags (e.g. `{'BusinessUnit': 'XYZ'}`).<br/>Neither the tag keys nor the tag values will be modified by this module. | `map(string)` | `{}` | no |
| <a name="input_tenant"></a> [tenant](#input\_tenant) | ID element \_(Rarely used, not included by default)\_. A customer identifier, indicating who this instance of a resource is for | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_aws_inspector2_member_association"></a> [aws\_inspector2\_member\_association](#output\_aws\_inspector2\_member\_association) | The Inspector2 member association resource. |
<!-- markdownlint-restore -->



## References


- [Amazon Inspector V2 Documentation](https://docs.aws.amazon.com/inspector/latest/user/what-is-inspector.html) - 

- [Cloud Posse's upstream component](https://github.com/cloudposse/terraform-aws-components/tree/main/modules/inspector2/common/) - 




[<img src="https://cloudposse.com/logo-300x69.svg" height="32" align="right"/>](https://cpco.io/homepage?utm_source=github&utm_medium=readme&utm_campaign=cloudposse-terraform-components/aws-inspector2&utm_content=)

