---
tags:
  - component/aws-security-hub
  - layer/security-and-compliance
  - provider/aws
---

# Component: `security-hub`

This component is responsible for configuring Security Hub within an AWS Organization.

Amazon Security Hub enables users to centrally manage and monitor the security and compliance of their AWS accounts and
resources. It aggregates, organizes, and prioritizes security findings from various AWS services, third-party tools, and
integrated partner solutions.

## Key Features

- **Centralized Security Management**: Provides a centralized dashboard where users can view and manage security
  findings from multiple AWS accounts and regions, allowing for a unified view of the security posture across the
  entire AWS environment.

- **Automated Security Checks**: Automatically performs continuous security checks on AWS resources, configurations,
  and security best practices using industry standards and compliance frameworks such as AWS CIS Foundations Benchmark.

- **Product Subscriptions**: Integrates with AWS security services (GuardDuty, Inspector, Macie, Config, Access
  Analyzer, Firewall Manager) to automatically receive and aggregate findings in a single dashboard.

- **Security Standards and Compliance**: Provides compliance checks against industry standards and regulatory
  frameworks such as PCI DSS, HIPAA, NIST 800-53, and GDPR, with guidance on remediation actions.

- **Prioritized Security Findings**: Analyzes and prioritizes security findings based on severity, enabling users to
  focus on the most critical issues with efficient threat response and remediation.

- **Custom Insights and Event Aggregation**: Supports custom insights and rules to focus on specific security criteria,
  with event aggregation and correlation capabilities to identify related findings and attack patterns.

- **Alert Notifications and Automation**: Supports alert notifications through Amazon SNS and facilitates automation
  through integration with AWS Lambda for automated remediation actions.

- **Automation Rules**: Supports org-wide Security Hub automation rules for suppressing known false-positive control
  findings without disabling the control entirely.

- **GovCloud Support**: All product subscription ARNs use partition-aware format, automatically supporting both
  Commercial AWS and GovCloud partitions.

## Component Features

- **Delegated Administrator Model**: Uses AWS Organizations delegated administrator pattern for centralized management
- **Organizations Delegation Policy**: Automatically creates the 8-statement Organizations resource-based delegation
  policy required for Security Hub console access in the delegated administrator account
- **Multi-Region Deployment**: Supports deployment across all AWS regions with finding aggregation
- **Product Subscriptions**: Automatically creates subscriptions for AWS security service integrations
- **SNS Notifications**: Optional SNS topic creation for security finding alerts
- **Compliance Standards**: Configurable security standards (CIS, PCI DSS, AWS Foundational Security Best Practices)
- **Account Verification**: Optional safety check that validates Terraform is running in the correct AWS account
- **Flexible Account Map**: Supports both remote-state account-map lookups and static account map variables (default)
- **Finding Suppression via Automation Rules**: Configurable automation rules that suppress specific control findings
  org-wide from the delegated administrator account, without disabling controls or migrating to CENTRAL configuration mode
## Usage

**Stack Level**: Regional

## Deployment Overview

This component is complex in that it must be deployed multiple times with different variables set to configure the AWS
Organization successfully.

