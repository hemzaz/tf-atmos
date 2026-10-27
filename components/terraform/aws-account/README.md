---
tags:
  - component/aws-account
  - layer/accounts
  - provider/aws
  - privileged
---

# Component: `account`

This component is responsible for creating or importing a single AWS Account within an AWS Organization.

Unlike the monolithic `account` component which manages the entire organization hierarchy,
this component follows the single-resource pattern - it only manages a single AWS account.

> [!NOTE]
>
> This component should be deployed from the **management/root account** as it creates accounts
> within AWS Organizations.

## Key Features

- **Single-resource pattern**: Manages exactly one AWS account per component instance
- **Conditional import blocks** (OpenTofu/Terraform 1.7+): Easily import existing accounts into Terraform state
- **Independent lifecycle**: Each account can be managed independently without affecting others
- **Simple configuration**: Minimal variables required for account creation
## Usage

**Stack Level**: Global (deployed in the management/root account)

This component creates or imports a single AWS account. For managing the entire organization hierarchy,
see the companion components: `aws-organization`, `aws-organizational-unit`, `aws-account-settings`, and `aws-scp`.

### Basic Usage

```yaml
components:
  terraform:
    aws-account/core-analytics:
      metadata:
        component: aws-account
      vars:
        name: core-analytics
        account_email: "aws+myorg-core-analytics@example.com"
        parent_id: "ou-xxxx-xxxxxxxx"
```

### Using Remote State for Parent ID

Reference the parent OU dynamically using Atmos remote state:

```yaml
components:
  terraform:
    aws-account/core-analytics:
      metadata:
        component: aws-account
      vars:
        name: core-analytics
        account_email: "aws+myorg-core-analytics@example.com"
        parent_id: !terraform.output aws-organizational-unit/core organizational_unit_id
```

### Importing an Existing Account

To import an existing AWS account into Terraform state:

```yaml
components:
  terraform:
    aws-account/core-analytics:
      metadata:
        component: aws-account
      vars:
        name: core-analytics
        account_email: "aws+myorg-core-analytics@example.com"
        parent_id: "ou-xxxx-xxxxxxxx"
        import_account_id: "123456789012"
```

After the import succeeds, you can remove the `import_account_id` variable.

### Using Catalog Defaults

Create a defaults file for consistent configuration:

```yaml
# stacks/catalog/aws-account/defaults.yaml
components:
  terraform:
    aws-account/defaults:
      metadata:
        component: aws-account
        type: abstract
      vars:
        enabled: true
        iam_user_access_to_billing: DENY
        close_on_deletion: false
```

Then inherit from defaults:

```yaml
# stacks/orgs/myorg/core/root/global-region.yaml
import:
  - catalog/aws-account/defaults

components:
  terraform:
    aws-account/core-analytics:
      metadata:
        component: aws-account
        inherits:
          - aws-account/defaults
      vars:
        name: core-analytics
        account_email: "aws+myorg-core-analytics@example.com"
        parent_id: !terraform.output aws-organizational-unit/core organizational_unit_id
```

### Complete Example with Multiple Accounts

```yaml
components:
  terraform:
    # Core OU Accounts
    aws-account/core-analytics:
      metadata:
        component: aws-account
        inherits:
          - aws-account/defaults
      vars:
        name: core-analytics
        account_email: "aws+myorg-core-analytics@example.com"
        parent_id: !terraform.output aws-organizational-unit/core organizational_unit_id
        import_account_id: "111111111111"

    aws-account/core-security:
      metadata:
        component: aws-account
        inherits:
          - aws-account/defaults
      vars:
        name: core-security
        account_email: "aws+myorg-core-security@example.com"
        parent_id: !terraform.output aws-organizational-unit/core organizational_unit_id
        import_account_id: "222222222222"

    # Platform OU Accounts
    aws-account/plat-dev:
      metadata:
        component: aws-account
        inherits:
          - aws-account/defaults
      vars:
        name: plat-dev
        account_email: "aws+myorg-plat-dev@example.com"
        parent_id: !terraform.output aws-organizational-unit/plat organizational_unit_id
        import_account_id: "333333333333"

    aws-account/plat-prod:
      metadata:
        component: aws-account
        inherits:
          - aws-account/defaults
      vars:
        name: plat-prod
        account_email: "aws+myorg-plat-prod@example.com"
        parent_id: !terraform.output aws-organizational-unit/plat organizational_unit_id
        import_account_id: "444444444444"
```

