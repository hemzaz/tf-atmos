# House override of the vendored Cloud Posse aws-iam-role (vendor.yaml)
# github-assume-role-policy.tf: the GitHub `pull_request` OIDC subject (gap G2,
# owner decision OQ2 i, E6a4).
#
# Upstream turns a trusted_github_repos entry "<org>/<repo>:<constraint>" into
# a sub claim: no constraint -> repo:<org>/<repo>:* (a wildcard), "ref:..." or
# "environment:..." -> repo:<org>/<repo>:<constraint>, anything else is a
# branch -> repo:<org>/<repo>:ref:refs/heads/<constraint>. A pull_request
# workflow's token has sub repo:<org>/<repo>:pull_request, which no entry can
# produce ("<org>/<repo>:pull_request" becomes ref:refs/heads/pull_request),
# so the CI plan role (stacks/catalog/aws-iam-role/ci.yaml) could not trust
# pull-request plans without the wildcard the repository bans.
#
# This override adds exactly one mapping, "pull_request" ->
# repo:<org>/<repo>:pull_request, and keeps every other branch of upstream's
# expression as it is (a constraint-less entry still yields upstream's
# wildcard: check-prod-protection.py fails such an entry in lint, the
# override never widens). distinct() keeps a subject once when two entries
# resolve to it (the catalog's prod plan role, whose pull_request entry
# collapses onto master). Upstream's StringLike test stays: the catalog's
# subjects carry no * or ?, so it matches them exactly.
#
# Terraform merges a locals override value by value and fails on a local the
# base does not define, so a vendor bump that renames github_repos_sub fails
# `terraform validate` instead of silently dropping the subject.
# tests/ci_roles.tftest.hcl pins the resulting trust policy.

locals {
  github_repos_sub = distinct([
    for r in local.trusted_github_repos_sub : (
      r["constraint"] == "" ?
      format("repo:%s/%s:*", coalesce(r["org"], var.trusted_github_org), r["repo"]) :
      r["constraint"] == "pull_request" ?
      format("repo:%s/%s:pull_request", coalesce(r["org"], var.trusted_github_org), r["repo"]) :
      startswith(r["constraint"], "ref:") || startswith(r["constraint"], "environment:") ?
      format("repo:%s/%s:%s", coalesce(r["org"], var.trusted_github_org), r["repo"], r["constraint"]) :
      format("repo:%s/%s:ref:refs/heads/%s", coalesce(r["org"], var.trusted_github_org), r["repo"], r["constraint"])
    )
  ])
}
