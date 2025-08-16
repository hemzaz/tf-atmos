#!/usr/bin/env bash
# Add required variables to all catalog component files

REPO_ROOT="/Users/elad/IdeaProjects/tf-atmos"
CATALOG_DIR="$REPO_ROOT/stacks/catalog"

echo "Adding required variables to catalog components..."

# Find all catalog files
catalog_files=$(find "$CATALOG_DIR" -name "*.yaml")
file_count=$(echo "$catalog_files" | wc -l)

echo "Found $file_count catalog files"

# Process each file
modified_count=0
for file in $catalog_files; do
  filename=$(basename "$file")
  echo "Processing $filename..."
  
  # Check if file has vars section
  if grep -q "vars:" "$file"; then
    # File already has vars section
    tmp_file=$(mktemp)
    
    # Add missing variables
    awk '
      # If we find a vars section, add the required variables if missing
      /^ *vars:/ {
        print $0;
        vars_indent = length($0) - length($0 ~ s/^ *//);
        
        # Read the next several lines to check what variables already exist
        getline vars_content;
        vars_buffer = vars_content;
        
        for(i=0; i<10; i++) {
          if (getline nextline > 0) {
            vars_buffer = vars_buffer "\n" nextline;
          } else {
            break;
          }
        }
        
        # Check for tenant
        if (vars_buffer !~ /tenant:/) {
          printf("%*s%s\n", vars_indent, "", "  tenant: \"${tenant}\"");
        }
        
        # Check for account
        if (vars_buffer !~ /account:/) {
          printf("%*s%s\n", vars_indent, "", "  account: \"${account}\"");
        }
        
        # Check for environment
        if (vars_buffer !~ /environment:/) {
          printf("%*s%s\n", vars_indent, "", "  environment: \"${environment}\"");
        }
        
        # Print the buffered content
        print vars_buffer;
        next;
      }
      
      # For files without a vars section, add one at the end
      END {
        if (!found_vars) {
          print "vars:";
          print "  tenant: \"${tenant}\"";
          print "  account: \"${account}\"";
          print "  environment: \"${environment}\"";
        }
      }
      
      # Print all other lines unchanged
      { print $0; }
    ' "$file" > "$tmp_file"
    
    # Copy modified file back
    cp "$tmp_file" "$file"
    rm "$tmp_file"
    modified_count=$((modified_count + 1))
  else
    # Add vars section to end of file
    echo "" >> "$file"
    echo "vars:" >> "$file"
    echo "  tenant: \"\${tenant}\"" >> "$file"
    echo "  account: \"\${account}\"" >> "$file"
    echo "  environment: \"\${environment}\"" >> "$file"
    modified_count=$((modified_count + 1))
  fi
done

echo ""
echo "Summary: Modified $modified_count of $file_count files"