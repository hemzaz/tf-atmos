#!/usr/bin/env bash
#
# stack-name.sh - stack names from atmos.yaml name_template, for the scripts.
#
# A stack is {tenant}-{environment}-{stage}[-{name}] (Cloud Posse null-label
# order): environment is the region's Cloud Posse code (ue1 for us-east-1),
# name an optional lane (fnx-ue1-fixtures-batch). The code comes from the
# region mixin (stacks/mixins/region/<region>.yaml settings.context.environment)
# when it exists, else from Cloud Posse's short region table below; a region in
# neither is an error, never a guess.
#
# Usage (CLI):
#   scripts/stack-name.sh region-code <region>               # ue1
#   scripts/stack-name.sh stack <tenant> <region> <stage> [<name>]
# Or source it and call region_code / stack_name.

STACK_NAME_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Cloud Posse's terraform-aws-utils "short" codes for the regions a new mixin
# is most likely to need.
region_code_table() {
    case "$1" in
        us-east-1) echo ue1 ;;
        us-east-2) echo ue2 ;;
        us-west-1) echo uw1 ;;
        us-west-2) echo uw2 ;;
        ca-central-1) echo cc1 ;;
        eu-west-1) echo ew1 ;;
        eu-west-2) echo ew2 ;;
        eu-west-3) echo ew3 ;;
        eu-central-1) echo ec1 ;;
        eu-north-1) echo en1 ;;
        ap-northeast-1) echo an1 ;;
        ap-northeast-2) echo an2 ;;
        ap-southeast-1) echo as1 ;;
        ap-southeast-2) echo as2 ;;
        sa-east-1) echo se1 ;;
        *) return 1 ;;
    esac
}

# region_code <region>: the mixin's settings.context.environment, else the table.
region_code() {
    local region="$1" mixin code
    mixin="${STACK_NAME_REPO_ROOT}/stacks/mixins/region/${region}.yaml"
    if [[ -f "$mixin" ]]; then
        code="$(awk '/^settings:/{s=1;next} s&&/^  context:/{c=1;next} c&&/^    environment:/{print $2; exit} /^[^ #]/{s=0;c=0}' "$mixin")"
        if [[ -n "$code" ]]; then
            echo "$code"
            return 0
        fi
    fi
    if ! region_code_table "$region"; then
        echo "stack-name.sh: no Cloud Posse region code for '${region}': add stacks/mixins/region/${region}.yaml with settings.context.environment" >&2
        return 1
    fi
}

# stack_name <tenant> <region> <stage> [<name>]
stack_name() {
    local code
    code="$(region_code "$2")" || return 1
    echo "${1}-${code}-${3}${4:+-$4}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -euo pipefail
    if [[ "${1:-}" == region-code && $# -eq 2 ]]; then
        region_code "$2"
    elif [[ "${1:-}" == stack && $# -ge 4 && $# -le 5 ]]; then
        stack_name "${@:2}"
    else
        sed -n '/^# Usage/,/^# Or source/p' "$0" >&2
        exit 1
    fi
fi
