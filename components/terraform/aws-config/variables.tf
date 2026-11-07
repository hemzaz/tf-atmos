variable "account_verification_enabled" {
  type        = bool
  description = <<-DOC
  Enable account verification. When true (default), the component verifies that Terraform is executing
  in the correct AWS account by comparing the current account ID against the expected account from the
  account_map based on the component's tenant-stage context.
  DOC
  default     = true
}

variable "account_map_enabled" {
  type        = bool
  description = <<-DOC
  Enable the account map component. When true, the component fetches account mappings from the
  `account-map` component via remote state. When false (default), the component uses the static `account_map` variable instead.
  DOC
  default     = false
}

variable "account_map" {
  type = object({
    full_account_map              = map(string)
    audit_account_account_name    = optional(string, "")
    root_account_account_name     = optional(string, "")
    identity_account_account_name = optional(string, "")
    aws_partition                 = optional(string, "aws")
    iam_role_arn_templates        = optional(map(string), {})
  })
  description = <<-DOC
  Static account map configuration. Only used when `account_map_enabled` is `false`.
  Map keys use `tenant-stage` format (e.g., `core-security`, `core-audit`, `plat-prod`).
  DOC
  default = {
    full_account_map              = {}
    audit_account_account_name    = ""
    root_account_account_name     = ""
    identity_account_account_name = ""
    aws_partition                 = "aws"
    iam_role_arn_templates        = {}
  }
}

variable "region" {
  type        = string
  description = "AWS Region"
}

variable "account_map_tenant" {
  type        = string
  default     = "core"
  description = "The tenant where the `account_map` component required by remote-state is deployed"
}

variable "root_account_stage" {
  type        = string
  default     = "root"
  description = "The stage name for the Organization root (master) account"
}

variable "global_environment" {
  type        = string
  default     = "gbl"
  description = "Global environment name"
}

variable "privileged" {
  type        = bool
  description = "True if the default provider already has access to the backend"
  default     = false
}

variable "config_bucket_stage" {
  type        = string
  description = "The stage of the AWS Config S3 Bucket"
}

variable "config_bucket_env" {
  type        = string
  description = "The environment of the AWS Config S3 Bucket"
}

variable "config_bucket_tenant" {
  type        = string
  default     = ""
  description = "(Optional) The tenant of the AWS Config S3 Bucket"
}

variable "global_resource_collector_region" {
  description = "The region that collects AWS Config data for global resources such as IAM"
  type        = string
}

variable "central_resource_collector_account" {
  description = "The name of the account that is the centralized aggregation account."
  type        = string
}

variable "create_iam_role" {
  description = "Flag to indicate whether an IAM Role should be created to grant the proper permissions for AWS Config"
  type        = bool
  default     = false
}

variable "az_abbreviation_type" {
  type        = string
  description = "AZ abbreviation type, `fixed` or `short`"
  default     = "fixed"
}

variable "iam_role_arn" {
  description = <<-DOC
    The ARN for an IAM Role AWS Config uses to make read or write requests to the delivery channel and to describe the
    AWS resources associated with the account. This is only used if create_iam_role is false.

    If you want to use an existing IAM Role, set the variable to the ARN of the existing role and set create_iam_role to `false`.

    See the AWS Docs for further information:
    http://docs.aws.amazon.com/config/latest/developerguide/iamrole-permissions.html
  DOC
  default     = null
  type        = string
}

variable "conformance_packs" {
  description = <<-DOC
    List of conformance packs. Each conformance pack is a map with the following keys: name, conformance_pack, parameter_overrides.

    For example:
    conformance_packs = [
      {
        name                  = "Operational-Best-Practices-for-CIS-AWS-v1.4-Level1"
        conformance_pack      = "https://raw.githubusercontent.com/awslabs/aws-config-rules/master/aws-config-conformance-packs/Operational-Best-Practices-for-CIS-AWS-v1.4-Level1.yaml"
        parameter_overrides   = {
          "AccessKeysRotatedParamMaxAccessKeyAge" = "45"
        }
      },
      {
        name                  = "Operational-Best-Practices-for-CIS-AWS-v1.4-Level2"
        conformance_pack      = "https://raw.githubusercontent.com/awslabs/aws-config-rules/master/aws-config-conformance-packs/Operational-Best-Practices-for-CIS-AWS-v1.4-Level2.yaml"
        parameter_overrides   = {
          "IamPasswordPolicyParamMaxPasswordAge" = "45"
        }
      }
    ]

    Complete list of AWS Conformance Packs managed by AWSLabs can be found here:
    https://github.com/awslabs/aws-config-rules/tree/master/aws-config-conformance-packs
  DOC
  type = list(object({
    name                = string
    conformance_pack    = string
    parameter_overrides = map(any)
    scope               = optional(string, null)
  }))
  default = []
  validation {
    # verify scope is valid
    condition     = alltrue([for conformance_pack in var.conformance_packs : conformance_pack.scope == null || conformance_pack.scope == "account" || conformance_pack.scope == "organization"])
    error_message = "The scope must be either `account` or `organization`."
  }
}

