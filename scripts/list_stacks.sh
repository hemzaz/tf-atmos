#!/usr/bin/env bash
# List all Atmos stacks with their naming context.
#
# Stack names come from atmos.yaml `name_template`
# ({tenant}-{stage}-{environment}, e.g. fnx-dev-testenv-01), so they can be
# passed straight to `atmos ... -s <stack>`. The naming context is read from
# settings.context / settings.environment, the region from vars.region.
#
# Usage: ./scripts/list_stacks.sh [--plain]
#   --plain   print only the stack names, one per line (for scripting)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

for tool in atmos jq; do
    if ! command -v "$tool" &> /dev/null; then
        echo -e "${YELLOW}⚠️  $tool not found. Install it first (see .atmos.env for versions).${NC}" >&2
        exit 1
    fi
done

if [ "${1:-}" = "--plain" ]; then
    atmos list stacks
    exit 0
fi

echo -e "${CYAN}Atmos Stack Listing${NC}"
echo -e "${BLUE}🔍 Discovering available stacks...${NC}"

# One row per stack: stack, tenant, stage, environment, account, region.
# Context is taken from the first non-abstract Terraform component of the stack.
STACK_ROWS=$(atmos describe stacks --process-functions=false --format json | jq -r '
  to_entries[]
  | .key as $stack
  | (.value.components.terraform // {} | to_entries
     | map(select(.value.metadata.type != "abstract")) | first | .value) as $c
  | [$stack,
     ($c.settings.context.tenant // "-"),
     ($c.settings.context.stage // "-"),
     ($c.settings.context.environment // "-"),
     ($c.settings.environment.account // "-"),
     ($c.vars.region // "-")]
  | @tsv')

if [ -z "$STACK_ROWS" ]; then
    echo -e "${YELLOW}⚠️  No stacks found. Check atmos.yaml and stacks/orgs/.${NC}" >&2
    exit 1
fi

echo -e "${GREEN}✅ Found $(echo "$STACK_ROWS" | wc -l | tr -d ' ') stack(s)${NC}"
echo

while IFS=$'\t' read -r stack tenant stage environment account region; do
    echo -e "  ${GREEN}•${NC} ${WHITE}$stack${NC}"
    echo -e "    ${BLUE}Tenant:${NC} $tenant  ${BLUE}Stage:${NC} $stage  ${BLUE}Environment:${NC} $environment  ${BLUE}Account:${NC} $account  ${BLUE}Region:${NC} $region"
    echo -e "    ${YELLOW}Manifest:${NC} stacks/orgs/$tenant/$stage/$region/$environment.yaml"
done <<< "$STACK_ROWS"
echo

FIRST_STACK=$(echo "$STACK_ROWS" | head -1 | cut -f1)
echo -e "${WHITE}Usage Examples:${NC}"
echo -e "  ${WHITE}make plan STACK=$FIRST_STACK${NC}"
echo -e "  ${WHITE}atmos list components -s $FIRST_STACK${NC}"
echo -e "  ${WHITE}atmos terraform plan vpc/main -s $FIRST_STACK${NC}"
echo -e "  ${WHITE}atmos workflow plan -f plan-environment -s $FIRST_STACK${NC}"
echo -e "  ${WHITE}atmos list workflows${NC}"
