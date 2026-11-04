---
tags:
  - component/cloudtrail-bucket
  - layer/foundation
  - provider/aws
---

# Component: `cloudtrail-bucket`

This component is responsible for provisioning a bucket for storing
CloudTrail logs for auditing purposes. It's expected to be used alongside
[the `cloudtrail` component](https://github.com/cloudposse/terraform-aws-components/tree/main/modules/cloudtrail).
## Usage

**Stack Level**: Regional

Here's an example snippet for how to use this component. It's suggested to apply this component to only the centralized
`audit` account.

```yaml
components:
  terraform:
    cloudtrail-bucket:
      vars:
        enabled: true
        name: "cloudtrail"
        noncurrent_version_expiration_days: 180
        noncurrent_version_transition_days: 30
        standard_transition_days: 60
        glacier_transition_days: 180
        expiration_days: 365
```

### S3 Object Lock Configuration

For PCI compliance, you can enable S3 Object Lock to store objects using a write-once-read-many (WORM) model.

> **Important**: Terraform can only enable Object Lock when it creates the bucket. The `object_lock_enabled` attribute
> on `aws_s3_bucket` forces replacement, so flipping it on a bucket Terraform already manages plans a destroy and
> recreate. The S3 API itself does support enabling Object Lock on an existing versioned bucket
> (`aws s3api put-object-lock-configuration`), so the way to adopt it is to make that call out of band first, then set
> the variable so Terraform matches what is already there.

Set `object_lock_enabled` to turn Object Lock on without a bucket-wide default retention rule. Objects are then
protected only when a retention period or a legal hold is applied to them individually. This is usually what you want
for a CloudTrail bucket, because a default retention period longer than `expiration_days` deadlocks the lifecycle
rule — S3 cannot delete an object that is still under retention.

```yaml
components:
  terraform:
    cloudtrail-bucket:
      vars:
        enabled: true
        name: "cloudtrail"
        versioning_enabled: true
        object_lock_enabled: true
```

Set `object_lock_configuration` instead to apply a default retention rule to every new object. Keep the retention
period shorter than `expiration_days` so lifecycle expiration can still run.

```yaml
components:
  terraform:
    cloudtrail-bucket:
      vars:
        enabled: true
        name: "cloudtrail"
        object_lock_configuration:
          mode: "GOVERNANCE"  # Valid values: GOVERNANCE, COMPLIANCE
          days: 365
          years: null
```

<!-- prettier-ignore-start -->
<!-- prettier-ignore-end -->


<!-- markdownlint-disable -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.37.0, < 7.0.0 |
| <a name="requirement_utils"></a> [utils](#requirement\_utils) | >= 2.0.0, < 3.0.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_cloudtrail_s3_bucket"></a> [cloudtrail\_s3\_bucket](#module\_cloudtrail\_s3\_bucket) | cloudposse/cloudtrail-s3-bucket/aws | 0.33.0 |
| <a name="module_iam_roles"></a> [iam\_roles](#module\_iam\_roles) | ../account-map/modules/iam-roles | n/a |
| <a name="module_this"></a> [this](#module\_this) | cloudposse/label/null | 0.25.0 |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_access_log_bucket_name"></a> [access\_log\_bucket\_name](#input\_access\_log\_bucket\_name) | If var.create\_access\_log\_bucket is false, this is the name of the S3 bucket where s3 access logs will be sent to. | `string` | `""` | no |
| <a name="input_acl"></a> [acl](#input\_acl) | The canned ACL to apply. We recommend log-delivery-write for<br/>compatibility with AWS services. Valid values are private, public-read,<br/>public-read-write, aws-exec-read, authenticated-read, bucket-owner-read,<br/>bucket-owner-full-control, log-delivery-write.<br/><br/>Due to https://docs.aws.amazon.com/AmazonS3/latest/userguide/create-bucket-faq.html, this<br/>will need to be set to 'private' during creation, but you can update normally after. | `string` | `"log-delivery-write"` | no |
| <a name="input_additional_tag_map"></a> [additional\_tag\_map](#input\_additional\_tag\_map) | Additional key-value pairs to add to each map in `tags_as_list_of_maps`. Not added to `tags` or `id`.<br/>This is for some rare cases where resources want additional configuration of tags<br/>and therefore take a list of maps with tag key, value, and additional configuration. | `map(string)` | `{}` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Additional attributes (e.g. `workers` or `cluster`) to add to `id`,<br/>in the order they appear in the list. New attributes are appended to the<br/>end of the list. The elements of the list are joined by the `delimiter`<br/>and treated as a single ID element. | `list(string)` | `[]` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object for setting entire context at once.<br/>See description of individual variables for details.<br/>Leave string and numeric variables as `null` to use default value.<br/>Individual variable settings (non-null) override settings in context object,<br/>except for attributes, tags, and additional\_tag\_map, which are merged. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_create_access_log_bucket"></a> [create\_access\_log\_bucket](#input\_create\_access\_log\_bucket) | Whether or not to create an access log bucket. | `bool` | `false` | no |
| <a name="input_delimiter"></a> [delimiter](#input\_delimiter) | Delimiter to be used between ID elements.<br/>Defaults to `-` (hyphen). Set to `""` to use no delimiter at all. | `string` | `null` | no |
| <a name="input_descriptor_formats"></a> [descriptor\_formats](#input\_descriptor\_formats) | Describe additional descriptors to be output in the `descriptors` output map.<br/>Map of maps. Keys are names of descriptors. Values are maps of the form<br/>`{<br/>  format = string<br/>  labels = list(string)<br/>}`<br/>(Type is `any` so the map values can later be enhanced to provide additional options.)<br/>`format` is a Terraform format string to be passed to the `format()` function.<br/>`labels` is a list of labels, in order, to pass to `format()` function.<br/>Label values will be normalized before being passed to `format()` so they will be<br/>identical to how they appear in `id`.<br/>Default is `{}` (`descriptors` output will be empty). | `any` | `{}` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Usually used for region e.g. 'uw2', 'us-west-2', OR role 'prod', 'staging', 'dev', 'UAT' | `string` | `null` | no |
| <a name="input_expiration_days"></a> [expiration\_days](#input\_expiration\_days) | Number of days after which to expunge the objects | `number` | `90` | no |
| <a name="input_force_destroy"></a> [force\_destroy](#input\_force\_destroy) | (Optional, Default:false ) A boolean that indicates all objects should be deleted from the bucket so that the bucket can be destroyed without error. These objects are not recoverable | `bool` | `false` | no |
| <a name="input_glacier_transition_days"></a> [glacier\_transition\_days](#input\_glacier\_transition\_days) | Number of days after which to move the data to the glacier storage tier | `number` | `60` | no |
| <a name="input_id_length_limit"></a> [id\_length\_limit](#input\_id\_length\_limit) | Limit `id` to this many characters (minimum 6).<br/>Set to `0` for unlimited length.<br/>Set to `null` for keep the existing setting, which defaults to `0`.<br/>Does not affect `id_full`. | `number` | `null` | no |
| <a name="input_label_key_case"></a> [label\_key\_case](#input\_label\_key\_case) | Controls the letter case of the `tags` keys (label names) for tags generated by this module.<br/>Does not affect keys of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper`.<br/>Default value: `title`. | `string` | `null` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | The order in which the labels (ID elements) appear in the `id`.<br/>Defaults to ["namespace", "environment", "stage", "name", "attributes"].<br/>You can omit any of the 6 labels ("tenant" is the 6th), but at least one must be present. | `list(string)` | `null` | no |
| <a name="input_label_value_case"></a> [label\_value\_case](#input\_label\_value\_case) | Controls the letter case of ID elements (labels) as included in `id`,<br/>set as tag values, and output by this module individually.<br/>Does not affect values of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper` and `none` (no transformation).<br/>Set this to `title` and set `delimiter` to `""` to yield Pascal Case IDs.<br/>Default value: `lower`. | `string` | `null` | no |
| <a name="input_labels_as_tags"></a> [labels\_as\_tags](#input\_labels\_as\_tags) | Set of labels (ID elements) to include as tags in the `tags` output.<br/>Default is to include all labels.<br/>Tags with empty values will not be included in the `tags` output.<br/>Set to `[]` to suppress all generated tags.<br/>**Notes:**<br/>  The value of the `name` tag, if included, will be the `id`, not the `name`.<br/>  Unlike other `null-label` inputs, the initial setting of `labels_as_tags` cannot be<br/>  changed in later chained modules. Attempts to change it will be silently ignored. | `set(string)` | <pre>[<br/>  "default"<br/>]</pre> | no |
| <a name="input_lifecycle_rule_enabled"></a> [lifecycle\_rule\_enabled](#input\_lifecycle\_rule\_enabled) | Enable lifecycle events on this bucket | `bool` | `true` | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Usually the component or solution name, e.g. 'app' or 'jenkins'.<br/>This is the only ID element not also included as a `tag`.<br/>The "name" tag is set to the full `id` string. There is no tag with the value of the `name` input. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Usually an abbreviation of your organization name, e.g. 'eg' or 'cp', to help ensure generated IDs are globally unique | `string` | `null` | no |
| <a name="input_noncurrent_version_expiration_days"></a> [noncurrent\_version\_expiration\_days](#input\_noncurrent\_version\_expiration\_days) | Specifies when noncurrent object versions expire | `number` | `90` | no |
| <a name="input_noncurrent_version_transition_days"></a> [noncurrent\_version\_transition\_days](#input\_noncurrent\_version\_transition\_days) | Specifies when noncurrent object versions transition to a different storage tier | `number` | `30` | no |
| <a name="input_object_lock_configuration"></a> [object\_lock\_configuration](#input\_object\_lock\_configuration) | A configuration for S3 object locking. With S3 Object Lock, you can store objects using a write-once-read-many (WORM) model. Object lock can help prevent objects from being deleted or overwritten for a fixed amount of time or indefinitely. | <pre>object({<br/>    mode  = string           # Valid values are GOVERNANCE and COMPLIANCE.<br/>    days  = optional(number) # Retention period in days. Specify either days or years, not both.<br/>    years = optional(number) # Retention period in years. Specify either days or years, not both.<br/>  })</pre> | `null` | no |
| <a name="input_object_lock_enabled"></a> [object\_lock\_enabled](#input\_object\_lock\_enabled) | Set to `true` to enable S3 Object Lock on the CloudTrail bucket without configuring a default retention rule, so objects are only protected when a retention period or legal hold is applied per object. Object Lock is also enabled implicitly when `object_lock_configuration` is set. Requires `versioning_enabled = true`. | `bool` | `false` | no |
| <a name="input_policy"></a> [policy](#input\_policy) | A valid bucket policy JSON document. This policy will be merged with the<br/>default CloudTrail bucket policies (AWSCloudTrailAclCheck and AWSCloudTrailWrite). | `string` | `""` | no |
| <a name="input_regex_replace_chars"></a> [regex\_replace\_chars](#input\_regex\_replace\_chars) | Terraform regular expression (regex) string.<br/>Characters matching the regex will be removed from the ID elements.<br/>If not set, `"/[^a-zA-Z0-9-]/"` is used to remove all characters other than hyphens, letters and digits. | `string` | `null` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS Region | `string` | n/a | yes |
| <a name="input_sse_algorithm"></a> [sse\_algorithm](#input\_sse\_algorithm) | The server-side encryption algorithm to use. Valid values are AES256, aws:kms, or aws:kms:dsse | `string` | `"AES256"` | no |
| <a name="input_stage"></a> [stage](#input\_stage) | ID element. Usually used to indicate role, e.g. 'prod', 'staging', 'source', 'build', 'test', 'deploy', 'release' | `string` | `null` | no |
| <a name="input_standard_transition_days"></a> [standard\_transition\_days](#input\_standard\_transition\_days) | Number of days to persist in the standard storage tier before moving to the infrequent access tier | `number` | `30` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags (e.g. `{'BusinessUnit': 'XYZ'}`).<br/>Neither the tag keys nor the tag values will be modified by this module. | `map(string)` | `{}` | no |
| <a name="input_tenant"></a> [tenant](#input\_tenant) | ID element \_(Rarely used, not included by default)\_. A customer identifier, indicating who this instance of a resource is for | `string` | `null` | no |
| <a name="input_versioning_enabled"></a> [versioning\_enabled](#input\_versioning\_enabled) | A state of versioning. Versioning is a means of keeping multiple variants of an object in the same bucket | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cloudtrail_bucket_arn"></a> [cloudtrail\_bucket\_arn](#output\_cloudtrail\_bucket\_arn) | CloudTrail S3 bucket ARN |
| <a name="output_cloudtrail_bucket_domain_name"></a> [cloudtrail\_bucket\_domain\_name](#output\_cloudtrail\_bucket\_domain\_name) | CloudTrail S3 bucket domain name |
| <a name="output_cloudtrail_bucket_id"></a> [cloudtrail\_bucket\_id](#output\_cloudtrail\_bucket\_id) | CloudTrail S3 bucket ID |
<!-- markdownlint-restore -->



## References


- [cloudposse-terraform-components](https://github.com/orgs/cloudposse-terraform-components/repositories) - Cloud Posse's upstream component




[<img src="https://cloudposse.com/logo-300x69.svg" height="32" align="right"/>](https://cpco.io/homepage?utm_source=github&utm_medium=readme&utm_campaign=cloudposse-terraform-components/aws-cloudtrail-bucket&utm_content=)

