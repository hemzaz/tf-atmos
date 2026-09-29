# Terraform module library

Shared modules that root components call with a relative source,
`source = "../_library/<category>/<module>"`.

- `security/kms-multi-region`: KMS key with alias, key policy, optional multi-region replicas
  and grants. Used by `kms`.

Add a module here only when a component uses it. Removed modules remain in git history
(master at 6fead3d).
