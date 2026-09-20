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

## Usage

```
atmos terraform plan apigateway/main -s fnx-dev-testenv-01
```
