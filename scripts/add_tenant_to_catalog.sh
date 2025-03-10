#!/bin/bash
# Add tenant variable to all catalog component files

REPO_ROOT="/Users/elad/IdeaProjects/tf-atmos"
CATALOG_DIR="$REPO_ROOT/stacks/catalog"

echo "Adding tenant to catalog components..."

# Find all catalog files
catalog_files=$(find "$CATALOG_DIR" -name "*.yaml")
file_count=$(echo "$catalog_files" | wc -l)

echo "Found $file_count catalog files"

# Process each file
modified_count=0
for file in $catalog_files; do
  filename=$(basename "$file")
  echo -n "Processing $filename... "
  
  # Check if the file already has tenant defined
  if grep -q "tenant: " "$file"; then
    echo "already has tenant - skipping"
    continue
  fi
  
  # Add tenant to all terraform component vars sections
  components_count=$(grep -c "components:" "$file")
  terraform_count=$(grep -c "terraform:" "$file")
  vars_count=$(grep -c "vars:" "$file")
  
  if [ $vars_count -gt 0 ] && [ $terraform_count -gt 0 ]; then
    # Find all vars sections in terraform components
    tmp_file=$(mktemp)
    
    # Add tenant to each vars section
    awk '
      /^ *vars:/ && terraform_found {
        print $0;
        # Get indentation level
        match($0, /^ */);
        indent = RLENGTH;
        # Add tenant variable with same indentation plus two spaces
        print substr($0, 0, indent) "  tenant: \"${tenant}\"";
        next;
      }
      /^ *terraform:/ {
        terraform_found = 1;
      }
      # If we hit another major section, reset the terraform flag
      /^[a-z]/ {
        terraform_found = 0;
      }
      { print $0 }
    ' "$file" > "$tmp_file"
    
    # Check if we made changes
    if ! diff -q "$file" "$tmp_file" >/dev/null; then
      cp "$tmp_file" "$file"
      echo "tenant added"
      modified_count=$((modified_count + 1))
    else
      echo "no suitable vars section found"
    fi
    
    rm "$tmp_file"
  else
    echo "no terraform component vars found"
  fi
done

echo ""
echo "Summary: Modified $modified_count of $file_count files"