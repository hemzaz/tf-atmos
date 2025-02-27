# Templates

This directory contains reusable templates for quickly implementing common patterns in your Atmos-managed infrastructure.

## Contents

### Component Templates

- `terraform-component/` - Base files for creating a new Terraform component
  - `main.tf` - Core resource definitions
  - `variables.tf` - Input variable definitions with validation
  - `outputs.tf` - Standard output format
  - `provider.tf` - Provider configuration with assume_role support

### Stack Templates

- `catalog-component.yaml` - Template for adding a new component to the catalog
- `environment-config.yaml` - Template for environment-specific component configuration

### Workflow Templates

- `custom-workflow.yaml` - Template for creating custom Atmos workflows
- `cicd-workflow.yaml` - Template for CI/CD pipeline integration

## Usage

### Creating a New Component

1. Copy the `terraform-component/` directory to your new component location:
   ```bash
   cp -r templates/terraform-component components/terraform/new-component-name
   ```

2. Update the files with your component-specific code.

3. Create a catalog entry using the catalog template:
   ```bash
   cp templates/catalog-component.yaml stacks/catalog/new-component-name.yaml
   ```

4. Customize the catalog entry for your component.

### Creating Environment Configuration

1. Copy the environment configuration template:
   ```bash
   cp templates/environment-config.yaml stacks/account/dev/my-environment/new-component-name.yaml
   ```

2. Update the configuration with environment-specific values.

### Creating Custom Workflows

1. Copy the workflow template:
   ```bash
   cp templates/custom-workflow.yaml workflows/my-custom-workflow.yaml
   ```

2. Customize the workflow steps according to your needs.

## Template Strategy

All templates follow these principles:

1. **Consistency** - Adhere to established code style guidelines in CLAUDE.md
2. **Best Practices** - Implement security, tagging, and error handling patterns
3. **Documentation** - Include comprehensive comments explaining usage
4. **Modularity** - Focus on reusability and clear separation of concerns
5. **Validation** - Include input validation to prevent errors