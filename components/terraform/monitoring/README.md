# monitoring

CloudWatch log groups and dashboards, a KMS-encrypted SNS alarm topic with email subscriptions,
EC2/RDS/Lambda/EKS/ALB/ElastiCache/API Gateway alarms, certificate-expiry monitoring, optional
Synthetics canary and X-Ray sampling rule, business-metric filters, and generic `metric_alarms`,
`metric_dashboards` and `log_insights_queries` for any metric by namespace and dimensions.

## Wiring

- Instances: `monitoring/main` (`name: main`) and `monitoring/data` (`name: data`) in the three
  AWS stacks; `monitoring/main` also in `fnx-ue1-local-localemu`, `fnx-ue2-prod`, `fnx-ew1-prod` and
  `fnx-ec1-prod`
  (`fnx-ue1-prod`'s and `fnx-ew1-prod`'s inherit `monitoring/main-prod`,
  `stacks/catalog/monitoring/prod.yaml`). Both read `kms/main .key_arn`.
- `monitoring/main` reads `acm/main`, `apigateway/main`, `eks/main`, `rds/main`, `ecs/main` (not in `fnx-ue2-prod`, `fnx-ew1-prod` or `fnx-ec1-prod`) and, in
  prod, `elasticache/main .member_clusters`.
- `monitoring/data` reads `acm/services`, `apigateway/data`, `eks/data`, `rds/data` and the stack's
  `lambda/*` functions.
- Deploys in the last (`monitoring`) layer. Nothing reads its outputs.

## Notes

- Every resource is `<Environment>-<name>-<suffix>` (Cloud Posse null-label style). Two instances
  in one stack need distinct `name`s or their topics, dashboards and alarms collide.
- `custom_dashboards` / `metric_dashboards` keys must not reuse a built-in dashboard suffix
  (`infrastructure-overview`, `certificates`, `backend-services`, ...): validated.
- `kms_key_id` is set per instance, not in `monitoring/defaults`: the stack templates inherit the
  base without a `kms/main` dependency. Null leaves the topic and log group unencrypted.
- Use `rds/* .instance_identifier` for RDS dimensions (not `instance_id`), and REST `api_name`;
  an HTTP API publishes no `ApiName`, so use `metric_alarms` with `ApiId` instead.
- The EKS node alarms read Container Insights metrics from `eks-addons`; set `eks_min_node_count`
  to the sum of the node groups' `min_group_size`.
- Alarms notify the own topic when `create_sns_topic = true` (default) and every topic in
  `alarm_sns_topic_arns` (an `sns` instance, for subscribers the own email-only topic cannot take).
- `lambda_error_alarms` keys are stable alarm ids; the watched function is each entry's
  `function_name` (validated as a name, not an ARN), never the key.
- `create_dashboard` is a legacy alias of `create_infrastructure_dashboard`, still set by the stacks.
- `receive_relayed_health_check_alarms` (the EU prod stacks, owner decision B5) is the receiving end
  of `apigateway`'s `health_check_alarm_relay_regions`: an EventBridge rule on this region's
  default bus matching this account's us-east-1 alarms named `*-health-check` (only a relay brings
  us-east-1 events here; the wildcard also matches the peer stack's alarm, whose state this stack
  cannot read), targeting the own topic, plus a topic policy for that rule and this region's
  CloudWatch alarms. The topic's key must allow EventBridge (`kms` `allow_eventbridge`, on in prod).