It is further complicated by the fact that you must deploy each of the component instances described below to every
region that existed before March 2019 and to any regions that have been opted-in as described in the
[AWS Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-regions-availability-zones.html#concepts-regions).

In the examples below, we assume that the AWS Organization Management account is `root` and the AWS Organization
Delegated Administrator account is `security`, both in the `core` tenant.

### Deploy to Delegated Administrator Account

First, the component is deployed to the
[Delegated Administrator](https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_organizations.html) account in each
region to configure the Security Hub instance to which each account will send its findings.

```yaml
# core-use1-security
components:
  terraform:
    aws-security-hub/delegated-administrator:
      metadata:
        component: aws-security-hub
      vars:
        enabled: true
        delegated_administrator_account_name: core-security
        # Product subscriptions for AWS security service integrations
        product_subscriptions:
          guardduty: true        # Enable GuardDuty findings
          inspector: true        # Enable Inspector findings
          macie: false           # Disabled by default - enable if using Macie
          config: true           # Enable Config findings
          access_analyzer: true  # Enable Access Analyzer findings
          firewall_manager: false # Disabled by default
```

```bash
atmos terraform apply aws-security-hub/delegated-administrator -s core-use1-security
atmos terraform apply aws-security-hub/delegated-administrator -s core-use2-security
atmos terraform apply aws-security-hub/delegated-administrator -s core-usw1-security
# ... other regions
```

### Deploy to Organization Management (root) Account

Next, the component is deployed to the AWS Organization Management (a/k/a `root`) Account in order to set the AWS
Organization Designated Administrator account. This step also creates the
[Organizations resource-based delegation policy](https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-v2-policy-statement.html)
that grants the delegated administrator permissions to manage Security Hub policies via Organizations APIs.

Note that `SuperAdmin` permissions must be used as we are deploying to the AWS Organization Management account. Since we
are using the `SuperAdmin` user, it will already have access to the state bucket, so we set the `role_arn` of the
backend config to null and set `var.privileged` to `true`.

```yaml
# core-use1-root
components:
  terraform:
    aws-security-hub/root:
      metadata:
        component: aws-security-hub
      vars:
        enabled: true
        delegated_administrator_account_name: core-security
        privileged: true
```

```bash
atmos terraform apply aws-security-hub/root -s core-use1-root
atmos terraform apply aws-security-hub/root -s core-use2-root
atmos terraform apply aws-security-hub/root -s core-usw1-root
# ... other regions
```

### Deploy Organization Settings in Delegated Administrator Account

Finally, the component is deployed to the Delegated Administrator Account again in order to create the organization-wide
Security Hub configuration for the AWS Organization, but with `var.admin_delegated` set to `true` this time to indicate
that the delegation from the Organization Management account has already been performed. This step uses LOCAL
configuration mode where each account manages its own configuration, and auto-enables Security Hub for all member
accounts.

```yaml
# core-use1-security
components:
  terraform:
    aws-security-hub/org-settings:
      metadata:
        component: aws-security-hub
      vars:
        enabled: true
        delegated_administrator_account_name: core-security
        admin_delegated: true
```

```bash
atmos terraform apply aws-security-hub/org-settings -s core-use1-security
atmos terraform apply aws-security-hub/org-settings -s core-use2-security
atmos terraform apply aws-security-hub/org-settings -s core-usw1-security
# ... other regions
```

## Product Subscriptions

Product subscriptions enable Security Hub to receive and aggregate findings from AWS security services. The component
supports automatic integration with:

| Product          | Default | Description                          |
|------------------|---------|--------------------------------------|
| GuardDuty        | `true`  | Threat detection findings            |
| Inspector        | `true`  | Vulnerability scanning findings      |
| Macie            | `false` | Sensitive data discovery findings    |
| Config           | `true`  | Configuration compliance findings    |
| Access Analyzer  | `true`  | External access findings             |
| Firewall Manager | `false` | Firewall policy compliance findings  |

Product subscriptions are only created during Step 1 (delegated administrator deployment) and use partition-aware ARN
format for GovCloud compatibility.

### Verification

After deployment, verify product subscriptions:

```bash
# Via Terraform output
atmos terraform output aws-security-hub/delegated-administrator -s core-use1-security

# Via AWS CLI
aws securityhub list-enabled-products-for-import --region us-east-1
```

## Delegation Policy

Step 2 (root account deployment) creates an
[Organizations resource-based delegation policy](https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-v2-policy-statement.html)
with 8 policy statements that grant the delegated administrator account permissions to manage Security Hub policies via
Organizations APIs. This policy is required even when using LOCAL configuration mode, because the Security Hub console
checks for it when displaying central configuration management options.

**Key details:**

- The policy uses **`organizations:*` actions** (not `securityhub:*`). Organizations resource policies only support
  `organizations:*` actions.
- AWS expects exactly **8 policy statements**, including `SecurityServicesDelegating*` statements with resource ARNs
  scoped to the organization ID.
- The policy includes resources for both `securityhub_policy` and `inspector_policy` types (shared delegation mechanism).
- `aws_organizations_resource_policy` is an **organization-wide singleton**. Only one can exist per organization. If
  other services need delegation policies, their statements must be combined into a single policy.
- Set `organizations_resource_policy_enabled = false` if the Organizations resource policy is managed by another
  component or service.

### Troubleshooting: "Missing Permissions to Manage Policies"

If the delegated administrator sees this error in the Security Hub console:

> You are missing permissions that are required to manage policies in Security Hub.

This means the Organizations resource-based delegation policy is missing or incomplete. Re-apply Step 2:

```bash
atmos terraform apply aws-security-hub/root -s core-use1-root
```

## Automation Rules (Suppress False-Positive Findings)

Security Hub automation rules let you mutate findings as they are ingested — for example, marking findings from a known
false-positive control as `SUPPRESSED` so they stop showing up in the active dashboard. Rules created in the delegated
administrator account apply org-wide and work in **LOCAL** configuration mode (no CENTRAL migration required).

This component exposes a `disabled_control_finding_reasons` variable that creates one
[`aws_securityhub_automation_rule`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_automation_rule)
per entry. Rules are only created during Step 3 (`org-settings` deployment, `admin_delegated = true`), so they live in
the delegated administrator account alongside `aws_securityhub_organization_configuration`.

### Example: Suppress Config.1 false positive

The CloudPosse `aws-config` module provisions a custom IAM role for the AWS Config recorder. Security Hub's `Config.1`
control then flags every account with reason code `CONFIG_RECORDER_CUSTOM_ROLE`, even though the custom role is a valid
deployment pattern.

```yaml
# core-use1-security
components:
  terraform:
    aws-security-hub/org-settings:
      vars:
        enabled: true
        admin_delegated: true
        disabled_control_finding_reasons:
          config-1-custom-role:
            control_id: "Config.1"
            reason_code: "CONFIG_RECORDER_CUSTOM_ROLE"
            disabled_reason: >-
              False positive: CloudPosse aws-config module uses a custom IAM role
              with equivalent permissions instead of AWSServiceRoleForConfig.
```

The resulting rule matches every `FAILED` / `ACTIVE` finding for the given `control_id` and sets workflow status to
`SUPPRESSED` with a note containing `disabled_reason`. New findings are suppressed immediately; existing findings are
re-evaluated by Security Hub (typically within 12–24 hours).

### Variable reference

| Field             | Required | Description                                                                                                                                                       |
|-------------------|----------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `control_id`      | yes      | Security Hub control ID (e.g., `Config.1`). The rule fires on every `FAILED`/`ACTIVE` finding for this control.                                                   |
| `reason_code`     | no       | Optional label appended to the rule name. **Documentation only** — Security Hub's automation rule API cannot filter on `Compliance.StatusReasons[].ReasonCode`.   |
| `disabled_reason` | yes      | Human-readable justification. Used as the rule description and as the note added to suppressed findings.                                                          |
| `rule_order`      | no       | Rule precedence (1–1000, lower runs first). Defaults to `1`. Only relevant when multiple rules could match the same finding (rules are terminal — first wins).    |

### Caveats

- **No reason-code filtering**: AWS does not expose `ReasonCode` as a criterion for automation rules, so the suppression
  applies to **all** `FAILED` findings for the configured `control_id`. If a control can fail for multiple distinct
  reasons and you want to suppress only one, you must either accept the broader suppression or migrate to CENTRAL
  configuration mode and use `aws_securityhub_configuration_policy` parameter overrides.
- **Singleton-aware**: Rules use `for_each`, so adding/removing entries does not affect other entries.
- **Rollback**: Removing an entry from the map deletes the rule on the next apply. Previously suppressed findings revert
  to their original workflow status on the next Security Hub evaluation cycle.

### Verification

```bash
# List automation rules in the delegated administrator account
aws securityhub list-automation-rules --region us-east-1

# Check that Config.1 findings are now suppressed
aws securityhub get-findings \
  --filters '{
    "ComplianceSecurityControlId": [{"Value": "Config.1", "Comparison": "EQUALS"}],
    "WorkflowStatus": [{"Value": "SUPPRESSED", "Comparison": "EQUALS"}]
  }' \
  --query 'length(Findings)'
```

## Account Map Configuration

The component supports two modes for resolving AWS account IDs:

### Static Mode (default)

When `account_map_enabled = false` (default), the component uses a static `account_map` variable instead of remote state. This is
useful when not using the `account-map` component or when account mappings are managed externally (e.g., by Atmos).

### Remote State Mode

When `account_map_enabled = true`, the component fetches account mappings from the `account-map` component
via Terraform remote state. This is the standard Cloud Posse reference architecture pattern.

```yaml
vars:
  account_map_enabled: false
  account_map:
    full_account_map:
      core-root: "111111111111"
      core-security: "222222222222"
      core-audit: "333333333333"
      plat-dev: "444444444444"
      plat-prod: "555555555555"
    root_account_account_name: "core-root"
```

When using static mode, provider authentication is handled externally (e.g., by Atmos identity resolution) rather than
through the `iam-roles` module.

## Account Verification

When `account_verification_enabled = true` (default), the component verifies that Terraform is executing in the correct
AWS account by comparing the current account ID against the expected account ID from the account map, based on the
component's `tenant-stage` context. This provides a safety check to catch misconfigurations before any resources are
created or modified.

To disable account verification:

```yaml
vars:
  account_verification_enabled: false
```

<!-- prettier-ignore-start -->
<!-- prettier-ignore-end -->


<!-- markdownlint-disable -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.4.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.33.0 |
| <a name="requirement_awsutils"></a> [awsutils](#requirement\_awsutils) | >= 0.16.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.33.0 |
| <a name="provider_awsutils"></a> [awsutils](#provider\_awsutils) | >= 0.16.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_account_map"></a> [account\_map](#module\_account\_map) | cloudposse/stack-config/yaml//modules/remote-state | 1.8.0 |
| <a name="module_security_hub"></a> [security\_hub](#module\_security\_hub) | cloudposse/security-hub/aws | 0.12.2 |
| <a name="module_this"></a> [this](#module\_this) | cloudposse/label/null | 0.25.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_organizations_resource_policy.security_hub](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_resource_policy) | resource |
| [aws_securityhub_account.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_account) | resource |
| [aws_securityhub_automation_rule.suppress_control_findings](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_automation_rule) | resource |
| [aws_securityhub_organization_admin_account.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_organization_admin_account) | resource |
| [aws_securityhub_organization_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_organization_configuration) | resource |
| [aws_securityhub_product_subscription.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_product_subscription) | resource |
| [awsutils_security_hub_organization_settings.this](https://registry.terraform.io/providers/cloudposse/awsutils/latest/docs/resources/security_hub_organization_settings) | resource |
| [terraform_data.account_verification](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [aws_caller_identity.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_organizations_organization.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/organizations_organization) | data source |
| [aws_partition.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_account_map"></a> [account\_map](#input\_account\_map) | Static account map configuration. Only used when `account_map_enabled` is `false`.<br/>Map keys use `tenant-stage` format (e.g., `core-security`, `core-audit`, `plat-prod`). | <pre>object({<br/>    full_account_map              = map(string)<br/>    audit_account_account_name    = optional(string, "")<br/>    root_account_account_name     = optional(string, "")<br/>    identity_account_account_name = optional(string, "")<br/>    aws_partition                 = optional(string, "aws")<br/>    iam_role_arn_templates        = optional(map(string), {})<br/>  })</pre> | <pre>{<br/>  "audit_account_account_name": "",<br/>  "aws_partition": "aws",<br/>  "full_account_map": {},<br/>  "iam_role_arn_templates": {},<br/>  "identity_account_account_name": "",<br/>  "root_account_account_name": ""<br/>}</pre> | no |
| <a name="input_account_map_component_name"></a> [account\_map\_component\_name](#input\_account\_map\_component\_name) | The name of the account-map component | `string` | `"account-map"` | no |
| <a name="input_account_map_enabled"></a> [account\_map\_enabled](#input\_account\_map\_enabled) | Enable the account map component. When true, the component fetches account mappings from the<br/>`account-map` component via remote state. When false (default), the component uses the static `account_map` variable instead. | `bool` | `false` | no |
| <a name="input_account_map_tenant"></a> [account\_map\_tenant](#input\_account\_map\_tenant) | The tenant where the `account_map` component required by remote-state is deployed | `string` | `"core"` | no |
| <a name="input_account_verification_enabled"></a> [account\_verification\_enabled](#input\_account\_verification\_enabled) | Enable account verification. When true (default), the component verifies that Terraform is executing<br/>in the correct AWS account by comparing the current account ID against the expected account from the<br/>account\_map based on the component's tenant-stage context. | `bool` | `true` | no |
| <a name="input_additional_tag_map"></a> [additional\_tag\_map](#input\_additional\_tag\_map) | Additional key-value pairs to add to each map in `tags_as_list_of_maps`. Not added to `tags` or `id`.<br/>This is for some rare cases where resources want additional configuration of tags<br/>and therefore take a list of maps with tag key, value, and additional configuration. | `map(string)` | `{}` | no |
| <a name="input_admin_delegated"></a> [admin\_delegated](#input\_admin\_delegated) | A flag to indicate if the AWS Organization-wide settings should be created. This can only be done after the Security<br/>  Hub Administrator account has already been delegated from the AWS Org Management account (usually 'root'). See the<br/>  Deployment section of the README for more information. | `bool` | `false` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Additional attributes (e.g. `workers` or `cluster`) to add to `id`,<br/>in the order they appear in the list. New attributes are appended to the<br/>end of the list. The elements of the list are joined by the `delimiter`<br/>and treated as a single ID element. | `list(string)` | `[]` | no |
| <a name="input_auto_enable_organization_members"></a> [auto\_enable\_organization\_members](#input\_auto\_enable\_organization\_members) | Flag to toggle auto-enablement of Security Hub for new member accounts in the organization.<br/><br/>For more information, see:<br/>https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_organization_configuration#auto_enable | `bool` | `true` | no |
| <a name="input_cloudwatch_event_rule_pattern_detail_type"></a> [cloudwatch\_event\_rule\_pattern\_detail\_type](#input\_cloudwatch\_event\_rule\_pattern\_detail\_type) | The detail-type pattern used to match events that will be sent to SNS.<br/><br/>For more information, see:<br/>https://docs.aws.amazon.com/AmazonCloudWatch/latest/events/CloudWatchEventsandEventPatterns.html<br/>https://docs.aws.amazon.com/eventbridge/latest/userguide/event-types.html | `string` | `"Security Hub Findings - Imported"` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object for setting entire context at once.<br/>See description of individual variables for details.<br/>Leave string and numeric variables as `null` to use default value.<br/>Individual variable settings (non-null) override settings in context object,<br/>except for attributes, tags, and additional\_tag\_map, which are merged. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_create_sns_topic"></a> [create\_sns\_topic](#input\_create\_sns\_topic) | Flag to indicate whether an SNS topic should be created for notifications. If you want to send findings to a new SNS<br/>topic, set this to true and provide a valid configuration for subscribers. | `bool` | `false` | no |
| <a name="input_default_standards_enabled"></a> [default\_standards\_enabled](#input\_default\_standards\_enabled) | Flag to indicate whether default standards should be enabled | `bool` | `true` | no |
| <a name="input_delegated_administrator_account_name"></a> [delegated\_administrator\_account\_name](#input\_delegated\_administrator\_account\_name) | The name of the account that is the AWS Organization Delegated Administrator account | `string` | `"core-security"` | no |
| <a name="input_delimiter"></a> [delimiter](#input\_delimiter) | Delimiter to be used between ID elements.<br/>Defaults to `-` (hyphen). Set to `""` to use no delimiter at all. | `string` | `null` | no |
| <a name="input_descriptor_formats"></a> [descriptor\_formats](#input\_descriptor\_formats) | Describe additional descriptors to be output in the `descriptors` output map.<br/>Map of maps. Keys are names of descriptors. Values are maps of the form<br/>`{<br/>  format = string<br/>  labels = list(string)<br/>}`<br/>(Type is `any` so the map values can later be enhanced to provide additional options.)<br/>`format` is a Terraform format string to be passed to the `format()` function.<br/>`labels` is a list of labels, in order, to pass to `format()` function.<br/>Label values will be normalized before being passed to `format()` so they will be<br/>identical to how they appear in `id`.<br/>Default is `{}` (`descriptors` output will be empty). | `any` | `{}` | no |
| <a name="input_disabled_control_finding_reasons"></a> [disabled\_control\_finding\_reasons](#input\_disabled\_control\_finding\_reasons) | A map of Security Hub automation rules to suppress specific control findings.<br/>Each entry creates an automation rule (in the delegated administrator account) that sets<br/>matching findings to `SUPPRESSED`.<br/><br/>- control\_id:      The Security Hub control ID (e.g., "Config.1"). This is the only field<br/>                   used for matching; the rule fires on every FAILED/ACTIVE finding for the<br/>                   given control.<br/>- reason\_code:     Optional label appended to the rule name (e.g., "CONFIG\_RECORDER\_CUSTOM\_ROLE").<br/>                   Documentation/traceability only — Security Hub's automation rule API does<br/>                   not support filtering on `Compliance.StatusReasons[].ReasonCode`, so the<br/>                   suppression applies to all FAILED findings for `control_id`, regardless of<br/>                   the underlying reason.<br/>- disabled\_reason: Human-readable justification for the suppression, stored as the rule<br/>                   description and as the note on suppressed findings.<br/>- rule\_order:      Optional rule precedence (1–1000, lower runs first). Defaults to 1. Only<br/>                   relevant when multiple rules could match the same finding; rules are<br/>                   terminal, so the first match wins.<br/><br/>Rules only deploy when running in the delegated administrator account with<br/>`admin_delegated = true` (i.e., the same gate as `aws_securityhub_organization_configuration`). | <pre>map(object({<br/>    control_id      = string<br/>    reason_code     = optional(string)<br/>    disabled_reason = string<br/>    rule_order      = optional(number, 1)<br/>  }))</pre> | `{}` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources | `bool` | `null` | no |
| <a name="input_enabled_standards"></a> [enabled\_standards](#input\_enabled\_standards) | A list of standards to enable in the account.<br/><br/>  For example:<br/>  - standards/aws-foundational-security-best-practices/v/1.0.0<br/>  - ruleset/cis-aws-foundations-benchmark/v/1.2.0<br/>  - standards/pci-dss/v/3.2.1<br/>  - standards/cis-aws-foundations-benchmark/v/1.4.0 | `set(string)` | `[]` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Usually used for region e.g. 'uw2', 'us-west-2', OR role 'prod', 'staging', 'dev', 'UAT' | `string` | `null` | no |
| <a name="input_finding_aggregation_region"></a> [finding\_aggregation\_region](#input\_finding\_aggregation\_region) | If finding aggregation is enabled, the region that collects findings | `string` | `"us-east-1"` | no |
| <a name="input_finding_aggregator_enabled"></a> [finding\_aggregator\_enabled](#input\_finding\_aggregator\_enabled) | Flag to indicate whether a finding aggregator should be created<br/><br/>If you want to aggregate findings from one region, set this to `true`.<br/><br/>For more information, see:<br/>https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/securityhub_finding_aggregator | `bool` | `true` | no |
| <a name="input_finding_aggregator_linking_mode"></a> [finding\_aggregator\_linking\_mode](#input\_finding\_aggregator\_linking\_mode) | Linking mode to use for the finding aggregator.<br/><br/>The possible values are:<br/>  - `ALL_REGIONS` - Aggregate from all regions<br/>  - `ALL_REGIONS_EXCEPT_SPECIFIED` - Aggregate from all regions except those specified in `var.finding_aggregator_regions`<br/>  - `SPECIFIED_REGIONS` - Aggregate from regions specified in `var.finding_aggregator_regions` | `string` | `"ALL_REGIONS"` | no |
| <a name="input_finding_aggregator_regions"></a> [finding\_aggregator\_regions](#input\_finding\_aggregator\_regions) | A list of regions to aggregate findings from.<br/><br/>This is only used if `finding_aggregator_enabled` is `true`. | `any` | `null` | no |
| <a name="input_findings_notification_arn"></a> [findings\_notification\_arn](#input\_findings\_notification\_arn) | The ARN for an SNS topic to send findings notifications to. This is only used if create\_sns\_topic is false.<br/>If you want to send findings to an existing SNS topic, set this to the ARN of the existing topic and set<br/>create\_sns\_topic to false. | `string` | `null` | no |
| <a name="input_global_environment"></a> [global\_environment](#input\_global\_environment) | Global environment name | `string` | `"gbl"` | no |
| <a name="input_id_length_limit"></a> [id\_length\_limit](#input\_id\_length\_limit) | Limit `id` to this many characters (minimum 6).<br/>Set to `0` for unlimited length.<br/>Set to `null` for keep the existing setting, which defaults to `0`.<br/>Does not affect `id_full`. | `number` | `null` | no |
| <a name="input_label_key_case"></a> [label\_key\_case](#input\_label\_key\_case) | Controls the letter case of the `tags` keys (label names) for tags generated by this module.<br/>Does not affect keys of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper`.<br/>Default value: `title`. | `string` | `null` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | The order in which the labels (ID elements) appear in the `id`.<br/>Defaults to ["namespace", "environment", "stage", "name", "attributes"].<br/>You can omit any of the 6 labels ("tenant" is the 6th), but at least one must be present. | `list(string)` | `null` | no |
| <a name="input_label_value_case"></a> [label\_value\_case](#input\_label\_value\_case) | Controls the letter case of ID elements (labels) as included in `id`,<br/>set as tag values, and output by this module individually.<br/>Does not affect values of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper` and `none` (no transformation).<br/>Set this to `title` and set `delimiter` to `""` to yield Pascal Case IDs.<br/>Default value: `lower`. | `string` | `null` | no |
| <a name="input_labels_as_tags"></a> [labels\_as\_tags](#input\_labels\_as\_tags) | Set of labels (ID elements) to include as tags in the `tags` output.<br/>Default is to include all labels.<br/>Tags with empty values will not be included in the `tags` output.<br/>Set to `[]` to suppress all generated tags.<br/>**Notes:**<br/>  The value of the `name` tag, if included, will be the `id`, not the `name`.<br/>  Unlike other `null-label` inputs, the initial setting of `labels_as_tags` cannot be<br/>  changed in later chained modules. Attempts to change it will be silently ignored. | `set(string)` | <pre>[<br/>  "default"<br/>]</pre> | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Usually the component or solution name, e.g. 'app' or 'jenkins'.<br/>This is the only ID element not also included as a `tag`.<br/>The "name" tag is set to the full `id` string. There is no tag with the value of the `name` input. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Usually an abbreviation of your organization name, e.g. 'eg' or 'cp', to help ensure generated IDs are globally unique | `string` | `null` | no |
| <a name="input_organization_management_account_name"></a> [organization\_management\_account\_name](#input\_organization\_management\_account\_name) | The name of the AWS Organization management account | `string` | `null` | no |
| <a name="input_organizations_resource_policy_enabled"></a> [organizations\_resource\_policy\_enabled](#input\_organizations\_resource\_policy\_enabled) | Enable creation of the Organizations resource-based delegation policy for Security Hub. When true (default),<br/>the component creates an `aws_organizations_resource_policy` in the management account (Step 2) that grants the<br/>delegated administrator permissions to manage Security Hub policies via Organizations APIs.<br/><br/>Set to `false` if the Organizations resource policy is managed elsewhere (e.g., by another component or service).<br/>Note: `aws_organizations_resource_policy` is an organization-wide singleton — only one can exist per organization.<br/>If other services (e.g., AWS Backup, Inspector) need delegation policies, their statements must be combined into<br/>a single policy managed by one component. | `bool` | `true` | no |
| <a name="input_privileged"></a> [privileged](#input\_privileged) | true if the default provider already has access to the backend | `bool` | `false` | no |
| <a name="input_product_subscriptions"></a> [product\_subscriptions](#input\_product\_subscriptions) | Map of AWS service product subscriptions to enable in Security Hub.<br/>Product subscriptions allow Security Hub to receive findings from AWS security services.<br/><br/>Default values:<br/>- guardduty: true (enable GuardDuty findings integration)<br/>- inspector: true (enable Inspector findings integration)<br/>- macie: false (disabled by default - enable if using Macie)<br/>- config: true (enable Config findings integration)<br/>- access\_analyzer: true (enable Access Analyzer findings integration)<br/>- firewall\_manager: false (disabled by default - enable if using Firewall Manager)<br/><br/>Note: Product subscriptions can be enabled even if the source service is not yet deployed.<br/>The subscription will simply wait for findings once the service is enabled.<br/><br/>For more information, see:<br/>https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-findings-providers.html | <pre>object({<br/>    guardduty        = optional(bool, true)<br/>    inspector        = optional(bool, true)<br/>    macie            = optional(bool, false)<br/>    config           = optional(bool, true)<br/>    access_analyzer  = optional(bool, true)<br/>    firewall_manager = optional(bool, false)<br/>  })</pre> | `{}` | no |
| <a name="input_regex_replace_chars"></a> [regex\_replace\_chars](#input\_regex\_replace\_chars) | Terraform regular expression (regex) string.<br/>Characters matching the regex will be removed from the ID elements.<br/>If not set, `"/[^a-zA-Z0-9-]/"` is used to remove all characters other than hyphens, letters and digits. | `string` | `null` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS Region | `string` | n/a | yes |
| <a name="input_root_account_stage"></a> [root\_account\_stage](#input\_root\_account\_stage) | The stage name for the Organization root (management) account. This is used to lookup account IDs from account names<br/>using the `account-map` component. | `string` | `"root"` | no |
| <a name="input_stage"></a> [stage](#input\_stage) | ID element. Usually used to indicate role, e.g. 'prod', 'staging', 'source', 'build', 'test', 'deploy', 'release' | `string` | `null` | no |
| <a name="input_subscribers"></a> [subscribers](#input\_subscribers) | A map of subscription configurations for SNS topics<br/><br/>For more information, see:<br/>https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription#argument-reference<br/><br/>protocol:<br/>  The protocol to use. The possible values for this are: sqs, sms, lambda, application. (http or https are partially<br/>  supported, see link) (email is an option but is unsupported in terraform, see link).<br/>endpoint:<br/>  The endpoint to send data to, the contents will vary with the protocol. (see link for more information)<br/>endpoint\_auto\_confirms:<br/>  Boolean indicating whether the end point is capable of auto confirming subscription e.g., PagerDuty. Default is<br/>  false.<br/>raw\_message\_delivery:<br/>  Boolean indicating whether or not to enable raw message delivery (the original message is directly passed, not<br/>  wrapped in JSON with the original message in the message property). Default is false. | <pre>map(object({<br/>    protocol               = string<br/>    endpoint               = string<br/>    endpoint_auto_confirms = bool<br/>    raw_message_delivery   = bool<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags (e.g. `{'BusinessUnit': 'XYZ'}`).<br/>Neither the tag keys nor the tag values will be modified by this module. | `map(string)` | `{}` | no |
| <a name="input_tenant"></a> [tenant](#input\_tenant) | ID element \_(Rarely used, not included by default)\_. A customer identifier, indicating who this instance of a resource is for | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_delegated_administrator_account_id"></a> [delegated\_administrator\_account\_id](#output\_delegated\_administrator\_account\_id) | The AWS Account ID of the AWS Organization delegated administrator account |
| <a name="output_product_subscriptions"></a> [product\_subscriptions](#output\_product\_subscriptions) | ARNs of Security Hub product subscriptions for AWS service integrations |
| <a name="output_sns_topic_name"></a> [sns\_topic\_name](#output\_sns\_topic\_name) | The name of the SNS topic created by the component |
| <a name="output_sns_topic_subscriptions"></a> [sns\_topic\_subscriptions](#output\_sns\_topic\_subscriptions) | The SNS topic subscriptions created by the component |
<!-- markdownlint-restore -->



## References


- [AWS Security Hub Documentation](https://docs.aws.amazon.com/securityhub/) - Official AWS documentation for Security Hub

- [Security Hub Organization Administration](https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-accounts-orgs.html) - Managing Security Hub across AWS Organizations

- [Security Hub Product Integrations](https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-findings-providers.html) - Integrating AWS services with Security Hub via product subscriptions

- [Security Hub Standards](https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-standards.html) - Security standards and compliance frameworks in Security Hub

- [Security Hub Finding Aggregation](https://docs.aws.amazon.com/securityhub/latest/userguide/finding-aggregation.html) - Cross-region finding aggregation configuration

- [CloudPosse Security Hub Terraform Module](https://github.com/cloudposse/terraform-aws-security-hub) - The underlying Terraform module used by this component

- [Cloud Posse's upstream component](https://github.com/cloudposse/terraform-aws-components/tree/main/modules/security-hub) - Original component in terraform-aws-components




[<img src="https://cloudposse.com/logo-300x69.svg" height="32" align="right"/>](https://cpco.io/homepage?utm_source=github&utm_medium=readme&utm_campaign=cloudposse-terraform-components/aws-security-hub&utm_content=)

