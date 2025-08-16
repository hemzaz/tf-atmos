#!/usr/bin/env bash
# Wrapper script for atmos to provide friendly stack names

# Helpful aliases that could be added to .zshrc or .bashrc:
# alias atmos-ls="./scripts/list_stacks.sh"
# alias atmos-plan="./scripts/atmos_wrapper.sh plan"
# alias atmos-apply="./scripts/atmos_wrapper.sh apply"

REPO_ROOT="/Users/elad/IdeaProjects/tf-atmos"
cd "$REPO_ROOT" || exit 1

# Map from friendly name to actual stack path
map_stack_name() {
  local friendly_name=$1
  
  if [[ $friendly_name == "fnx-testenv-01-dev" ]]; then
    echo "orgs/fnx/dev/eu-west-2/testenv-01"
  else
    echo "$friendly_name"
  fi
}

# Map from actual stack path to friendly name for display
friendly_stack_name() {
  local actual_name=$1
  
  if [[ $actual_name == "orgs/fnx/dev/eu-west-2/testenv-01" ]]; then
    echo "fnx-testenv-01-dev"
  else
    echo "$actual_name"
  fi
}

# Command is the first argument
COMMAND=$1
shift

# Check for stack name in arguments
STACK_ARG=""
STACK_POS=""
COMPONENT=""
for i in $(seq 1 $#); do
  arg=${!i}
  next_i=$((i+1))
  next_arg=${!next_i}
  
  if [[ $arg == "-s" || $arg == "--stack" ]] && [[ -n $next_arg ]]; then
    STACK_ARG=$next_arg
    STACK_POS=$next_i
  fi
  
  if [[ $i -eq 1 && $COMMAND == "terraform" ]]; then
    COMPONENT=$arg
  fi
done

# If we found a friendly stack name, map it back to the real path
if [[ -n $STACK_ARG ]]; then
  REAL_STACK=$(map_stack_name "$STACK_ARG")
  
  # Replace the stack name in the arguments
  if [[ -n $STACK_POS ]]; then
    eval "set -- \"\${@:1:$((STACK_POS-1))}\" \"$REAL_STACK\" \"\${@:$((STACK_POS+1))}\""
  fi
  
  # Print what we're doing with the friendly name
  if [[ -n $COMPONENT && $COMMAND == "terraform" ]]; then
    FRIENDLY=$(friendly_stack_name "$REAL_STACK")
    echo "Running $COMMAND $COMPONENT for stack: $FRIENDLY"
  fi
fi

# Run the actual atmos command
atmos "$COMMAND" "$@"