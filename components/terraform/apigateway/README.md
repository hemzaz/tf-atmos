# apigateway

Creates either a REST API (`aws_api_gateway_rest_api` + stage + deployment) or an HTTP API
(`aws_apigatewayv2_api` + stage), chosen by `var.api_type`. Optional: custom domain + Route53 alias,
access logging, usage plan + API key, Cognito/Lambda/JWT authorizers, a WAFv2 web ACL (rate-limit +
geo-block + AWS managed rules), caching/throttling, a dashboard, and 4xx/5xx/latency alarms.

Real instances `apigateway/main` and `apigateway/data` in all 3 stacks; the catalog's
`apigateway_domain`/`apigateway_http`/`apigateway_rest` entries are abstract.

## Inputs / Outputs

| Input | Notes |
|---|---|
| `api_type` | `REST` or `HTTP`, picks which resource set is created |
| `api_resources` | one `path_part` each; the resource is then addressed as `/<path_part>` |
| `api_methods` | addressed by `resource_path` (`/` is the API root), never by resource id |
| `api_integrations` | exactly one per method, same `resource_path` + `http_method`; `uri` required unless `type` is `MOCK` |
| `domain_name`, `certificate_arn` | both required together for the custom domain |
| `zone_id` | required for the Route53 alias record |
| `enable_waf` / `tracing_enabled` | both default false; prod opts in per instance. X-Ray bills per trace, so dev/staging stay off |
| `waf_common_rule_set_action`, `waf_known_bad_inputs_action` | `block` (default) or `count`, one per AWS managed rule group, so either can be soaked without relaxing the other |
| `cors_configuration` (null) | HTTP APIs only. It used to be silently ignored (the code looked up an `enabled` key the object type does not have), so no HTTP API got CORS; it is now applied whenever set. Validated: `allow_credentials = true` with `"*"` in `allow_origins` is refused, and `max_age` must be 0-86400. REST APIs ignore it silently (live staging and prod `apigateway/main` set it on REST); rejecting that is a known gap left open so those instances keep planning |
| `throttling_rate_limit`, `throttling_burst_limit` | REST: per-method settings (with caching). HTTP: the stage's `default_route_settings` |
| `vpc_link_subnet_ids`, `vpc_link_security_group_ids` | HTTP APIs: a VPC link `<Environment>-<api_name>-vpc-link` for private integrations; the security groups are required with the subnets. Outputs `http_api_vpc_link_id` and `http_api_vpc_link_arn`; its Name tag is `<prefix>-vpc-link`. Routes and integrations that use it are not defined here |

## Dependencies / gotchas

- `apigateway/main` depends on `acm/main`, `network/main`; `apigateway/data` depends on
  `acm/services`, `network/services`.
- Custom-domain resources are silently skipped if only one of `domain_name` /
  `certificate_arn` is set; `zone_id` must be non-null or the alias record is skipped too.
- `api_resources` hangs every resource off the API root, so declarable paths are one level deep. An
  entry with an explicit external `parent_id` is still keyed `/<path_part>`, not its real URL.
- The deployment redeploys whenever `api_resources`/`api_methods`/`api_integrations` change. The
  first apply after this trigger was added replaces the deployment once, `create_before_destroy`.
- No component reads these outputs via `!terraform.state apigateway...` — 0 matches in `stacks/`.

## Tests

`tests/http_api.tftest.hcl` (CORS, stage throttling, VPC link) runs against a
mock provider: `terraform init -backend=false && terraform test`.

## Usage

```
atmos terraform plan apigateway/main -s fnx-dev-testenv-01
```
