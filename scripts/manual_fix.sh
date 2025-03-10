#!/bin/bash
# Manually fix each catalog file

cd /Users/elad/IdeaProjects/tf-atmos

# Add required variables to each file one by one
for file in stacks/catalog/*.yaml; do
  echo "Adding vars to $(basename $file)..."
  
  # Check if the file has the import section (vpc.yaml)
  if grep -q "^import:" "$file"; then
    # Add vars section after import
    if ! grep -q "^vars:" "$file"; then
      # Create temporary file
      tmp_file=$(mktemp)
      awk '
        /^import:/ {
          print $0;
          in_import = 1;
          next;
        }
        in_import && /^$/ {
          print "";
          print "vars:";
          print "  tenant: \"${tenant}\"";
          print "  account: \"${account}\"";
          print "  environment: \"${environment}\"";
          in_import = 0;
          next;
        }
        {print $0}
      ' "$file" > "$tmp_file"
      cat "$tmp_file" > "$file"
      rm "$tmp_file"
    fi
  else
    # Just append vars to the end if not present
    if ! grep -q "^vars:" "$file"; then
      echo "" >> "$file"
      echo "vars:" >> "$file"
      echo "  tenant: \"\${tenant}\"" >> "$file"
      echo "  account: \"\${account}\"" >> "$file"
      echo "  environment: \"\${environment}\"" >> "$file"
    fi
  fi
done