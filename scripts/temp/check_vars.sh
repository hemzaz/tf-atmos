#\!/bin/bash

CATALOG_DIR="/Users/elad/IdeaProjects/tf-atmos/stacks/catalog"
REQUIRED_VARS=("tenant" "account" "environment" "region")

echo "Checking catalog files for required variables..."
echo "================================================"

for file in "$CATALOG_DIR"/*.yaml; do
  filename=$(basename "$file")
  echo "Processing $filename..."
  
  # Check if vars section exists
  if \! grep -q "^vars:" "$file"; then
    echo "  MISSING: vars section not found in $filename"
  else
    # Check for each required variable
    for var in "${REQUIRED_VARS[@]}"; do
      if \! grep -q "^[[:space:]]*$var:" "$file" -A5 | grep -q "vars:"; then
        echo "  MISSING: $var variable not found in $filename"
      fi
    done
  fi
done

echo "================================================"
echo "Checking tenant files in dev/testenv-01..."
echo "================================================"

TENANT_DIR="/Users/elad/IdeaProjects/tf-atmos/stacks/account/dev/testenv-01"
for file in "$TENANT_DIR"/*.yaml; do
  filename=$(basename "$file")
  if [ "$filename" \!= "variables.yaml" ] && [ "$filename" \!= "main.yaml" ]; then
    echo "Processing $filename..."
    
    # Check if the file references the main.yaml variables
    if \! grep -q "import:" "$file" | grep -q "main.yaml"; then
      # Check if vars section exists with correct values
      if grep -q "^vars:" "$file"; then
        for var in "${REQUIRED_VARS[@]}"; do
          if \! grep -q "$var:" "$file" -A20 | grep -q "vars:"; then
            echo "  MISSING: $var variable not found in $filename"
          fi
        done
        
        # Check specific values
        if \! grep -q "account:[[:space:]]*dev" "$file"; then
          echo "  INCORRECT: account should be 'dev' in $filename"
        fi
        
        if \! grep -q "environment:[[:space:]]*fnx" "$file"; then
          echo "  INCORRECT: environment should be 'fnx' in $filename"
        fi
        
        if \! grep -q "tenant:[[:space:]]*testenv-01" "$file"; then
          echo "  INCORRECT: tenant should be 'testenv-01' in $filename"
        fi
        
        if \! grep -q "region:[[:space:]]*eu-west-2" "$file"; then
          echo "  INCORRECT: region should be 'eu-west-2' in $filename"
        fi
      else
        echo "  MISSING: vars section not found in $filename"
      fi
    else
      echo "  OK: File imports main.yaml which contains variables"
    fi
  fi
done
