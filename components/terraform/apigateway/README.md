# apigateway

A REST API or an HTTP API (`api_type`), with optional custom domain and Route53 alias, access
logs, usage plan and API key, Cognito/Lambda/JWT authorizers, a WAFv2 web ACL, caching and
throttling, HTTP API VPC link and `http_routes`, a dashboard, and 4xx/5xx/latency alarms. The
custom domain is configured on this component, as in Cloud Posse `aws-api-gateway-rest-api`.

## Wiring

- `apigateway/main` (domain `api.<d>`) reads `acm/main .certificate_arns.main_wildcard` and
  `network/main .zone_ids.main`; `apigateway/data` (domain `data.services.<d>`) reads
  `acm/services .certificate_arns.services_wildcard` and `network/services .zone_ids.data`. Both,
  in the three AWS stacks, read `cognito/main .user_pool_arn` and `lambda/data-processor`
  (`.function_invoke_arn`, `.function_name`).
- Used by: `monitoring` (`.api_name`, `.rest_api_stage_name`).
- In the `microservices-platform` template, `http_routes` send `ANY /{proxy+}` over the VPC link to
  `alb-controller-ingress-group`'s `https_listener_arn`, with `tls_server_name_to_verify` set.

## Notes

- The custom domain is skipped silently unless both `domain_name` and `certificate_arn` are set,
  and the alias record unless `zone_id` is set. `check-domains.py` requires the domain to be
  inside the zone.
- The REST custom domain is REGIONAL with `TLS_1_2`; a precondition rejects `EDGE`/`PRIVATE`
  endpoints with a domain.
- `api_resources` hang off the API root: paths are one level deep. Methods and integrations are
  addressed by `resource_path`; every integration needs a matching method.
- `cors_configuration` and `http_routes` apply to HTTP APIs only; a REST API ignores them silently
  (staging and prod set CORS on REST instances, a known gap).
- `api_name` output is null for an HTTP API.
- `enable_waf` and `tracing_enabled` default to `false`; prod opts in per instance.
