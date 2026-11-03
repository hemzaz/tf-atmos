variable "region" {
  type        = string
  description = "AWS Region"
}

variable "account_assignments" {
  type = map(map(map(object({
    permission_sets = list(string)
    }
  ))))
  description = <<-EOT
    Enables access to permission sets for users and groups in accounts, in the following structure:

    ```yaml
    <account-name>:
      groups:
        <group-name>:
          permission_sets:
            - <permission-set-name>
      users:
        <user-name>:
          permission_sets:
            - <permission-set-name>
    ```

    EOT
  default     = {}
}

variable "groups" {
  type        = list(string)
  description = <<-EOT
    List of AWS Identity Center Groups to be created with the AWS API.

    When provisioning the Google Workspace Integration with AWS, Groups need to be created with API in order for automatic provisioning to work as intended.
    EOT
  default     = []
}

variable "session_duration" {
  type        = string
  description = "The default duration of the session in seconds for all permission sets. If not set, fallback to the default value in the module, which is 1 hour."
  default     = ""
}

variable "account_map_component_name" {
  type        = string
  description = "The name of the account-map component"
  default     = "account-map"
}

variable "idp_groups" {
  type        = list(string)
  description = <<-EOT
    List of IdP group names to look up and include in the group_ids output.
    These groups are managed by your Identity Provider (e.g., Google Workspace, Okta)
    and synced to AWS Identity Center. This allows referencing their IDs in other components.
    EOT
  default     = []
}
