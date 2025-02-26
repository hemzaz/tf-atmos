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

## Workflow Design Principles

1. **Idempotency:** Workflows are designed to be idempotent, meaning they can be run multiple times without causing unintended side effects.

2. **Explicit Over Implicit:** We avoid loops and complex logic in workflows, preferring explicit steps for clarity and easier debugging.

3. **Environment Variability:** Workflows use environment variables to adapt to different accounts and environments.

4. **Fail Fast:** Each step in a workflow is designed to fail immediately if there's an error, preventing partial or inconsistent states.

5. **Logging and Visibility:** Workflows include echo statements to provide clear visibility into the progress of each step.

## Best Practices for Workflow Development

1. **Naming Convention:** Use clear, descriptive names for workflows and their steps.

2. **Documentation:** Include a description for each workflow and comment complex commands.

3. **Error Handling:** Implement appropriate error handling and provide meaningful error messages.

4. **Parameterization:** Use environment variables to make workflows flexible and reusable across different contexts.

5. **Atomicity:** Design workflows to be atomic - they should either complete fully or not at all.

6. **Testing:** Regularly test workflows in a safe environment to ensure they behave as expected.

## Extending Workflows

To add a new workflow:

1. Create a new YAML file in the `workflows/` directory.
2. Define the workflow structure, including name, description, and steps.
3. Use existing environment variables or define new ones as needed.
4. Add the new workflow to the `imports` section of `atmos.yaml`.

Example of adding a new workflow for security scanning:

```yaml
# workflows/security-scan.yaml
name: security-scan
description: "Run security scans on infrastructure"

workflows:
  scan:
    steps:
    - run:
        command: |
          echo "Running security scan for ${tenant}-${account}-${environment}"
          # Add your security scanning logic here
```

Then in `atmos.yaml`:

```yaml
workflows:
  imports:
    - security-scan.yaml
    # ... other workflows
```