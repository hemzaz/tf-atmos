# Shaped like the remote-state module's outputs, so aws-guardduty's
# module.guardduty_delegated_detector[0].outputs.guardduty_detector_id reads
# work unchanged. Null when disabled.
output "outputs" {
  value = {
    guardduty_detector_id  = one(data.aws_guardduty_detector.this[*].id)
    guardduty_detector_arn = one(data.aws_guardduty_detector.this[*].arn)
  }
  description = "The detector's guardduty_detector_id and guardduty_detector_arn, as the step-1 instance outputs them."
}
