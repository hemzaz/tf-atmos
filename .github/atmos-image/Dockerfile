# Never built. This is the one reference Dependabot watches for the Atmos CI
# image (docker ecosystem, .github/dependabot.yml). Dependabot does not update
# a `container: image:` in a workflow file, so it bumps this FROM instead, and
# the actionlint job (terraform-ci.yml) fails until every workflow's atmos
# image matches it. Apply a Dependabot bump to the workflows with:
#   bash scripts/sync-atmos-image.sh
# and, running the new Atmos version, re-pin the manifest schema (lint step
# manifest-schema):
#   atmos stack schema schemas/atmos/atmos-manifest.json
FROM ghcr.io/cloudposse/atmos:1.233.2@sha256:ceceb1b38d24bc94adff144ed37202b55d0c0f09259322c8328fed1672a1247b
