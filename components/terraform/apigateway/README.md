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
- `fnx-ue1-prod`'s and `fnx-ew1-prod`'s `apigateway/main` inherit `apigateway/main-prod`
  (`stacks/catalog/apigateway/prod.yaml`) and are the PRIMARY halves of `api.<d>`'s failover
  pairs; `fnx-ue2-prod`'s and `fnx-ec1-prod`'s, configured inline, the SECONDARY ones.
- Used by: `monitoring` (`.api_name`, `.rest_api_stage_name`).
- In the `microservices-platform` template, `http_routes` send `ANY /{proxy+}` over the VPC link to
  `alb-controller-ingress-group`'s `https_listener_arn`, with `tls_server_name_to_verify` set.

## Notes

- The custom domain is skipped silently unless both `domain_name` and `certificate_arn` are set,
  and the alias record unless `zone_id` is set. `check-domains.py` requires the domain to be
  inside the zone and covered by the `acm` certificate `certificate_arn` reads; a literal
  certificate ARN is only a warning.
- `route53_failover_type` (`PRIMARY`/`SECONDARY`) with `route53_set_identifier` makes the alias
  record one half of a Route 53 failover pair: each region's instance owns its half for the same
  `domain_name` in the same zone, and gets a health check, HTTPS to its own stage root on the
  execute-api endpoint (`<api id>.execute-api.<region>.amazonaws.com/<stage>/`), so the name moves
  to the other region when this one's API Gateway stops answering. Cloud Posse's
  `aws-api-gateway-rest-api` has no failover; this follows AWS's regional-API failover pattern.
  The checker calls unauthenticated, so validations require a `GET`/`ANY` method on `/` with
  authorization `NONE` and no API key, and `US` in `allowed_countries` when the WAF geo rule is
  on (the check then calls from the US checker regions only). The execute-api endpoint stays
  enabled (`disable_execute_api_endpoint = false`). The component attaches no resource policy;
  one added later must still admit the Route 53 health checkers.
- The failover health check gets a `HealthCheckStatus` alarm, notifying `health_check_alarm_actions`
  on failure and recovery. Route 53 publishes the metric in us-east-1 only, so the alarm lives
  there (the resource's `region` argument) and its topics must be us-east-1 topics: both US prod
  stacks point it at `fnx-ue1-prod` `monitoring/main`'s topic, by name (that component reads this
  one).
- An EU stack has no topic in us-east-1 and no non-EU stack may read its state (GDPR, owner
  decision B5), so `create_health_check_alarm_topic` makes this component create one there,
  `<Environment>-<api_name>-health-check-alarms`, on its own rotated us-east-1 KMS key (the EU
  `kms/main` has no us-east-1 replica), subscribing `health_check_alarm_email_subscriptions`. Its
  policy admits CloudWatch alarms of the account in us-east-1 only. `fnx-ew1-prod`'s creates it and
  `fnx-ec1-prod`'s alarm names it, as `fnx-ue2-prod`'s names `ue1-main-alarms`. It carries alarm
  state only (`check-data-residency.py` EXEMPTIONS lists these fields).
- `health_check_regions` sets the checker regions (at least 3; null = every one). The EU pair uses
  `eu-west-1`, the only EU checker region, plus `us-east-1` and `ap-southeast-1` (probes only). A
  WAF geo rule (`allowed_countries`) pins the US checker regions instead, so the two cannot be
  combined.
- A `MOCK` integration answers 200: without `request_templates` it gets one selecting
  `statusCode: 200`, plus a 200 method and integration response (API Gateway answers 500 without
  them). `/`, the liveness method the health check probes, is such a MOCK.
- The REST custom domain is REGIONAL with `TLS_1_2`; a precondition rejects `EDGE`/`PRIVATE`
  endpoints with a domain.
- `api_resources` hang off the API root unless `parent_id` names another resource; methods and
  integrations still address them as `"/<path_part>"`, and every integration needs a matching
  method. The cache `method_path` uses the resource's full path (`v1/products/GET`).
- A `COGNITO_USER_POOLS` method without `authorization_scopes` accepts ID tokens only; with them
  it accepts access tokens carrying one of the scopes (a `client_credentials` client's token,
  `<resource server identifier>/<scope>`), and no longer ID tokens.
- `gateway_responses` (REST only, validated), keyed by response type, set what API Gateway
  answers itself: an authorizer's 401/403, a WAF or throttle reject. They carry no CORS headers
  by default, so a browser cannot read the status; a SPA's API sets the CORS headers on
  `DEFAULT_4XX`/`DEFAULT_5XX`. Only a new deployment serves a change (they are in its trigger).
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