variable "delegated_accounts" {
  description = "The account IDs of other accounts that will send their AWS Configuration or Security Hub data to this account"
  type        = set(string)
  default     = null
}

variable "managed_rules" {
  description = <<-DOC
    A list of AWS Managed Rules that should be enabled on the account.

    See the following for a list of possible rules to enable:
    https://docs.aws.amazon.com/config/latest/developerguide/managed-rules-by-aws-config.html

    Example:
    ```
    managed_rules = {
      access-keys-rotated = {
        identifier  = "ACCESS_KEYS_ROTATED"
        description = "Checks whether the active access keys are rotated within the number of days specified in maxAccessKeyAge. The rule is NON_COMPLIANT if the access keys have not been rotated for more than maxAccessKeyAge number of days."
        input_parameters = {
          maxAccessKeyAge : "90"
        }
        enabled = true
        tags = {}
      }
    }
    ```
  DOC
  type = map(object({
    description      = string
    identifier       = string
    input_parameters = any
    tags             = map(string)
    enabled          = bool
  }))
  default = {}
}

variable "default_scope" {
  type        = string
  description = "The default scope of the conformance pack. Valid values are `account` and `organization`."
  default     = "account"
  validation {
    condition     = var.default_scope == "account" || var.default_scope == "organization"
    error_message = "The scope must be either `account` or `organization`."
  }
}

variable "account_map_component_name" {
  type        = string
  description = "The name of the account-map component"
  default     = "account-map"
}

variable "config_component_name" {
  type        = string
  description = "The name of the aws config component (i.e., this component)"
  default     = "aws-config"
}

variable "config_bucket_component_name" {
  type        = string
  description = "The name of the config-bucket component"
  default     = "config-bucket"
}

variable "global_collector_component_name_pattern" {
  type        = string
  description = <<-EOT
    A string formatting pattern used to construct or look up the name of the
    global AWS Config collector region component.

    This pattern should align with the regional naming convention of the
    aws-config component. For example, if the pattern is "%s-%s" and you pass
    ("aws-config", "use1"), the resulting component name will be "aws-config-use1".

    Adjust this pattern if your environment uses a different naming convention
    for regional AWS Config components.
  EOT
  default     = "%s-%s"
}

variable "recording_mode" {
  description = <<-DOC
    The mode for AWS Config to record configuration changes.

    recording_frequency:
      The default frequency with which AWS Config records configuration changes (CONTINUOUS or DAILY).
    recording_mode_override:
      Override the recording frequency for specific resource types.

    Use DAILY recording for high-churn or ephemeral resource types to reduce costs.
    Resources created and destroyed within a 24-hour period generate zero CIs under DAILY.

    See: https://docs.aws.amazon.com/config/latest/developerguide/select-resources-recording-frequency.html

    Example:
    ```
    recording_mode = {
      recording_frequency = "CONTINUOUS"
      recording_mode_override = {
        description         = "Record high-churn resource types daily instead of continuously"
        recording_frequency = "DAILY"
        resource_types      = ["AWS::EC2::Instance", "AWS::EC2::EC2Fleet", "AWS::EC2::LaunchTemplate"]
      }
    }
    ```
  DOC
  type = object({
    recording_frequency = string
    recording_mode_override = optional(object({
      description         = string
      recording_frequency = string
      resource_types      = list(string)
    }))
  })
  default = null
}

variable "sns_encryption_key_id" {
  type        = string
  description = <<-DOC
    The ID of an AWS-managed customer master key (CMK) for Amazon SNS or a custom CMK.

    Use "alias/aws/sns" for AWS managed key (recommended for compliance).
    Use a custom KMS key ARN or alias for organization-specific encryption requirements.

    IMPORTANT: This is required for CMMC compliance (cmmc-2-v2-sns-encrypted-kms rule).
    The SNS topic created by AWS Config must be encrypted with KMS.
  DOC
  default     = "alias/aws/sns"
}

variable "allowed_aws_services_for_sns_published" {
  type        = list(string)
  description = <<-DOC
    AWS service principals granted `sns:Publish` on the AWS Config SNS topic.
    Passed through to `cloudposse/config/aws`.

    Required when the configuration recorder runs on the AWS Config
    service-linked role (`create_iam_role = false` with no customer-managed role):
    the service-linked role has no `sns:Publish` permission, so AWS Config
    publishes as the `config.amazonaws.com` service principal, which the default
    topic policy does not allow. Set to `["config.amazonaws.com"]` in that case.
    See https://docs.aws.amazon.com/config/latest/developerguide/sns-topic-policy.html
  DOC
  default     = []
}

variable "allowed_iam_arns_for_sns_publish" {
  type        = list(string)
  description = <<-DOC
    IAM role/user ARNs granted `sns:Publish` on the AWS Config SNS topic.
    Passed through to `cloudposse/config/aws`.
  DOC
  default     = []
}
