# The arguments aws-guardduty's remote-state.tf passes to its
# guardduty_delegated_detector module (Cloud Posse stack-config remote-state
# 1.8.1's names). An override can replace the module's source but not drop
# its arguments, so this module declares them; component, stage and privileged
# only name the step-1 instance in the failure message: nothing is read.
variable "component" {
  type        = string
  description = "The step-1 instance (aws-guardduty delegated_administrator_component_name); named in the failure message only."
}

variable "stage" {
  type        = string
  description = "The delegated administrator's stage; named in the failure message only."
}

variable "privileged" {
  type        = bool
  default     = false
  description = "Accepted for remote-state compatibility; the lookup uses the caller's provider, whatever this says."
}

variable "context" {
  type        = any
  description = "The caller's null-label context (module.this.context); only enabled is used."
}
