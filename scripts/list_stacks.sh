#!/bin/bash
# Script to list all available Atmos stacks

# Set to the repository root directory
REPO_ROOT="/Users/elad/IdeaProjects/tf-atmos"
cd "$REPO_ROOT" || exit 1

echo "===================== ATMOS ENVIRONMENT LISTING ====================="
echo "Running: atmos list stacks"

# Run atmos list stacks but replace with friendly names
atmos list stacks | sed 's|orgs/fnx/dev/eu-west-2/testenv-01|fnx-testenv-01-dev|g'
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