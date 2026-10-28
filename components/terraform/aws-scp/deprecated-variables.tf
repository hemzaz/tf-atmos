# Deprecated variables - these will be removed in the next major release. Do not use these in new configurations.

variable "target_id" {
  type        = string
  description = "DEPRECATED: Use `target_ids` instead. The ID of the organization root, OU, or account to attach the SCP to."
  default     = null
}
