# apigateway

Creates either a REST API (`aws_api_gateway_rest_api` + stage + deployment) or an HTTP
API (`aws_apigatewayv2_api` + stage), chosen by `var.api_type`. Optional: custom domain
+ Route53 alias when `domain_name` and `certificate_arn` are both set, CloudWatch access
logging, usage plan + API key, Cognito/Lambda/JWT authorizers, a WAFv2 web ACL
(rate-limit + geo-block + AWS managed rules), method caching/throttling, a CloudWatch
dashboard (`templates/dashboard.json.tpl`), and 4xx/5xx/latency alarms.

## Deployed as

Real instances `apigateway/main` and `apigateway/data` in all 3 stacks:
`fnx-dev-testenv-01`, `fnx-staging-staging-01`, `fnx-prod-production`. The catalog also
has abstract `apigateway_domain`/`apigateway_http`/`apigateway_rest` entries — none real.

## Inputs / Outputs

| Input | Notes |
|---|---|
| `api_type` | `REST` or `HTTP`, picks which resource set is created |
| `domain_name`, `certificate_arn` | both required together for the custom domain |
| `zone_id` | required for the Route53 alias record |
| `enable_waf` | default false; not enabled in any real stack today |

No component reads these outputs via `!terraform.state apigateway...` — 0 matches in `stacks/`.

## Dependencies / gotchas

- `apigateway/main` depends on `acm/main`, `network/main`; `apigateway/data` depends on
  `acm/services`, `network/services`.
- Custom-domain resources are silently skipped if only one of `domain_name` /
  `certificate_arn` is set.
- `zone_id` must be non-null or the alias record is skipped even with a domain set.

## Usage

```
atmos terraform plan apigateway/main -s fnx-dev-testenv-01
atmos terraform plan apigateway/data -s fnx-staging-staging-01
```
