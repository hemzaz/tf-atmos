# The delegated administrator's GuardDuty detector, looked up in the calling
# provider's account and region (E5c, owner decision OQ-W). aws-guardduty's
# remote-state_override.tf points its guardduty_delegated_detector module here
# instead of Cloud Posse's live remote-state read: CP's org-settings step runs
# in the delegated administrator account and region that step 1 created the
# detector in, so the detector is the account's only one in that region and a
# data source finds it without Atmos or another stack's state.
locals {
  # The caller passes its null-label context; a disabled component looks up nothing.
  enabled = var.context.enabled != false
}

data "aws_guardduty_detector" "this" {
  count = local.enabled ? 1 : 0

  lifecycle {
    postcondition {
      condition     = self.status == "ENABLED"
      error_message = "The GuardDuty detector ${self.id} is ${self.status}: step 1 (${var.component} in stage ${var.stage}, privileged = ${var.privileged}) must have enabled it before org-settings runs."
    }
  }
}
