---
tags:
  - component/guardduty
  - layer/security-and-compliance
  - provider/aws
---

# Component: `guardduty`

This component is responsible for configuring GuardDuty within an AWS Organization.

AWS GuardDuty is a managed threat detection service. It is designed to help protect AWS accounts and workloads by
continuously monitoring for malicious activities and unauthorized behaviors. To detect potential security threats,
GuardDuty analyzes various data sources within your AWS environment, such as AWS CloudTrail logs, VPC Flow Logs, and DNS
logs.

Key features and components of AWS GuardDuty include:

- Threat detection: GuardDuty employs machine learning algorithms, anomaly detection, and integrated threat intelligence
  to identify suspicious activities, unauthorized access attempts, and potential security threats. It analyzes event
  logs and network traffic data to detect patterns, anomalies, and known attack techniques.

- Threat intelligence: GuardDuty leverages threat intelligence feeds from AWS, trusted partners, and the global
  community to enhance its detection capabilities. It uses this intelligence to identify known malicious IP addresses,
  domains, and other indicators of compromise.

- Real-time alerts: When GuardDuty identifies a potential security issue, it generates real-time alerts that can be
  delivered through AWS CloudWatch Events. These alerts can be integrated with other AWS services like Amazon SNS or AWS
  Lambda for immediate action or custom response workflows.

- Multi-account support: GuardDuty can be enabled across multiple AWS accounts, allowing centralized management and
  monitoring of security across an entire organization's AWS infrastructure. This helps to maintain consistent security
  policies and practices.

- Automated remediation: GuardDuty integrates with other AWS services, such as AWS Macie, AWS Security Hub, and AWS
  Systems Manager, to facilitate automated threat response and remediation actions. This helps to minimize the impact of
  security incidents and reduces the need for manual intervention.

- Security findings and reports: GuardDuty provides detailed security findings and reports that include information
  about detected threats, affected AWS resources, and recommended remediation actions. These findings can be accessed
  through the AWS Management Console or retrieved via APIs for further analysis and reporting.

GuardDuty offers a scalable and flexible approach to threat detection within AWS environments, providing organizations
with an additional layer of security to proactively identify and respond to potential security risks.

## Supported GuardDuty Protection Features

This component supports the following GuardDuty protection features:

- **S3 Protection**: Monitors S3 data events to detect suspicious activities in your S3 buckets
- **EKS Audit Log Monitoring**: Analyzes Kubernetes audit logs from Amazon EKS clusters
- **Malware Protection**: Scans EBS volumes attached to EC2 instances for malware
- **Lambda Protection**: Monitors Lambda function network activity logs
- **Runtime Monitoring**: Provides runtime threat detection for EC2, ECS, and EKS workloads with automatic security agent management

## SNS Notifications

