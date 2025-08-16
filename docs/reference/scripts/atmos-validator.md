# Atmos Validator

A comprehensive validation tool for Atmos stacks that:
1. Validates YAML syntax for all catalog and environment files
2. Validates catalog structure and component definitions
3. Validates environment imports against the catalog
4. Validates component dependencies are satisfied
5. Runs atmos commands to verify stack configurations

## Requirements

- Python 3.6+
- PyYAML module: `pip install pyyaml`

## Installation

1. Install Python dependencies:
```bash
pip install pyyaml
```

2. Make the script executable:
```bash
chmod +x validate_atmos.py
```

## Usage

Run the validator from the repository root:

```bash
./scripts/validate_atmos.py
```

### Options

- `-r, --repo-root PATH`: Specify the repository root path (default: current directory)
- `-v, --verbose`: Enable verbose logging for more details about validation

### Examples

Run from the repository root with verbose logging:
```bash
./scripts/validate_atmos.py --verbose
```

Run from a different location, specifying the repository path:
```bash
cd /some/other/directory
/path/to/tf-atmos/scripts/validate_atmos.py --repo-root /path/to/tf-atmos
```

## Output Format

The script provides a detailed validation report:

```
================================================================================
                        ATMOS VALIDATION REPORT                         
================================================================================

✅ SUCCESSFUL VALIDATIONS:
  ✓ All 15 catalog YAML files are valid
  ✓ All 15 catalog components have valid structure
  ✓ Environment fnx/dev/testenv-01 imports valid catalog components
  ✓ All 4 dependency references are satisfied
  ✓ atmos validate stacks command succeeded
  ✓ Stack fnx-dev-testenv-01 validated successfully

⚠️ WARNINGS:
  ! Catalog component vpc has no terraform components

❌ ERRORS:
  ✗ Missing components required as dependencies: vpc

================================================================================
SUMMARY: FAILED
  Successful validations: 6
  Warnings: 1
  Errors: 1
================================================================================
```

## Exit Codes

- `0`: Validation passed with no errors
- `1`: Validation failed with errors

## Integration with CI/CD

This script can be integrated into CI/CD pipelines to validate Atmos stacks before deploying. 
For example, in a GitHub Actions workflow:

```yaml
steps:
  - name: Checkout repository
    uses: actions/checkout@v3

  - name: Set up Python
    uses: actions/setup-python@v4
    with:
      python-version: '3.10'

  - name: Install dependencies
    run: pip install pyyaml

  - name: Validate Atmos stacks
    run: ./scripts/validate_atmos.py --verbose
```

## Extending the validator

The script is designed to be extensible. To add additional validation steps, you can:

1. Add a new method to the `AtmosValidator` class
2. Call your method from the `validate()` method
3. Add appropriate error/warning/success messages

For example, to add a new validation step that checks for a specific pattern in YAML files:

```python
def validate_custom_pattern(self):
    """Validate custom patterns in YAML files"""
    self.log("Validating custom patterns...")
    
    for component_name, content in self.catalog_components.items():
        # Your custom validation logic
        if not meets_your_criteria(content):
            self.errors.append(f"Component {component_name} doesn't meet criteria")
```