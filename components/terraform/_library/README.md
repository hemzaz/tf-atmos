# Terraform module library

Shared modules that root components call with a relative source,
`source = "../_library/<category>/<module>"`.

- `security/kms-multi-region`: KMS key with alias, key policy, optional multi-region replicas
  and grants. Used by `kms`.
- `security/guardduty-delegated-detector`: the GuardDuty detector in the caller's account and
  region (data source). The vendored `aws-guardduty`'s `remote-state_override.tf` calls it in place
  of Cloud Posse's live remote-state read of the delegated administrator's detector.

Add a module here only when a component uses it. Removed modules remain in git history
(master at 6fead3d).
