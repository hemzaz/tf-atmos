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
- Both depend on `apigateway-account/main` (the account's CloudWatch Logs role; ordering only).
- Used by: `monitoring` (`.api_name`, `.rest_api_stage_name`).
- In the `microservices-platform` template, `http_routes` send `ANY /{proxy+}` over the VPC link to
  `alb-controller-ingress-group`'s `https_listener_arn`, with `tls_server_name_to_verify` set.

## Notes

- The custom domain is skipped silently unless both `domain_name` and `certificate_arn` are set,
  and the alias record unless `zone_id` is set. `check-domains.py` requires the domain to be
  inside the zone and covered by the `acm` certificate `certificate_arn` reads; a literal
  certificate ARN is only a warning.
- The REST custom domain is REGIONAL with `TLS_1_2`; a precondition rejects `EDGE`/`PRIVATE`
  endpoints with a domain.
- `api_resources` hang off the API root unless `parent_id` names another resource; methods and
  integrations still address them as `"/<path_part>"`, and every integration needs a matching
  method. The cache `method_path` uses the resource's full path (`v1/products/GET`).
- `cors_configuration` and `http_routes` apply to HTTP APIs only; a REST API ignores them silently
  (staging and prod set CORS on REST instances, a known gap).
- `api_name` output is null for an HTTP API.
- REST caching is per method: `cache_method_paths` lists `api_methods` keys (`"GET /products"`)
  and `enable_caching` provisions the billed cache cluster; each needs the other. `"*/*"` needs
  `cache_all_methods_acknowledged`. A cached method with authorization other than `NONE` must put
  the identity header in its `request_parameters` and its integration's `cache_key_parameters`,
  or users share cache entries (validated). For `AWS_IAM` that header is the SigV4
  `Authorization`, unique per request, so the method never hits: don't cache `AWS_IAM` methods.
  Cached data is encrypted, and `Cache-Control` bypass without `execute-api:InvalidateCache` gets
  a 403. No instance caches today.
- `cache_method_paths` allows one method besides `"*/*"`: each is its own method setting, an
  `UpdateStage` on the same stage, and parallel ones fail with `ConflictException`.
- The stage-wide `*/*` method settings (throttling, execution logging, metrics) apply to every
  REST stage; they used to exist only with caching on. REST execution and access logging need the
  account-level API Gateway CloudWatch role, which `apigateway-account` sets: a stack with a REST
  instance that logs needs `apigateway-account/main`, in `dependencies.components` and an earlier
  deploy layer, or the stage fails to create.
- `enable_waf`'s inline web ACL has no logging configuration (so nothing to redact); the `waf`
  component is the one with logs.
- `enable_waf` and `tracing_enabled` default to `false`. WAF is on for `apigateway/data` in every
  stack and for prod's `apigateway/main`; X-Ray tracing is on in prod only.
