# Quick Deploy

The shortest path to a deployed stack. The [Deployment Guide](./DEPLOYMENT_GUIDE.md) has the
details, and its [manual prerequisites](./DEPLOYMENT_GUIDE.md#manual-prerequisites-before-first-apply)
must be done first: the stacks still contain placeholder account IDs, domains and alert addresses.

## 1. Check the tooling

```bash
atmos version        # >= 1.229.0; Atmos installs Terraform 1.16.3 itself
atmos list stacks
```

## 2. Validate (offline)

```bash
atmos validate stacks
atmos workflow validate-all -f validate-enhanced
```

## 3. Bootstrap and deploy

With AWS credentials for the target account:

```bash
STACK=fnx-dev-testenv-01

atmos workflow full -f bootstrap -s $STACK           # state bucket, IAM, VPCs
atmos workflow deploy -f deploy-full-stack -s $STACK # remaining layers, confirmed one by one
```

In `fnx-prod-production` the `kms` layer (right after `foundation`) deploys `kms/main`, whose key
EKS, EC2 and RDS use; in other stacks it has nothing to do and just asks to continue.

## 4. Verify

```bash
atmos workflow verify -f bootstrap -s $STACK
atmos terraform output vpc/main -s $STACK
atmos workflow drift-detection -f drift-detection -s $STACK   # expect no changes
```

## Deploying a stack template

`stacks/catalog/templates/` contains five templates: `web-application`, `microservices-platform`,
`serverless-api`, `data-pipeline` and `batch-processing`. A template's component instances are
named `<prefix>/<name>` (for example `serverless-api/cognito`), and a stack uses a template by
importing it:

```yaml
import:
  - catalog/templates/serverless-api
```

Fill in the template's required variables (see
[stacks/catalog/templates/README.md](../stacks/catalog/templates/README.md)), then:

```bash
atmos workflow deploy -f deploy-template -s <stack>              # choose a template, plan, confirm, deploy, verify
atmos workflow deploy-serverless -f deploy-template -s <stack>   # quick deploy, no confirmation step
atmos workflow deploy-parallel -f deploy-template -s <stack>     # independent components concurrently
```

The quick-deploy workflows are `deploy-web-app`, `deploy-microservices`, `deploy-serverless`,
`deploy-data-pipeline` and `deploy-batch`. None of the three existing stacks imports a template
today.
