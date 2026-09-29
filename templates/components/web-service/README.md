# web-service (component template)

Copy-in root module for a container service on ECS Fargate behind an ALB (HTTPS with an HTTP
redirect when `certificate_arn` is set), with target-tracking auto scaling, logs and IAM roles.

```bash
cp -r templates/components/web-service components/terraform/web-service
```

```yaml
# in a stack's components/services.yaml
components:
  terraform:
    web-service/api:
      metadata: { component: web-service }
      vars:
        tenant: "{{ .settings.context.tenant }}"
        environment: "{{ .settings.context.environment }}"
        service_name: api
        container_image: 123456789012.dkr.ecr.eu-west-2.amazonaws.com/api@sha256:<digest>
        vpc_id: !terraform.state vpc/main .vpc_id
        private_subnet_ids: !terraform.state vpc/main .private_subnet_ids
        public_subnet_ids: !terraform.state vpc/main .public_subnet_ids
        certificate_arn: !terraform.state acm/main .certificate_arns.main_wildcard
      dependencies:
        components: [{ component: vpc/main }, { component: acm/main }]
```

Then add `web-service` to a layer after `certificates` in `workflows/deploy-full-stack.yaml`.
`<tenant>-<environment>-<service_name>` must be at most 28 characters. Pass secrets as ARNs in
`secret_environment_variables`. Auto scaling owns `desired_count` after the first apply.
