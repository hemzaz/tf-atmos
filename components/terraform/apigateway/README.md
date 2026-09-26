# apigateway

Creates either a REST API (`aws_api_gateway_rest_api` + stage + deployment) or an HTTP API
(`aws_apigatewayv2_api` + stage), chosen by `var.api_type`. Optional: custom domain + Route53 alias,
access logging, usage plan + API key, Cognito/Lambda/JWT authorizers, a WAFv2 web ACL (rate-limit +
geo-block + AWS managed rules), caching/throttling, a dashboard, and 4xx/5xx/latency alarms.

Real instances `apigateway/main` and `apigateway/data` in all 3 stacks; the catalog's
`apigateway_domain`/`apigateway_http`/`apigateway_rest` entries are abstract.
`stacks/catalog/templates/serverless-api.yaml`'s `serverless-api/apigateway` sets
`domain_name`/`certificate_arn`/`base_path`/`zone_id` directly on this component too,
the same way `apigateway/main` does in the 3 real stacks: no separate domain component
(mirrors `cloudposse-terraform-components/aws-api-gateway-rest-api`, which configures
its custom domain the same way).

## Inputs / Outputs

| Input | Notes |
|---|---|
| `api_type` | `REST` or `HTTP`, picks which resource set is created |
| `api_resources` | one `path_part` each; the resource is then addressed as `/<path_part>` |
| `api_methods` | addressed by `resource_path` (`/` is the API root), never by resource id |
| `api_integrations` | exactly one per method, same `resource_path` + `http_method`; `uri` required unless `type` is `MOCK` |
| `domain_name`, `certificate_arn` | both required together for the custom domain |
| `base_path` | default `null` (root mapping, same as `""`); the mapping is the custom domain's only path when unset |
| `zone_id` | required for the Route53 alias record |
| `enable_waf` / `tracing_enabled` | both default false; prod opts in per instance. X-Ray bills per trace, so dev/staging stay off |
| `waf_common_rule_set_action`, `waf_known_bad_inputs_action` | `block` (default) or `count`, one per AWS managed rule group, so either can be soaked without relaxing the other |
| `cors_configuration` (null) | HTTP APIs only. It used to be silently ignored (the code looked up an `enabled` key the object type does not have), so no HTTP API got CORS; it is now applied whenever set. Validated: `allow_credentials = true` with `"*"` in `allow_origins` is refused, and `max_age` must be 0-86400. REST APIs ignore it silently (live staging and prod `apigateway/main` set it on REST); rejecting that is a known gap left open so those instances keep planning |
| `throttling_rate_limit`, `throttling_burst_limit` | REST: per-method settings (with caching). HTTP: the stage's `default_route_settings` |
| `vpc_link_subnet_ids`, `vpc_link_security_group_ids` | HTTP APIs: a VPC link `<Environment>-<api_name>-vpc-link` for private integrations; the security groups are required with the subnets. Outputs `http_api_vpc_link_id` and `http_api_vpc_link_arn`; its Name tag is `<prefix>-vpc-link` |
| `http_routes` ({}) | HTTP APIs only (a REST API ignores it silently, like `cors_configuration`); keyed by `route_key` (e.g. `"ANY /{proxy+}"`). One `aws_apigatewayv2_integration` + `aws_apigatewayv2_route` per entry. `integration_type` is `HTTP_PROXY` (typically `connection_type = "VPC_LINK"`, `connection_id` = the VPC link's id, `integration_uri` = the target listener's ARN — usually the `alb-controller-ingress-group` component's `http_listener_arn`/`https_listener_arn` output) or `AWS_PROXY` (`integration_uri` = a Lambda's `invoke_arn`; `lambda_function_name` is required so this component can grant it `apigateway.amazonaws.com` invoke permission, the same reasoning as `api_integrations`' `AWS_PROXY` requirement). `authorization_type` is `JWT` (uses this component's own JWT authorizer — validated: requires `authorizer_type = "JWT"` on this component, there is no per-route authorizer override) or `NONE`. `tls_server_name_to_verify` (null) adds a `tls_config` block to the integration, enabling TLS on the private hop — only valid on an `HTTP_PROXY` + `connection_type = "VPC_LINK"` route into an HTTPS listener (`https_listener_arn`); left null the hop is plaintext HTTP_PROXY (`http_listener_arn`). Output `http_route_ids` maps `route_key` to the created route's id |

## Dependencies / gotchas

- `apigateway/main` depends on `acm/main`, `network/main`; `apigateway/data` depends on
  `acm/services`, `network/services`.
- Custom-domain resources are silently skipped if only one of `domain_name` /
  `certificate_arn` is set; `zone_id` must be non-null or the alias record is skipped too.
- The REST custom domain always uses `regional_certificate_arn` and `security_policy =
  "TLS_1_2"`, so it requires `endpoint_type = ["REGIONAL"]`; a `lifecycle.precondition`
  blocks `EDGE`/`PRIVATE` + a domain at plan time (EDGE needs a us-east-1
  `certificate_arn`, not `regional_certificate_arn`, and PRIVATE has no regional custom
  domain). Both real instances (`apigateway/main`, `apigateway/data`) use the REGIONAL
  default, so this never applies to them.
- `api_resources` hangs every resource off the API root, so declarable paths are one level deep. An
  entry with an explicit external `parent_id` is still keyed `/<path_part>`, not its real URL.
- The deployment redeploys whenever `api_resources`/`api_methods`/`api_integrations` change. The
  first apply after this trigger was added replaces the deployment once, `create_before_destroy`.
- `monitoring/main` and `monitoring/data` read `api_name` and `rest_api_stage_name` via
  `!terraform.state` in all 3 stacks (`api_gateway_name`/`api_gateway_stages`), for the
  ApiName/Stage dashboard dimensions and alarms. `api_name` is `null` for an HTTP API
  (`aws_api_gateway_rest_api.rest_api[0].name`, the real REST API name — not `var.api_name`,
  which is only its `-<api_name>` suffix).
- **`microservices-platform`'s `http_routes` hop is TLS, not plaintext.** It targets
  `alb-controller-ingress-group`'s `https_listener_arn`, not `http_listener_arn`:
  `microservices/alb-ingress-group` carries `certificate_arn` from a `microservices/acm`
  instance (DNS-validated through `settings.microservices.hosted_zone_id`, the account's public
  delegated zone -- validation only needs a public DNS record, not a reachable endpoint, so the
  internal-scheme ALB still carries a publicly-issued certificate), and the route's
  `tls_server_name_to_verify` names that same certificate's domain.

## Tests

`tests/http_api.tftest.hcl` (CORS, stage throttling, VPC link),
`tests/custom_domain.tftest.hcl` (REST custom domain: TLS_1_2/REGIONAL, root
base path, Route53 alias, and the two "one input without the other" skip
cases) and `tests/http_routes.tftest.hcl` (`HTTP_PROXY`/`VPC_LINK`,
`AWS_PROXY` + Lambda permission (including proxy-catch-all and `$default`
route keys, whose `{`, `}`, `+`, `$` characters used to break the generated
Lambda `statement_id`), JWT authorization, `tls_server_name_to_verify` wiring
`tls_config` onto the integration (and its rejection on `AWS_PROXY`/
`INTERNET` routes), the `connection_id`/`lambda_function_name` validations,
and that a REST API ignores `http_routes`) run against a mock provider:
`terraform init -backend=false && terraform test`.

## Usage

```
atmos terraform plan apigateway/main -s fnx-dev-testenv-01
```
