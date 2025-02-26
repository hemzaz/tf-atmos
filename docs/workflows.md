# Atmos Workflows: Orchestrating Multi-Account AWS Infrastructure

## Introduction

Workflows in our Atmos-managed infrastructure project are essential for automating complex, multi-step processes across our AWS accounts and environments. They provide a consistent, repeatable way to perform operations such as bootstrapping, planning, applying, and destroying infrastructure components.

## Key Workflows

### 1. Bootstrap Backend

**File:** `workflows/bootstrap-backend.yaml`

This workflow initializes the core infrastructure needed to manage Terraform state across all accounts and environments.

```yaml
name: bootstrap-backend
description: "Initialize the Terraform backend (S3 bucket and DynamoDB table)"

workflows:
  bootstrap:
    steps:
    - run:
        command: |
          aws s3api create-bucket --bucket ${bucket_name} --region ${region} --create-bucket-configuration LocationConstraint=${region}
          aws s3api put-bucket-versioning --bucket ${bucket_name} --versioning-configuration Status=Enabled
          aws dynamodb create-table --table-name ${dynamodb_table_name} --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST --region ${region}
        env:
          bucket_name: ${tenant}-terraform-state
          dynamodb_table_name: ${tenant}-terraform-locks
          region: ${region}
```

**Usage:**
```bash
atmos workflow bootstrap-backend tenant=mycompany region=us-west-2
```

### 2. Apply Backend

**File:** `workflows/apply-backend.yaml`

This workflow applies changes to the Terraform backend configuration.

```yaml
name: apply-backend
description: "Apply changes to the Terraform backend configuration"

workflows:
  apply:
    steps:
    - run:
        command: |
          atmos terraform init backend \
            -backend-config="bucket=${bucket_name}" \
            -backend-config="key=${state_file_key}" \
            -backend-config="region=${region}" \
            -backend-config="dynamodb_table=${dynamodb_table_name}" \
            -backend-config="role_arn=${iam_role_arn}" \
            -s ${tenant}-${account}-${environment}
          atmos terraform apply backend -s ${tenant}-${account}-${environment}
        env:
          bucket_name: ${tenant}-terraform-state
          dynamodb_table_name: ${tenant}-terraform-locks
          region: ${region}
          state_file_key: "${account}/${environment}/backend/terraform.tfstate"
          iam_role_arn: arn:aws:iam::${management_account_id}:role/${tenant}-terraform-backend-role
```

**Usage:**
```bash
atmos workflow apply-backend tenant=mycompany account=management environment=prod
```

### 3. Plan Environment

**File:** `workflows/plan-environment.yaml`

This workflow plans changes for all components in a specific environment.

```yaml
name: plan-environment
description: "Plan changes for all components in an environment"

workflows:
  plan:
    steps:
    - run:
        command: |
          echo "Planning backend..."
          atmos terraform plan backend -s ${tenant}-${account}-${environment}
          echo "Planning iam..."
          atmos terraform plan iam -s ${tenant}-${account}-${environment}
          echo "Planning network..."
          atmos terraform plan network -s ${tenant}-${account}-${environment}
          echo "Planning infrastructure..."
          atmos terraform plan infrastructure -s ${tenant}-${account}-${environment}
          echo "Planning services..."
          atmos terraform plan services -s ${tenant}-${account}-${environment}
```

**Usage:**
```bash
atmos workflow plan-environment tenant=mycompany account=dev environment=testenv-01
```

### 4. Apply Environment

**File:** `workflows/apply-environment.yaml`

Enhanced workflow to apply all components in an environment with proper error handling and validation.

```yaml
name: apply-environment
description: "Apply changes for all components in an environment with improved error handling"

workflows:
  apply:
    steps:
    - run:
        command: |
          # Validate required variables
          if [ -z "${tenant}" ] || [ -z "${account}" ] || [ -z "${environment}" ]; then
            echo "ERROR: Missing required parameters. Usage: atmos workflow apply-environment tenant=<tenant> account=<account> environment=<environment>"
            exit 1
          fi

          # Set exit on error
          set -e
          
          # Function to apply a component with error handling
          apply_component() {
            component=$1
            echo "Applying ${component}..."
            echo "----------------------------------------"
            if ! atmos terraform apply ${component} -s ${tenant}-${account}-${environment}; then
              echo "ERROR: Failed to apply ${component}. Exiting."
              return 1
            fi
            echo "Successfully applied ${component}."
            echo "----------------------------------------"
            return 0
          }
          
          # Apply components in dependency order
          echo "Starting deployment for ${tenant}-${account}-${environment}"
          echo "============================================"
          
          # Apply backend first
          apply_component "backend" || exit 1
          
          # Apply IAM next
          apply_component "iam" || exit 1
          
          # Apply network
          apply_component "network" || exit 1
          
          # Apply infrastructure components
          apply_component "infrastructure" || exit 1
          
          # Apply services last
          apply_component "services" || exit 1
          
          echo "============================================"
          echo "Deployment completed successfully for ${tenant}-${account}-${environment}"
          
          # Perform validation checks
          echo "Running post-deployment validation checks..."
          atmos workflow validate tenant=${tenant} account=${account} environment=${environment}
```

