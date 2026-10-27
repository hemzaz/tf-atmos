---
tags:
  - component/aws-scp
  - layer/accounts
  - provider/aws
  - privileged
---

# Component: `scp`

This component is responsible for creating a single Service Control Policy (SCP) and optionally
attaching it to a target (organization root, OU, or account).

Unlike the monolithic `account` component which manages SCPs as part of the organization hierarchy,
this component follows the single-resource pattern - it only manages a single SCP.

> [!NOTE]
>
> This component should be deployed from the **management/root account** as it creates SCPs
> within AWS Organizations.
## Usage

**Stack Level**: Global (deployed in the management/root account)

### Using the SCP Policy Catalog (recommended)

This component ships with a `catalog/` directory of pre-built SCP policies based on
[CloudPosse terraform-aws-service-control-policies v0.15.1](https://github.com/cloudposse/terraform-aws-service-control-policies).
Each file contains a single policy statement that maps to one SCP. Use Atmos `!include` to
reference catalog files directly (local path) or from a remote source:

**Local include** (when the catalog is vendored with the component):

```yaml
components:
  terraform:
    aws-scp/iam-restrictions:
      metadata:
        component: aws-scp
      vars:
        enabled: true
        policy_name: IAMRestrictions
        policy_description: "Restrict IAM user creation and deny root account access"
        policy_statements:
          - !include catalog/DenyIAMCreatingUsers.yaml
          - !include catalog/DenyIAMRootAccount.yaml
          - !include catalog/DenyLeavingOrganization.yaml
        target_id: !terraform.output aws-organizational-unit/core organizational_unit_id
```

**Remote include** (reference the catalog directly from GitHub):

```yaml
components:
  terraform:
    aws-scp/iam-restrictions:
      metadata:
        component: aws-scp
      vars:
        enabled: true
        policy_name: IAMRestrictions
        policy_statements:
          - !include "https://github.com/cloudposse-terraform-components/aws-scp/blob/main/catalog/DenyIAMCreatingUsers.yaml"
          - !include "https://github.com/cloudposse-terraform-components/aws-scp/blob/main/catalog/DenyIAMRootAccount.yaml"
          - !include "https://github.com/cloudposse-terraform-components/aws-scp/blob/main/catalog/DenyLeavingOrganization.yaml"
        target_id: !terraform.output aws-organizational-unit/core organizational_unit_id
```

Atmos supports multiple remote protocols including `https://`, `github://`, `s3://`, and `gcs://`
via [go-getter](https://atmos.tools/functions/yaml/include#remote-sources). Standard GitHub URLs
(with `/blob/` or `/tree/`) are automatically converted to raw content URLs.

Available catalog files:

**Account & Organization:**
- `DenyAccountRegionDisableEnable.yaml` - Deny enabling/disabling AWS regions
- `DenyLeavingOrganization.yaml` - Prevent leaving the organization
- `DenyRootAccountAccess.yaml` - Deny all actions by root account
- `DenyAllAccess.yaml` - Deny all access (quarantine)

**IAM:**
- `DenyIAMCreatingUsers.yaml` - Deny IAM user and access key creation
- `DenyIAMRolesChanges.yaml` - Deny IAM role modifications
- `DenyIAMNoMFA.yaml` - Require MFA for most actions (uses `not_actions`)
- `DenyIAMRootAccount.yaml` - Deny all actions by IAM root account

**EC2 & Compute:**
- `DenyEC2NonNitroInstances.yaml` - Require Nitro-based instance types
- `DenyEC2InstancesWithoutEncryptionInTransit.yaml` - Require encryption-in-transit capable instances
- `DenyEC2PublicAMI.yaml` - Deny launching from public AMIs
- `DenyEC2AssociatePublicIp.yaml` - Deny public IP assignment
- `DenyEC2WithNoIMDSv2.yaml` - Require IMDSv2
- `DenyEC2ApiWithNoMFA.yaml` - Require MFA for stop/terminate
- `RequireEBSEncryption.yaml` - Require EBS volume encryption
- `DenyLambdaWithoutVpc.yaml` - Require VPC for Lambda functions

**Storage & Database:**
- `DenyS3DeleteBucketsAndObjects.yaml` - Prevent S3 bucket/object deletion
- `DenyS3BucketsPublicAccess.yaml` - Prevent modifying S3 public access blocks
- `DenyS3IncorrectEncryptionHeader.yaml` - Require S3 server-side encryption
- `DenyS3UnEncryptedObjectUploads.yaml` - Deny unencrypted S3 uploads
- `DenyRDSUnencrypted.yaml` - Require RDS encryption
- `DenyDeletingKMSKeys.yaml` - Prevent KMS key deletion

**Networking:**
- `DenyVpcDeletingFlowLogs.yaml` - Protect VPC flow logs
- `DenyVpcInternetAccess.yaml` - Deny internet gateway and VPC peering creation
- `DenyRoute53DeletingZones.yaml` - Prevent hosted zone deletion

**Security & Monitoring:**
- `DenyCloudTrailActions.yaml` - Protect CloudTrail configuration
- `DenyCloudWatchDeletingLogs.yaml` - Protect CloudWatch log groups
- `DenyDisablingCloudWatch.yaml` - Protect CloudWatch alarms and dashboards
- `DenyConfigRulesDelete.yaml` - Protect AWS Config rules and recorders
- `DenyGuardDutyDisassociation.yaml` - Prevent GuardDuty disassociation
- `DenyDisablingGuardDuty.yaml` - Protect GuardDuty configuration
- `DenyShieldlRemoval.yaml` - Prevent Shield protection removal

**SageMaker:**
- `DenySagemakerDirectInternetNotebook.yaml` - Deny direct internet for notebooks
- `DenySagemakerWithoutRootAccess.yaml` - Require root access for notebooks
- `DenySagemakerWithoutInterContainerEncrypt.yaml` - Require inter-container encryption
- `DenyeSagemakerWithoutVpcDomain.yaml` - Deny public internet domains

### Using inline policy_statements

```yaml
components:
  terraform:
    aws-scp/deny-leaving-organization:
      metadata:
        component: aws-scp
      vars:
        enabled: true
        policy_name: DenyLeavingOrganization
        policy_description: "Prevents accounts from leaving the organization"
        policy_statements:
          - sid: "DenyLeaveOrganization"
            effect: "Deny"
            actions:
              - "organizations:LeaveOrganization"
            resources:
              - "*"
        target_ids:
          - !terraform.output aws-organizational-unit/core organizational_unit_id
```

### Using policy_content (raw JSON)

```yaml
components:
  terraform:
    aws-scp/custom-policy:
      metadata:
        component: aws-scp
      vars:
        enabled: true
        policy_name: CustomPolicy
        policy_content: |
          {
            "Version": "2012-10-17",
            "Statement": [
              {
                "Effect": "Deny",
                "Action": ["ec2:RunInstances"],
                "Resource": "*"
              }
            ]
          }
        target_ids:
          - !terraform.output aws-organizational-unit/plat organizational_unit_id
```

### Policy Without Attachment

Create a policy without attaching it to any target:

```yaml
components:
  terraform:
    aws-scp/deny-root-user:
      metadata:
        component: aws-scp
      vars:
        enabled: true
        policy_name: DenyRootUser
        attach_to_target: false
        policy_statements:
          - sid: "DenyRootUser"
            effect: "Deny"
            actions:
              - "*"
            resources:
              - "*"
            conditions:
              - test: "StringLike"
                variable: "aws:PrincipalArn"
                values:
                  - "arn:aws:iam::*:root"
```

### Importing an Existing SCP

To import an existing SCP:

1. Get the policy ID from AWS Console or CLI

2. Set the `import_policy_id` variable:
   ```yaml
   vars:
     import_policy_id: "p-xxxxxxxxxx"
   ```

3. Run `atmos terraform apply`

After successful import, you can remove the `import_policy_id` variable.

> **Note:** If you don't need import functionality, you can exclude `imports.tf` when vendoring the component.

## Policy Statements Format

Each statement must specify either `actions` or `not_actions`, but not both.
`not_actions` maps to the IAM `NotAction` element, which matches all actions except the listed ones.

```yaml
policy_statements:
  - sid: "OptionalStatementId"
    effect: "Deny"  # or "Allow"
    actions:         # use actions OR not_actions
      - "service:Action"
    resources:
      - "*"
    conditions:  # optional
      - test: "StringEquals"
        variable: "aws:RequestedRegion"
        values:
          - "us-east-1"

  - sid: "ExampleWithNotActions"
    effect: "Deny"
    not_actions:     # matches everything EXCEPT these actions
      - "iam:CreateVirtualMFADevice"
      - "iam:EnableMFADevice"
    resources:
      - "*"
```

## Related Components

This component is part of a suite of single-resource components for AWS Organizations:

| Component | Purpose |
|-----------|---------|
| `aws-organization` | Creates/imports the AWS Organization |
| `aws-organizational-unit` | Creates/imports a single OU |
| `aws-account` | Creates/imports a single AWS Account |
| `aws-account-settings` | Configures account settings |
| `aws-scp` | Creates/imports Service Control Policies (this component) |


<!-- markdownlint-disable -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.66 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.66 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_this"></a> [this](#module\_this) | cloudposse/label/null | 0.25.0 |

## Resources

| Name | Type |
|------|------|
| [aws_organizations_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy) | resource |
| [aws_organizations_policy_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy_attachment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_additional_tag_map"></a> [additional\_tag\_map](#input\_additional\_tag\_map) | Additional key-value pairs to add to each map in `tags_as_list_of_maps`. Not added to `tags` or `id`.<br/>This is for some rare cases where resources want additional configuration of tags<br/>and therefore take a list of maps with tag key, value, and additional configuration. | `map(string)` | `{}` | no |
| <a name="input_attach_to_target"></a> [attach\_to\_target](#input\_attach\_to\_target) | Whether to attach the SCP to a target. Set to false to create the policy without attaching it. | `bool` | `true` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Additional attributes (e.g. `workers` or `cluster`) to add to `id`,<br/>in the order they appear in the list. New attributes are appended to the<br/>end of the list. The elements of the list are joined by the `delimiter`<br/>and treated as a single ID element. | `list(string)` | `[]` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object for setting entire context at once.<br/>See description of individual variables for details.<br/>Leave string and numeric variables as `null` to use default value.<br/>Individual variable settings (non-null) override settings in context object,<br/>except for attributes, tags, and additional\_tag\_map, which are merged. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_delimiter"></a> [delimiter](#input\_delimiter) | Delimiter to be used between ID elements.<br/>Defaults to `-` (hyphen). Set to `""` to use no delimiter at all. | `string` | `null` | no |
| <a name="input_descriptor_formats"></a> [descriptor\_formats](#input\_descriptor\_formats) | Describe additional descriptors to be output in the `descriptors` output map.<br/>Map of maps. Keys are names of descriptors. Values are maps of the form<br/>`{<br/>   format = string<br/>   labels = list(string)<br/>}`<br/>(Type is `any` so the map values can later be enhanced to provide additional options.)<br/>`format` is a Terraform format string to be passed to the `format()` function.<br/>`labels` is a list of labels, in order, to pass to `format()` function.<br/>Label values will be normalized before being passed to `format()` so they will be<br/>identical to how they appear in `id`.<br/>Default is `{}` (`descriptors` output will be empty). | `any` | `{}` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Usually used for region e.g. 'uw2', 'us-west-2', OR role 'prod', 'staging', 'dev', 'UAT' | `string` | `null` | no |
| <a name="input_id_length_limit"></a> [id\_length\_limit](#input\_id\_length\_limit) | Limit `id` to this many characters (minimum 6).<br/>Set to `0` for unlimited length.<br/>Set to `null` for keep the existing setting, which defaults to `0`.<br/>Does not affect `id_full`. | `number` | `null` | no |
| <a name="input_import_policy_id"></a> [import\_policy\_id](#input\_import\_policy\_id) | The ID of an existing SCP to import | `string` | `null` | no |
| <a name="input_import_target_ids"></a> [import\_target\_ids](#input\_import\_target\_ids) | The IDs of the targets (organization roots, OUs, or accounts) that already have the SCP attached, to import existing attachments. Must be a subset of target\_ids. | `list(string)` | `[]` | no |
| <a name="input_label_key_case"></a> [label\_key\_case](#input\_label\_key\_case) | Controls the letter case of the `tags` keys (label names) for tags generated by this module.<br/>Does not affect keys of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper`.<br/>Default value: `title`. | `string` | `null` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | The order in which the labels (ID elements) appear in the `id`.<br/>Defaults to ["namespace", "environment", "stage", "name", "attributes"].<br/>You can omit any of the 6 labels ("tenant" is the 6th), but at least one must be present. | `list(string)` | `null` | no |
| <a name="input_label_value_case"></a> [label\_value\_case](#input\_label\_value\_case) | Controls the letter case of ID elements (labels) as included in `id`,<br/>set as tag values, and output by this module individually.<br/>Does not affect values of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper` and `none` (no transformation).<br/>Set this to `title` and set `delimiter` to `""` to yield Pascal Case IDs.<br/>Default value: `lower`. | `string` | `null` | no |
| <a name="input_labels_as_tags"></a> [labels\_as\_tags](#input\_labels\_as\_tags) | Set of labels (ID elements) to include as tags in the `tags` output.<br/>Default is to include all labels.<br/>Tags with empty values will not be included in the `tags` output.<br/>Set to `[]` to suppress all generated tags.<br/>**Notes:**<br/>  The value of the `name` tag, if included, will be the `id`, not the `name`.<br/>  Unlike other `null-label` inputs, the initial setting of `labels_as_tags` cannot be<br/>  changed in later chained modules. Attempts to change it will be silently ignored. | `set(string)` | <pre>[<br/>  "default"<br/>]</pre> | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Usually the component or solution name, e.g. 'app' or 'jenkins'.<br/>This is the only ID element not also included as a `tag`.<br/>The "name" tag is set to the full `id` string. There is no tag with the value of the `name` input. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Usually an abbreviation of your organization name, e.g. 'eg' or 'cp', to help ensure generated IDs are globally unique | `string` | `null` | no |
| <a name="input_policy_content"></a> [policy\_content](#input\_policy\_content) | The JSON policy document for the SCP. If not provided, policy\_statements will be used to generate the policy. | `string` | `null` | no |
| <a name="input_policy_description"></a> [policy\_description](#input\_policy\_description) | Description of the SCP | `string` | `"Service Control Policy managed by Terraform"` | no |
| <a name="input_policy_name"></a> [policy\_name](#input\_policy\_name) | The name of the Service Control Policy. Defaults to module.this.id | `string` | `null` | no |
| <a name="input_policy_statements"></a> [policy\_statements](#input\_policy\_statements) | List of policy statements to generate the SCP. Alternative to policy\_content. Each statement must specify either 'actions' or 'not\_actions', but not both. | <pre>list(object({<br/>    sid         = optional(string)<br/>    effect      = string<br/>    actions     = optional(list(string), [])<br/>    not_actions = optional(list(string), [])<br/>    resources   = list(string)<br/>    conditions = optional(list(object({<br/>      test     = string<br/>      variable = string<br/>      values   = list(string)<br/>    })), [])<br/>  }))</pre> | `[]` | no |
| <a name="input_regex_replace_chars"></a> [regex\_replace\_chars](#input\_regex\_replace\_chars) | Terraform regular expression (regex) string.<br/>Characters matching the regex will be removed from the ID elements.<br/>If not set, `"/[^a-zA-Z0-9-]/"` is used to remove all characters other than hyphens, letters and digits. | `string` | `null` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS Region | `string` | n/a | yes |
| <a name="input_skip_destroy"></a> [skip\_destroy](#input\_skip\_destroy) | If true, the policy will be detached from the target but not destroyed when removed from Terraform | `bool` | `false` | no |
| <a name="input_stage"></a> [stage](#input\_stage) | ID element. Usually used to indicate role, e.g. 'prod', 'staging', 'source', 'build', 'test', 'deploy', 'release' | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags (e.g. `{'BusinessUnit': 'XYZ'}`).<br/>Neither the tag keys nor the tag values will be modified by this module. | `map(string)` | `{}` | no |
| <a name="input_target_id"></a> [target\_id](#input\_target\_id) | DEPRECATED: Use `target_ids` instead. The ID of the organization root, OU, or account to attach the SCP to. | `string` | `null` | no |
| <a name="input_target_ids"></a> [target\_ids](#input\_target\_ids) | The IDs of the organization roots, OUs, or accounts to attach the SCP to | `list(string)` | `[]` | no |
| <a name="input_tenant"></a> [tenant](#input\_tenant) | ID element \_(Rarely used, not included by default)\_. A customer identifier, indicating who this instance of a resource is for | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_attached"></a> [attached](#output\_attached) | Whether the SCP was attached to any targets |
| <a name="output_attachment_ids"></a> [attachment\_ids](#output\_attachment\_ids) | Map of target IDs to policy attachment IDs |
| <a name="output_policy_arn"></a> [policy\_arn](#output\_policy\_arn) | The ARN of the Service Control Policy |
| <a name="output_policy_id"></a> [policy\_id](#output\_policy\_id) | The ID of the Service Control Policy |
| <a name="output_policy_name"></a> [policy\_name](#output\_policy\_name) | The name of the Service Control Policy |
| <a name="output_target_ids"></a> [target\_ids](#output\_target\_ids) | The target IDs the SCP is attached to |
<!-- markdownlint-restore -->



## References


- [cloudposse-terraform-components](https://github.com/orgs/cloudposse-terraform-components/repositories) - Cloud Posse's upstream components

- [Service Control Policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html) - AWS Service Control Policies documentation

- [OpenTofu Import Blocks](https://opentofu.org/docs/language/import/) - OpenTofu 1.7+ import block documentation




[<img src="https://cloudposse.com/logo-300x69.svg" height="32" align="right"/>](https://cpco.io/homepage?utm_source=github&utm_medium=readme&utm_campaign=cloudposse-terraform-components/aws-scp&utm_content=)

