# awsconfig

The AWS Config recorder for one account and region: a recorder of every resource type (global
types included), its IAM role (`AWS_ConfigRole` plus an inline bucket/key policy), and a delivery
channel to an SSE-KMS bucket. Modelled on Cloud Posse `aws-config` with `aws-config-bucket` folded
in, since every stack is its own account.

## Wiring

- Instance: `awsconfig/main` in every AWS stack; reads `kms/main .key_arn`. Global types are
  recorded by one stack per account (`fnx-ue2-prod` sets `include_global_resource_types: false`;
  `fnx-ew1-prod` records them for `prod-eu`).
- Used by: `securityhub` (dependency, ordering only). `harden.sh` deploys it.

## Notes

- AWS allows one recorder per account and region, and global types must be recorded in exactly
  one region. If two stacks ever share an account, keep the recorder in only one. An existing
  recorder created outside Terraform must be imported or deleted first.
- No `kms/main` key-policy flag is needed: the recorder's role gets key use through IAM.
- Config bills per recorded item; `recording_frequency: DAILY` lowers the cost of noisy types.
