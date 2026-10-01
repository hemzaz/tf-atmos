# Never built. This is the one reference Dependabot watches for the Atmos CI
# image (docker ecosystem, .github/dependabot.yml). Dependabot does not update
# a `container: image:` in a workflow file, so it bumps this FROM instead, and
# the actionlint job (terraform-ci.yml) fails until every workflow's atmos
# image matches it. Apply a Dependabot bump to the workflows with:
#   bash scripts/sync-atmos-image.sh
FROM ghcr.io/cloudposse/atmos:1.229.0@sha256:9777fffcaf0ac3f0ef96ef584b9d7a4f8b9ac3640950149d525d30c9874a556d