**Usage:**
```bash
atmos workflow apply-environment tenant=mycompany account=dev environment=testenv-01
```

### 5. Onboard Environment

**File:** `workflows/onboard-environment.yaml`

New workflow to streamline the creation of new environments by generating all required configurations and optionally deploying the infrastructure.

```yaml
name: onboard-environment
description: "Onboard a new environment by creating all necessary configurations and deploying infrastructure"

workflows:
  onboard:
    steps:
    - run:
        command: |
          # Validate required variables
          if [ -z "${tenant}" ] || [ -z "${account}" ] || [ -z "${environment}" ] || [ -z "${vpc_cidr}" ]; then
            echo "ERROR: Missing required parameters."
            echo "Usage: atmos workflow onboard-environment tenant=<tenant> account=<account> environment=<environment> vpc_cidr=<vpc_cidr> [region=<region>]"
            exit 1
          fi
          
          # Create configuration files
          ENV_DIR="stacks/account/${account}/${environment}"
          mkdir -p "${ENV_DIR}"
          
          # Generate backend, iam, network, infrastructure, and services configurations
          # ...
          
          # Ask for confirmation before deploying
          read -p "Do you want to deploy the environment now? (y/n): " CONFIRM
          if [[ ${CONFIRM} == "y" || ${CONFIRM} == "Y" ]]; then
            echo "Beginning deployment..."
            atmos workflow apply-environment tenant=${tenant} account=${account} environment=${environment}
          fi
```

**Usage:**
```bash
atmos workflow onboard-environment tenant=mycompany account=dev environment=testenv-02 vpc_cidr=10.2.0.0/16
```

### 6. Drift Detection

**File:** `workflows/drift-detection.yaml`

This workflow detects infrastructure drift by comparing the actual state with the desired state.

```yaml
name: drift-detection
description: "Detect infrastructure drift in an environment"

workflows:
  detect:
    steps:
    - run:
        command: |
          echo "Checking drift for backend..."
          atmos terraform plan backend -s ${tenant}-${account}-${environment} -detailed-exitcode
          echo "Checking drift for iam..."
          atmos terraform plan iam -s ${tenant}-${account}-${environment} -detailed-exitcode
          # ...
```

**Usage:**
```bash
atmos workflow drift-detection tenant=mycompany account=dev environment=testenv-01
```

## Workflow Design Principles

1. **Idempotency:** Workflows are designed to be idempotent, meaning they can be run multiple times without causing unintended side effects.

2. **Explicit Over Implicit:** We avoid loops and complex logic in workflows, preferring explicit steps for clarity and easier debugging.

3. **Environment Variability:** Workflows use environment variables to adapt to different accounts and environments.

4. **Fail Fast:** Each step in a workflow is designed to fail immediately if there's an error, preventing partial or inconsistent states.

5. **Logging and Visibility:** Workflows include echo statements to provide clear visibility into the progress of each step.

## Best Practices for Workflow Development

1. **Validation:** Always validate required parameters at the beginning of the workflow.

2. **Error Handling:** Implement proper error handling with informative error messages.

3. **Dependency Order:** Apply components in the correct dependency order (backend → IAM → network → infrastructure → services).

4. **Post-Deployment Validation:** Include validation steps after deployment to ensure everything is working as expected.

5. **Atomic Operations:** Design workflows to be atomic - they should either complete fully or not at all.

## Extending Workflows

To add a new workflow:

1. Create a new YAML file in the `workflows/` directory.
2. Define the workflow structure, including name, description, and steps.
3. Use existing environment variables or define new ones as needed.
4. Add the new workflow to the `imports` section of `atmos.yaml`.

Example structure:

```yaml
name: custom-workflow
description: "Description of your custom workflow"

workflows:
  main:
    steps:
    - run:
        command: |
          # Your workflow logic here
        env:
          # Environment variables
```

Then in `atmos.yaml`:

```yaml
workflows:
  imports:
    - custom-workflow.yaml
    # ... other workflows
```