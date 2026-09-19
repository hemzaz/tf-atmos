# Terraform module library

Shared modules that root components call with a relative source,
`source = "../_library/<category>/<module>"`.

| Module | Purpose | Used by |
|---|---|---|
| `security/kms-multi-region` | KMS key with alias, key policy, optional multi-region replicas and grants | `kms` |

Add a module here only when a component uses it. The unused modules were removed;
they remain in git history (master at 6fead3d) if one is needed again.