## Related Components

This component is part of a suite of single-resource components for AWS Organizations:

| Component | Purpose |
|-----------|---------|
| `aws-organization` | Creates/imports the AWS Organization |
| `aws-organizational-unit` | Creates/imports a single Organizational Unit |
| `aws-account` | Creates/imports a single AWS Account (this component) |
| `aws-account-settings` | Configures account settings (IAM alias, S3 block, EBS encryption) |
| `aws-scp` | Creates/imports Service Control Policies |


<!-- markdownlint-disable -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 4.9.0, < 6.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 4.9.0, < 6.0.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_this"></a> [this](#module\_this) | cloudposse/label/null | 0.25.0 |

## Resources

| Name | Type |
|------|------|
| [aws_organizations_account.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_account) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_account_email"></a> [account\_email](#input\_account\_email) | The email address for the AWS account | `string` | n/a | yes |
| <a name="input_additional_tag_map"></a> [additional\_tag\_map](#input\_additional\_tag\_map) | Additional key-value pairs to add to each map in `tags_as_list_of_maps`. Not added to `tags` or `id`.<br/>This is for some rare cases where resources want additional configuration of tags<br/>and therefore take a list of maps with tag key, value, and additional configuration. | `map(string)` | `{}` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Additional attributes (e.g. `workers` or `cluster`) to add to `id`,<br/>in the order they appear in the list. New attributes are appended to the<br/>end of the list. The elements of the list are joined by the `delimiter`<br/>and treated as a single ID element. | `list(string)` | `[]` | no |
| <a name="input_close_on_deletion"></a> [close\_on\_deletion](#input\_close\_on\_deletion) | Whether to close the account on deletion | `bool` | `false` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object for setting entire context at once.<br/>See description of individual variables for details.<br/>Leave string and numeric variables as `null` to use default value.<br/>Individual variable settings (non-null) override settings in context object,<br/>except for attributes, tags, and additional\_tag\_map, which are merged. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_delimiter"></a> [delimiter](#input\_delimiter) | Delimiter to be used between ID elements.<br/>Defaults to `-` (hyphen). Set to `""` to use no delimiter at all. | `string` | `null` | no |
| <a name="input_descriptor_formats"></a> [descriptor\_formats](#input\_descriptor\_formats) | Describe additional descriptors to be output in the `descriptors` output map.<br/>Map of maps. Keys are names of descriptors. Values are maps of the form<br/>`{<br/>  format = string<br/>  labels = list(string)<br/>}`<br/>(Type is `any` so the map values can later be enhanced to provide additional options.)<br/>`format` is a Terraform format string to be passed to the `format()` function.<br/>`labels` is a list of labels, in order, to pass to `format()` function.<br/>Label values will be normalized before being passed to `format()` so they will be<br/>identical to how they appear in `id`.<br/>Default is `{}` (`descriptors` output will be empty). | `any` | `{}` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Usually used for region e.g. 'uw2', 'us-west-2', OR role 'prod', 'staging', 'dev', 'UAT' | `string` | `null` | no |
| <a name="input_iam_user_access_to_billing"></a> [iam\_user\_access\_to\_billing](#input\_iam\_user\_access\_to\_billing) | Whether IAM users can access billing. ALLOW or DENY | `string` | `"DENY"` | no |
| <a name="input_id_length_limit"></a> [id\_length\_limit](#input\_id\_length\_limit) | Limit `id` to this many characters (minimum 6).<br/>Set to `0` for unlimited length.<br/>Set to `null` for keep the existing setting, which defaults to `0`.<br/>Does not affect `id_full`. | `number` | `null` | no |
| <a name="input_import_account_id"></a> [import\_account\_id](#input\_import\_account\_id) | The AWS account ID to import. Set this to import an existing account into Terraform state. | `string` | `null` | no |
| <a name="input_label_key_case"></a> [label\_key\_case](#input\_label\_key\_case) | Controls the letter case of the `tags` keys (label names) for tags generated by this module.<br/>Does not affect keys of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper`.<br/>Default value: `title`. | `string` | `null` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | The order in which the labels (ID elements) appear in the `id`.<br/>Defaults to ["namespace", "environment", "stage", "name", "attributes"].<br/>You can omit any of the 6 labels ("tenant" is the 6th), but at least one must be present. | `list(string)` | `null` | no |
| <a name="input_label_value_case"></a> [label\_value\_case](#input\_label\_value\_case) | Controls the letter case of ID elements (labels) as included in `id`,<br/>set as tag values, and output by this module individually.<br/>Does not affect values of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper` and `none` (no transformation).<br/>Set this to `title` and set `delimiter` to `""` to yield Pascal Case IDs.<br/>Default value: `lower`. | `string` | `null` | no |
| <a name="input_labels_as_tags"></a> [labels\_as\_tags](#input\_labels\_as\_tags) | Set of labels (ID elements) to include as tags in the `tags` output.<br/>Default is to include all labels.<br/>Tags with empty values will not be included in the `tags` output.<br/>Set to `[]` to suppress all generated tags.<br/>**Notes:**<br/>  The value of the `name` tag, if included, will be the `id`, not the `name`.<br/>  Unlike other `null-label` inputs, the initial setting of `labels_as_tags` cannot be<br/>  changed in later chained modules. Attempts to change it will be silently ignored. | `set(string)` | <pre>[<br/>  "default"<br/>]</pre> | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Usually the component or solution name, e.g. 'app' or 'jenkins'.<br/>This is the only ID element not also included as a `tag`.<br/>The "name" tag is set to the full `id` string. There is no tag with the value of the `name` input. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Usually an abbreviation of your organization name, e.g. 'eg' or 'cp', to help ensure generated IDs are globally unique | `string` | `null` | no |
| <a name="input_parent_id"></a> [parent\_id](#input\_parent\_id) | The ID of the parent Organizational Unit or organization root | `string` | n/a | yes |
| <a name="input_regex_replace_chars"></a> [regex\_replace\_chars](#input\_regex\_replace\_chars) | Terraform regular expression (regex) string.<br/>Characters matching the regex will be removed from the ID elements.<br/>If not set, `"/[^a-zA-Z0-9-]/"` is used to remove all characters other than hyphens, letters and digits. | `string` | `null` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS Region | `string` | n/a | yes |
| <a name="input_role_name"></a> [role\_name](#input\_role\_name) | The name of the IAM role that Organizations creates in the new member account | `string` | `null` | no |
| <a name="input_stage"></a> [stage](#input\_stage) | ID element. Usually used to indicate role, e.g. 'prod', 'staging', 'source', 'build', 'test', 'deploy', 'release' | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags (e.g. `{'BusinessUnit': 'XYZ'}`).<br/>Neither the tag keys nor the tag values will be modified by this module. | `map(string)` | `{}` | no |
| <a name="input_tenant"></a> [tenant](#input\_tenant) | ID element \_(Rarely used, not included by default)\_. A customer identifier, indicating who this instance of a resource is for | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_account_arn"></a> [account\_arn](#output\_account\_arn) | The ARN of the AWS account |
| <a name="output_account_email"></a> [account\_email](#output\_account\_email) | The email of the AWS account |
| <a name="output_account_id"></a> [account\_id](#output\_account\_id) | The ID of the AWS account |
| <a name="output_account_name"></a> [account\_name](#output\_account\_name) | The name of the AWS account |
| <a name="output_parent_id"></a> [parent\_id](#output\_parent\_id) | The parent ID of the account |
<!-- markdownlint-restore -->



## References


- [cloudposse-terraform-components](https://github.com/orgs/cloudposse-terraform-components/repositories) - Cloud Posse's upstream components

- [AWS Organizations Accounts](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_accounts.html) - AWS Organizations account management documentation

- [OpenTofu Import Blocks](https://opentofu.org/docs/language/import/) - OpenTofu 1.7+ import block documentation




[<img src="https://cloudposse.com/logo-300x69.svg" height="32" align="right"/>](https://cpco.io/homepage?utm_source=github&utm_medium=readme&utm_campaign=cloudposse-terraform-components/aws-account&utm_content=)

