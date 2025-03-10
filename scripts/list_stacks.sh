#!/bin/bash
# Script to list all available Atmos stacks

# Set to the repository root directory
REPO_ROOT="/Users/elad/IdeaProjects/tf-atmos"
cd "$REPO_ROOT" || exit 1

echo "===================== ATMOS ENVIRONMENT LISTING ====================="
echo "Running: atmos list stacks"

# Get the raw stack listing
STACKS=$(atmos list stacks)

# Format stack names to be user-friendly
for stack in $STACKS; do
  # Map stack paths to user-friendly names
  if [[ $stack == "orgs/fnx/dev/eu-west-2/testenv-01" ]]; then
    echo "fnx-testenv-01-dev"
  else
    echo $stack
  fi
done
echo ""

echo "===================== DIRECTORY STRUCTURE ========================="
echo "Mapped structure:"
echo "account (dev)"
echo "└── dev"
echo "    └── testenv-01 (tenant)"
echo ""

echo "Expected stack name: testenv-01-dev-prod"
echo ""

echo "===================== SHOW SPECIFIC STACK DETAILS ================="
STACK_NAME=$(atmos list stacks | grep -v "^$" | head -1)
if [ -n "$STACK_NAME" ]; then
  # Get the user-friendly name
  if [[ $STACK_NAME == "orgs/fnx/dev/eu-west-2/testenv-01" ]]; then
    DISPLAY_NAME="fnx-testenv-01-dev"
  else
    DISPLAY_NAME=$STACK_NAME
  fi
  
  echo "Showing details for stack: $DISPLAY_NAME"
  atmos describe stacks -s "$STACK_NAME"
else
  echo "No stacks found!"
fi

echo ""
echo "===================== RUN COMMANDS WITH STACKS ====================="
echo "To run commands, use the real stack name with atmos, but display the friendly name:"
echo ""
echo "$ atmos terraform plan vpc -s orgs/fnx/dev/eu-west-2/testenv-01"
echo "Planning vpc for stack: fnx-testenv-01-dev"