This component creates its own SNS topic, SQS queue, and KMS key for GuardDuty findings notifications instead of using
the ones from the upstream `cloudposse/guardduty/aws` module. This is a workaround for
[cloudposse/terraform-aws-guardduty#10](https://github.com/cloudposse/terraform-aws-guardduty/issues/10) where the
module's SNS topic encryption doesn't grant EventBridge permission to decrypt messages.

The component creates:
- A custom **KMS key** with proper permissions for EventBridge, SNS, and SQS services
- An **SNS topic** encrypted with the custom KMS key
- An **SQS queue** subscribed to the SNS topic for message processing
- **CloudWatch Event Rules** to route GuardDuty findings to the SNS topic

To enable notifications, set `create_sns_topic: true` and `cloudwatch_enabled: true`.

## Component Features

- **Delegated Administrator Model**: Uses AWS Organizations delegated administrator pattern for centralized management
- **Multi-Region Deployment**: Supports deployment across all AWS regions
- **Protection Features**: Configurable protection for S3, EKS, Lambda, Malware, and Runtime Monitoring
- **SNS Notifications**: Optional SNS topic creation with KMS encryption for finding alerts
- **Account Verification**: Optional safety check that validates Terraform is running in the correct AWS account
- **Flexible Account Map**: Supports both remote-state account-map lookups and static account map variables (default)
## Usage

**Stack Level**: Regional

## Prerequisites

Before deploying this component, ensure that GuardDuty trusted access is enabled in AWS Organizations. This can be done
by adding `guardduty.amazonaws.com` to the `aws_service_access_principals` list in your `account` component, or by
running the following command from the management account:

```bash
aws organizations enable-aws-service-access --service-principal guardduty.amazonaws.com
```

## Deployment Overview

This component is complex in that it must be deployed multiple times with different variables set to configure the AWS
Organization successfully.

It is further complicated by the fact that you must deploy each of the the component instances described below to every
region that existed before March 2019 and to any regions that have been opted-in as described in the
[AWS Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-regions-availability-zones.html#concepts-regions).

In the examples below, we assume that the AWS Organization Management account is `root` and the AWS Organization
Delegated Administrator account is `security`, both in the `core` tenant.

### Step 1: Deploy to Delegated Administrator Account

First, the component is deployed to the
[Delegated Administrator](https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_organizations.html) account in each
region in order to configure the central GuardDuty detector that each account will send its findings to.

```yaml
# core-use1-security
components:
  terraform:
    aws-guardduty/delegated-administrator:
      metadata:
        component: aws-guardduty
      vars:
        enabled: true
        delegated_administrator_account_name: core-security
```

```bash
atmos terraform apply aws-guardduty/delegated-administrator -s core-use1-security
atmos terraform apply aws-guardduty/delegated-administrator -s core-use2-security
atmos terraform apply aws-guardduty/delegated-administrator -s core-usw1-security
# ... other regions
```

### Step 2: Deploy to Organization Management (root) Account

Next, the component is deployed to the AWS Organization Management, a/k/a `root`, Account in order to set the AWS
Organization Designated Administrator account.

Note that you must use the `SuperAdmin` permissions as we are deploying to the AWS Organization Management account. Since
we are using the `SuperAdmin` user, it will already have access to the state bucket, so we set `var.privileged` to
`true`.

```yaml
# core-use1-root
components:
  terraform:
    aws-guardduty/root:
      metadata:
        component: aws-guardduty
      vars:
        enabled: true
        delegated_administrator_account_name: core-security
        privileged: true
```

```bash
atmos terraform apply aws-guardduty/root -s core-use1-root
atmos terraform apply aws-guardduty/root -s core-use2-root
atmos terraform apply aws-guardduty/root -s core-usw1-root
# ... other regions
```

### Step 3: Deploy Organization Settings in Delegated Administrator Account

Finally, the component is deployed to the Delegated Administrator Account again in order to create the organization-wide
configuration for the AWS Organization, but with `var.admin_delegated` set to `true` to indicate that the delegation has
already been performed from the Organization Management account.

```yaml
# core-use1-security
components:
  terraform:
    aws-guardduty/org-settings:
      metadata:
        component: aws-guardduty
      vars:
        enabled: true
        delegated_administrator_account_name: core-security
        admin_delegated: true
```

```bash
atmos terraform apply aws-guardduty/org-settings -s core-use1-security
atmos terraform apply aws-guardduty/org-settings -s core-use2-security
atmos terraform apply aws-guardduty/org-settings -s core-usw1-security
# ... other regions
```

### Enabling GuardDuty Protection Features

You can enable various GuardDuty protection features by setting the corresponding variables. Here's an example with
all protection features enabled:

```yaml
# core-use1-security
components:
  terraform:
    aws-guardduty/org-settings:
      metadata:
        component: aws-guardduty
      vars:
        enabled: true
        delegated_administrator_account_name: core-security
        admin_delegated: true
        # Protection features
        s3_protection_enabled: true
        kubernetes_audit_logs_enabled: true
        malware_protection_scan_ec2_ebs_volumes_enabled: true
        lambda_network_logs_enabled: true
        # Runtime Monitoring with automatic agent management
        runtime_monitoring_enabled: true
        runtime_monitoring_additional_config:
          eks_addon_management_enabled: true
          ecs_fargate_agent_management_enabled: true
          ec2_agent_management_enabled: true
```

> **Note**: You cannot enable both `eks_runtime_monitoring_enabled` and `runtime_monitoring_enabled` at the same time.
> Use `runtime_monitoring_enabled` if you want runtime monitoring across EC2, ECS, and EKS resources.

### Enabling SNS Notifications

To enable SNS notifications for GuardDuty findings, set `create_sns_topic` and `cloudwatch_enabled` to `true`:

```yaml
# core-use1-security
components:
  terraform:
    aws-guardduty/delegated-administrator:
      metadata:
        component: aws-guardduty
      vars:
        enabled: true
        delegated_administrator_account_name: core-security
        # Enable SNS notifications
        create_sns_topic: true
        cloudwatch_enabled: true
```

This will create:
- A KMS key with permissions for EventBridge, SNS, and SQS
- An encrypted SNS topic for GuardDuty findings
- An SQS queue subscribed to the SNS topic
- CloudWatch Event Rules to route findings to SNS

<!-- prettier-ignore-start -->
<!-- prettier-ignore-end -->


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
| <a name="provider_awsutils"></a> [awsutils](#provider\_awsutils) | >= 0.16.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_account_map"></a> [account\_map](#module\_account\_map) | cloudposse/stack-config/yaml//modules/remote-state | 1.8.0 |
| <a name="module_findings_label"></a> [findings\_label](#module\_findings\_label) | cloudposse/label/null | 0.25.0 |
| <a name="module_guardduty"></a> [guardduty](#module\_guardduty) | cloudposse/guardduty/aws | 1.0.0 |
| <a name="module_guardduty_delegated_detector"></a> [guardduty\_delegated\_detector](#module\_guardduty\_delegated\_detector) | cloudposse/stack-config/yaml//modules/remote-state | 1.8.0 |
| <a name="module_kms_key"></a> [kms\_key](#module\_kms\_key) | cloudposse/kms-key/aws | 0.12.2 |
| <a name="module_queue_policy"></a> [queue\_policy](#module\_queue\_policy) | cloudposse/iam-policy/aws | 2.0.2 |
| <a name="module_sns_topic"></a> [sns\_topic](#module\_sns\_topic) | cloudposse/sns-topic/aws | 1.2.0 |
| <a name="module_sqs"></a> [sqs](#module\_sqs) | terraform-aws-modules/sqs/aws | 4.3.1 |
| <a name="module_this"></a> [this](#module\_this) | cloudposse/label/null | 0.25.0 |

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_event_rule.findings](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.imported_findings](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_guardduty_organization_admin_account.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_organization_admin_account) | resource |
| [aws_guardduty_organization_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_organization_configuration) | resource |
| [aws_guardduty_organization_configuration_feature.additional](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_organization_configuration_feature) | resource |
| [aws_guardduty_organization_configuration_feature.ebs_malware_protection](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_organization_configuration_feature) | resource |
| [aws_guardduty_organization_configuration_feature.eks_audit_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_organization_configuration_feature) | resource |
| [aws_guardduty_organization_configuration_feature.eks_runtime_monitoring](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_organization_configuration_feature) | resource |
| [aws_guardduty_organization_configuration_feature.lambda_network_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_organization_configuration_feature) | resource |
| [aws_guardduty_organization_configuration_feature.runtime_monitoring](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_organization_configuration_feature) | resource |
| [aws_guardduty_organization_configuration_feature.s3_data_events](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_organization_configuration_feature) | resource |
| [aws_sns_topic_policy.sns_topic_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_policy) | resource |
| [aws_sqs_queue_policy.sqs_queue_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_policy) | resource |
| [awsutils_guardduty_organization_settings.this](https://registry.terraform.io/providers/cloudposse/awsutils/latest/docs/resources/guardduty_organization_settings) | resource |
| [terraform_data.account_verification](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_caller_identity.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.sns_topic_combined_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_organizations_organization.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/organizations_organization) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_account_map"></a> [account\_map](#input\_account\_map) | Static account map configuration. Only used when `account_map_enabled` is `false`.<br/>Map keys use `tenant-stage` format (e.g., `core-security`, `core-audit`, `plat-prod`). | <pre>object({<br/>    full_account_map              = map(string)<br/>    audit_account_account_name    = optional(string, "")<br/>    root_account_account_name     = optional(string, "")<br/>    identity_account_account_name = optional(string, "")<br/>    aws_partition                 = optional(string, "aws")<br/>    iam_role_arn_templates        = optional(map(string), {})<br/>  })</pre> | <pre>{<br/>  "audit_account_account_name": "",<br/>  "aws_partition": "aws",<br/>  "full_account_map": {},<br/>  "iam_role_arn_templates": {},<br/>  "identity_account_account_name": "",<br/>  "root_account_account_name": ""<br/>}</pre> | no |
| <a name="input_account_map_component_name"></a> [account\_map\_component\_name](#input\_account\_map\_component\_name) | The name of the account-map component | `string` | `"account-map"` | no |
| <a name="input_account_map_enabled"></a> [account\_map\_enabled](#input\_account\_map\_enabled) | Enable the account map component. When true, the component fetches account mappings from the<br/>`account-map` component via remote state. When false (default), the component uses the static `account_map` variable instead. | `bool` | `false` | no |
| <a name="input_account_map_tenant"></a> [account\_map\_tenant](#input\_account\_map\_tenant) | The tenant where the `account_map` component required by remote-state is deployed | `string` | `"core"` | no |
| <a name="input_account_verification_enabled"></a> [account\_verification\_enabled](#input\_account\_verification\_enabled) | Enable account verification. When true (default), the component verifies that Terraform is executing<br/>in the correct AWS account by comparing the current account ID against the expected account from the<br/>account\_map based on the component's tenant-stage context. | `bool` | `true` | no |
| <a name="input_additional_tag_map"></a> [additional\_tag\_map](#input\_additional\_tag\_map) | Additional key-value pairs to add to each map in `tags_as_list_of_maps`. Not added to `tags` or `id`.<br/>This is for some rare cases where resources want additional configuration of tags<br/>and therefore take a list of maps with tag key, value, and additional configuration. | `map(string)` | `{}` | no |
| <a name="input_admin_delegated"></a> [admin\_delegated](#input\_admin\_delegated) | A flag to indicate if the AWS Organization-wide settings should be created. This can only be done after the GuardDuty<br/>  Administrator account has already been delegated from the AWS Org Management account (usually 'root'). See the<br/>  Deployment section of the README for more information. | `bool` | `false` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Additional attributes (e.g. `workers` or `cluster`) to add to `id`,<br/>in the order they appear in the list. New attributes are appended to the<br/>end of the list. The elements of the list are joined by the `delimiter`<br/>and treated as a single ID element. | `list(string)` | `[]` | no |
| <a name="input_auto_enable_organization_members"></a> [auto\_enable\_organization\_members](#input\_auto\_enable\_organization\_members) | Indicates the auto-enablement configuration of GuardDuty for the member accounts in the organization. Valid values are `ALL`, `NEW`, `NONE`.<br/><br/>For more information, see:<br/>https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_organization_configuration#auto_enable_organization_members | `string` | `"NEW"` | no |
| <a name="input_cloudwatch_enabled"></a> [cloudwatch\_enabled](#input\_cloudwatch\_enabled) | Flag to indicate whether CloudWatch logging should be enabled for GuardDuty | `bool` | `false` | no |
| <a name="input_cloudwatch_event_rule_pattern_detail_type"></a> [cloudwatch\_event\_rule\_pattern\_detail\_type](#input\_cloudwatch\_event\_rule\_pattern\_detail\_type) | The detail-type pattern used to match events that will be sent to SNS.<br/><br/>For more information, see:<br/>https://docs.aws.amazon.com/AmazonCloudWatch/latest/events/CloudWatchEventsandEventPatterns.html<br/>https://docs.aws.amazon.com/eventbridge/latest/userguide/event-types.html<br/>https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_findings_cloudwatch.html | `string` | `"GuardDuty Finding"` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object for setting entire context at once.<br/>See description of individual variables for details.<br/>Leave string and numeric variables as `null` to use default value.<br/>Individual variable settings (non-null) override settings in context object,<br/>except for attributes, tags, and additional\_tag\_map, which are merged. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_create_sns_topic"></a> [create\_sns\_topic](#input\_create\_sns\_topic) | Flag to indicate whether an SNS topic should be created for notifications. If you want to send findings to a new SNS<br/>topic, set this to true and provide a valid configuration for subscribers. | `bool` | `false` | no |
| <a name="input_delegated_administrator_account_name"></a> [delegated\_administrator\_account\_name](#input\_delegated\_administrator\_account\_name) | The name of the account that is the AWS Organization Delegated Administrator account | `string` | `"core-security"` | no |
| <a name="input_delegated_administrator_component_name"></a> [delegated\_administrator\_component\_name](#input\_delegated\_administrator\_component\_name) | The name of the component that created the GuardDuty detector. | `string` | `"aws-guardduty/delegated-administrator"` | no |
| <a name="input_delimiter"></a> [delimiter](#input\_delimiter) | Delimiter to be used between ID elements.<br/>Defaults to `-` (hyphen). Set to `""` to use no delimiter at all. | `string` | `null` | no |
| <a name="input_descriptor_formats"></a> [descriptor\_formats](#input\_descriptor\_formats) | Describe additional descriptors to be output in the `descriptors` output map.<br/>Map of maps. Keys are names of descriptors. Values are maps of the form<br/>`{<br/>  format = string<br/>  labels = list(string)<br/>}`<br/>(Type is `any` so the map values can later be enhanced to provide additional options.)<br/>`format` is a Terraform format string to be passed to the `format()` function.<br/>`labels` is a list of labels, in order, to pass to `format()` function.<br/>Label values will be normalized before being passed to `format()` so they will be<br/>identical to how they appear in `id`.<br/>Default is `{}` (`descriptors` output will be empty). | `any` | `{}` | no |
| <a name="input_detector_features"></a> [detector\_features](#input\_detector\_features) | A map of detector features for streaming foundational data sources to detect communication with known malicious domains and IP addresses and identify anomalous behavior.<br/><br/>For more information, see:<br/>https://docs.aws.amazon.com/guardduty/latest/ug/guardduty-features-activation-model.html#guardduty-features<br/><br/>feature\_name:<br/>  The name of the detector feature. Possible values include: S3\_DATA\_EVENTS, EKS\_AUDIT\_LOGS, EBS\_MALWARE\_PROTECTION, RDS\_LOGIN\_EVENTS, EKS\_RUNTIME\_MONITORING, LAMBDA\_NETWORK\_LOGS, RUNTIME\_MONITORING. Specifying both EKS Runtime Monitoring (EKS\_RUNTIME\_MONITORING) and Runtime Monitoring (RUNTIME\_MONITORING) will cause an error. You can add only one of these two features because Runtime Monitoring already includes the threat detection for Amazon EKS resources. For more information, see: https://docs.aws.amazon.com/guardduty/latest/APIReference/API_DetectorFeatureConfiguration.html.<br/>status:<br/>  The status of the detector feature. Valid values include: ENABLED or DISABLED.<br/>additional\_configuration:<br/>  Optional list of additional configurations for a feature in your GuardDuty account. For more information, see: https://docs.aws.amazon.com/guardduty/latest/APIReference/API_DetectorAdditionalConfiguration.html.<br/>addon\_name:<br/>  The name of the add-on for which the configuration applies. Possible values include: EKS\_ADDON\_MANAGEMENT, ECS\_FARGATE\_AGENT\_MANAGEMENT, and EC2\_AGENT\_MANAGEMENT. For more information, see: https://docs.aws.amazon.com/guardduty/latest/APIReference/API_DetectorAdditionalConfiguration.html.<br/>status:<br/>  The status of the add-on. Valid values include: ENABLED or DISABLED. | <pre>map(object({<br/>    feature_name = string<br/>    status       = string<br/>    additional_configuration = optional(list(object({<br/>      addon_name = string<br/>      status     = string<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_eks_runtime_monitoring_enabled"></a> [eks\_runtime\_monitoring\_enabled](#input\_eks\_runtime\_monitoring\_enabled) | If `true`, enables EKS Runtime Monitoring.<br/>Note: Do not enable both EKS\_RUNTIME\_MONITORING and RUNTIME\_MONITORING as Runtime Monitoring already includes<br/>threat detection for Amazon EKS resources.<br/><br/>For more information, see:<br/>https://docs.aws.amazon.com/guardduty/latest/ug/eks-runtime-monitoring.html | `bool` | `false` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Usually used for region e.g. 'uw2', 'us-west-2', OR role 'prod', 'staging', 'dev', 'UAT' | `string` | `null` | no |
| <a name="input_finding_publishing_frequency"></a> [finding\_publishing\_frequency](#input\_finding\_publishing\_frequency) | The frequency of notifications sent for finding occurrences. If the detector is a GuardDuty member account, the value<br/>is determined by the GuardDuty master account and cannot be modified, otherwise it defaults to SIX\_HOURS.<br/><br/>For standalone and GuardDuty master accounts, it must be configured in Terraform to enable drift detection.<br/>Valid values for standalone and master accounts: FIFTEEN\_MINUTES, ONE\_HOUR, SIX\_HOURS."<br/><br/>For more information, see:<br/>https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_findings_cloudwatch.html#guardduty_findings_cloudwatch_notification_frequency | `string` | `null` | no |
| <a name="input_findings_notification_arn"></a> [findings\_notification\_arn](#input\_findings\_notification\_arn) | The ARN for an SNS topic to send findings notifications to. This is only used if create\_sns\_topic is false.<br/>If you want to send findings to an existing SNS topic, set this to the ARN of the existing topic and set<br/>create\_sns\_topic to false. | `string` | `null` | no |
| <a name="input_global_environment"></a> [global\_environment](#input\_global\_environment) | Global environment name | `string` | `"gbl"` | no |
| <a name="input_id_length_limit"></a> [id\_length\_limit](#input\_id\_length\_limit) | Limit `id` to this many characters (minimum 6).<br/>Set to `0` for unlimited length.<br/>Set to `null` for keep the existing setting, which defaults to `0`.<br/>Does not affect `id_full`. | `number` | `null` | no |
| <a name="input_kubernetes_audit_logs_enabled"></a> [kubernetes\_audit\_logs\_enabled](#input\_kubernetes\_audit\_logs\_enabled) | If `true`, enables Kubernetes audit logs as a data source for Kubernetes protection.<br/><br/>For more information, see:<br/>https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_detector#audit_logs | `bool` | `false` | no |
| <a name="input_label_key_case"></a> [label\_key\_case](#input\_label\_key\_case) | Controls the letter case of the `tags` keys (label names) for tags generated by this module.<br/>Does not affect keys of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper`.<br/>Default value: `title`. | `string` | `null` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | The order in which the labels (ID elements) appear in the `id`.<br/>Defaults to ["namespace", "environment", "stage", "name", "attributes"].<br/>You can omit any of the 6 labels ("tenant" is the 6th), but at least one must be present. | `list(string)` | `null` | no |
| <a name="input_label_value_case"></a> [label\_value\_case](#input\_label\_value\_case) | Controls the letter case of ID elements (labels) as included in `id`,<br/>set as tag values, and output by this module individually.<br/>Does not affect values of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper` and `none` (no transformation).<br/>Set this to `title` and set `delimiter` to `""` to yield Pascal Case IDs.<br/>Default value: `lower`. | `string` | `null` | no |
| <a name="input_labels_as_tags"></a> [labels\_as\_tags](#input\_labels\_as\_tags) | Set of labels (ID elements) to include as tags in the `tags` output.<br/>Default is to include all labels.<br/>Tags with empty values will not be included in the `tags` output.<br/>Set to `[]` to suppress all generated tags.<br/>**Notes:**<br/>  The value of the `name` tag, if included, will be the `id`, not the `name`.<br/>  Unlike other `null-label` inputs, the initial setting of `labels_as_tags` cannot be<br/>  changed in later chained modules. Attempts to change it will be silently ignored. | `set(string)` | <pre>[<br/>  "default"<br/>]</pre> | no |
| <a name="input_lambda_network_logs_enabled"></a> [lambda\_network\_logs\_enabled](#input\_lambda\_network\_logs\_enabled) | If `true`, enables Lambda network logs as a data source for Lambda protection.<br/><br/>For more information, see:<br/>https://docs.aws.amazon.com/guardduty/latest/ug/lambda-protection.html | `bool` | `false` | no |
| <a name="input_malware_protection_scan_ec2_ebs_volumes_enabled"></a> [malware\_protection\_scan\_ec2\_ebs\_volumes\_enabled](#input\_malware\_protection\_scan\_ec2\_ebs\_volumes\_enabled) | Configure whether Malware Protection is enabled as data source for EC2 instances EBS Volumes in GuardDuty.<br/><br/>For more information, see:<br/>https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_detector#malware-protection | `bool` | `false` | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Usually the component or solution name, e.g. 'app' or 'jenkins'.<br/>This is the only ID element not also included as a `tag`.<br/>The "name" tag is set to the full `id` string. There is no tag with the value of the `name` input. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Usually an abbreviation of your organization name, e.g. 'eg' or 'cp', to help ensure generated IDs are globally unique | `string` | `null` | no |
| <a name="input_organization_management_account_name"></a> [organization\_management\_account\_name](#input\_organization\_management\_account\_name) | The name of the AWS Organization management account | `string` | `null` | no |
| <a name="input_privileged"></a> [privileged](#input\_privileged) | true if the default provider already has access to the backend | `bool` | `false` | no |
| <a name="input_regex_replace_chars"></a> [regex\_replace\_chars](#input\_regex\_replace\_chars) | Terraform regular expression (regex) string.<br/>Characters matching the regex will be removed from the ID elements.<br/>If not set, `"/[^a-zA-Z0-9-]/"` is used to remove all characters other than hyphens, letters and digits. | `string` | `null` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS Region | `string` | n/a | yes |
| <a name="input_root_account_stage"></a> [root\_account\_stage](#input\_root\_account\_stage) | The stage name for the Organization root (management) account. This is used to lookup account IDs from account names<br/>using the `account-map` component. | `string` | `"root"` | no |
| <a name="input_runtime_monitoring_additional_config"></a> [runtime\_monitoring\_additional\_config](#input\_runtime\_monitoring\_additional\_config) | Additional configuration for Runtime Monitoring features.<br/><br/>eks\_addon\_management\_enabled: Enable EKS add-on management<br/>ecs\_fargate\_agent\_management\_enabled: Enable ECS Fargate agent management<br/>ec2\_agent\_management\_enabled: Enable EC2 agent management<br/><br/>For more information, see:<br/>https://docs.aws.amazon.com/guardduty/latest/ug/runtime-monitoring.html | <pre>object({<br/>    eks_addon_management_enabled         = optional(bool, false)<br/>    ecs_fargate_agent_management_enabled = optional(bool, false)<br/>    ec2_agent_management_enabled         = optional(bool, false)<br/>  })</pre> | `{}` | no |
| <a name="input_runtime_monitoring_enabled"></a> [runtime\_monitoring\_enabled](#input\_runtime\_monitoring\_enabled) | If `true`, enables Runtime Monitoring for EC2, ECS, and EKS resources.<br/>Note: Runtime Monitoring already includes threat detection for Amazon EKS resources, so you should not enable both<br/>RUNTIME\_MONITORING and EKS\_RUNTIME\_MONITORING features.<br/><br/>For more information, see:<br/>https://docs.aws.amazon.com/guardduty/latest/ug/runtime-monitoring.html | `bool` | `false` | no |
| <a name="input_s3_protection_enabled"></a> [s3\_protection\_enabled](#input\_s3\_protection\_enabled) | If `true`, enables S3 protection.<br/><br/>For more information, see:<br/>https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_detector#s3-logs | `bool` | `true` | no |
| <a name="input_stage"></a> [stage](#input\_stage) | ID element. Usually used to indicate role, e.g. 'prod', 'staging', 'source', 'build', 'test', 'deploy', 'release' | `string` | `null` | no |
| <a name="input_subscribers"></a> [subscribers](#input\_subscribers) | A map of subscription configurations for SNS topics<br/><br/>For more information, see:<br/>https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription#argument-reference<br/><br/>protocol:<br/>  The protocol to use. The possible values for this are: sqs, sms, lambda, application. (http or https are partially<br/>  supported, see link) (email is an option but is unsupported in terraform, see link).<br/>endpoint:<br/>  The endpoint to send data to, the contents will vary with the protocol. (see link for more information)<br/>endpoint\_auto\_confirms:<br/>  Boolean indicating whether the end point is capable of auto confirming subscription e.g., PagerDuty. Default is<br/>  false.<br/>raw\_message\_delivery:<br/>  Boolean indicating whether or not to enable raw message delivery (the original message is directly passed, not<br/>  wrapped in JSON with the original message in the message property). Default is false. | <pre>map(object({<br/>    protocol               = string<br/>    endpoint               = string<br/>    endpoint_auto_confirms = bool<br/>    raw_message_delivery   = bool<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags (e.g. `{'BusinessUnit': 'XYZ'}`).<br/>Neither the tag keys nor the tag values will be modified by this module. | `map(string)` | `{}` | no |
| <a name="input_tenant"></a> [tenant](#input\_tenant) | ID element \_(Rarely used, not included by default)\_. A customer identifier, indicating who this instance of a resource is for | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cloudwatch_event_rule_arn"></a> [cloudwatch\_event\_rule\_arn](#output\_cloudwatch\_event\_rule\_arn) | The ARN of the CloudWatch Event Rule for GuardDuty findings |
| <a name="output_cloudwatch_event_rule_id"></a> [cloudwatch\_event\_rule\_id](#output\_cloudwatch\_event\_rule\_id) | The ID of the CloudWatch Event Rule for GuardDuty findings |
| <a name="output_delegated_administrator_account_id"></a> [delegated\_administrator\_account\_id](#output\_delegated\_administrator\_account\_id) | The AWS Account ID of the AWS Organization delegated administrator account |
| <a name="output_guardduty_delegated_detector_arn"></a> [guardduty\_delegated\_detector\_arn](#output\_guardduty\_delegated\_detector\_arn) | The ARN of the GuardDuty detector from the delegated administrator account (via remote state) |
| <a name="output_guardduty_delegated_detector_id"></a> [guardduty\_delegated\_detector\_id](#output\_guardduty\_delegated\_detector\_id) | The ID of the GuardDuty detector from the delegated administrator account (via remote state) |
| <a name="output_guardduty_detector_arn"></a> [guardduty\_detector\_arn](#output\_guardduty\_detector\_arn) | The ARN of the GuardDuty detector created by the component in this account |
| <a name="output_guardduty_detector_id"></a> [guardduty\_detector\_id](#output\_guardduty\_detector\_id) | The ID of the GuardDuty detector created by the component in this account |
| <a name="output_root_kms_key_alias"></a> [root\_kms\_key\_alias](#output\_root\_kms\_key\_alias) | The alias of the KMS key used for encrypting the GuardDuty SNS topic |
| <a name="output_root_kms_key_arn"></a> [root\_kms\_key\_arn](#output\_root\_kms\_key\_arn) | The ARN of the KMS key used for encrypting the GuardDuty SNS topic |
| <a name="output_root_kms_key_id"></a> [root\_kms\_key\_id](#output\_root\_kms\_key\_id) | The ID of the KMS key used for encrypting the GuardDuty SNS topic |
| <a name="output_root_sns_topic_arn"></a> [root\_sns\_topic\_arn](#output\_root\_sns\_topic\_arn) | The ARN of the root-level SNS topic created for GuardDuty findings |
| <a name="output_root_sns_topic_id"></a> [root\_sns\_topic\_id](#output\_root\_sns\_topic\_id) | The ID of the root-level SNS topic created for GuardDuty findings |
| <a name="output_root_sns_topic_name"></a> [root\_sns\_topic\_name](#output\_root\_sns\_topic\_name) | The name of the root-level SNS topic created for GuardDuty findings |
| <a name="output_root_sqs_queue_arn"></a> [root\_sqs\_queue\_arn](#output\_root\_sqs\_queue\_arn) | The ARN of the SQS queue subscribed to the GuardDuty SNS topic |
| <a name="output_root_sqs_queue_name"></a> [root\_sqs\_queue\_name](#output\_root\_sqs\_queue\_name) | The name of the SQS queue subscribed to the GuardDuty SNS topic |
| <a name="output_root_sqs_queue_url"></a> [root\_sqs\_queue\_url](#output\_root\_sqs\_queue\_url) | The URL of the SQS queue subscribed to the GuardDuty SNS topic |
| <a name="output_sns_topic_name"></a> [sns\_topic\_name](#output\_sns\_topic\_name) | The name of the SNS topic created for GuardDuty findings |
| <a name="output_sns_topic_subscriptions"></a> [sns\_topic\_subscriptions](#output\_sns\_topic\_subscriptions) | The SNS topic subscriptions for GuardDuty findings |
<!-- markdownlint-restore -->



## References


- [AWS GuardDuty Documentation](https://aws.amazon.com/guardduty/) - 

- [Cloud Posse terraform-aws-guardduty module](https://github.com/cloudposse/terraform-aws-guardduty) - The underlying Terraform module used by this component

- [Cloud Posse's upstream component](https://github.com/cloudposse/terraform-aws-components/tree/main/modules/guardduty/common/) - 

- [GuardDuty Organization Configuration Feature](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_organization_configuration_feature) - Terraform AWS provider documentation for organization-wide GuardDuty features




[<img src="https://cloudposse.com/logo-300x69.svg" height="32" align="right"/>](https://cpco.io/homepage?utm_source=github&utm_medium=readme&utm_campaign=cloudposse-terraform-components/aws-guardduty&utm_content=)

