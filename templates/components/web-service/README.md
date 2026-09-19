# web-service (component template)

Copy-in Terraform root module for a containerized web service on ECS Fargate:
Application Load Balancer (HTTPS with HTTP redirect when `certificate_arn` is
set), target group, ECS cluster and service, CPU/memory target-tracking
auto scaling, CloudWatch logs and least-privilege IAM roles.

Requirements: Terraform `>= 1.16.0, < 2.0.0`, AWS provider `~> 6.65`.

## Usage

```bash
cp -r templates/components/web-service components/terraform/web-service
```

```yaml
# stacks/orgs/fnx/dev/eu-west-2/<environment>.yaml
components:
  terraform:
    web-service/api:
      metadata: { component: web-service }
      vars:
        service_name: api
        container_image: 123456789012.dkr.ecr.eu-west-2.amazonaws.com/api@sha256:<digest>
        vpc_id: !terraform.state vpc/main .vpc_id
        certificate_arn: !terraform.state acm/main .certificate_arns.main_wildcard
      dependencies:
        components: [{ component: vpc/main }, { component: acm/main }]
```

`<tenant>-<environment>-<service_name>` must be at most 28 characters (ALB/target group names are
limited to 32). Secrets are passed as ARNs (`secret_environment_variables`). Auto scaling owns
`desired_count` after the first apply.
