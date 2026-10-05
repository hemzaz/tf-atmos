# sns

One SNS topic per instance with its subscriptions, encrypted with a customer managed key, and a
topic policy that denies publishing without TLS and limits AWS service publishers to this account.
Modelled on Cloud Posse `aws-sns-topic` (input and output names, defaults) as plain resources.

## Wiring

- No instance in the fnx stacks. `sns/defaults` reads `kms/main .key_arn`; the copyable stack
  template `templates/stacks/serverless-stack.yaml` creates `sns/notifications` from it, the
  `batch-processing` catalog template `batch-processing/sns/notifications`. Deploys in the
  `deploy-full-stack` storage layer.

## Notes

- `kms/main` covers EventBridge rules (`allow_eventbridge`) and CloudWatch alarms
  (`allow_cloudwatch_alarms`) publishing to the encrypted topic; other publishers need their own
  key-policy statement.
- An SQS subscriber must let `sns.amazonaws.com` send with `aws:SourceArn` on this topic (the sqs
  component's `iam_policy`); `kms/main`'s `allow_sns` covers the key.
- The generated policy replaces SNS's default one. Other accounts publish via
  `allowed_iam_arns_for_sns_publish`.
- `sns_topic_policy_json` is merged in, not substituted, so the TLS deny stays. Its statements are
  not rescoped: set each `Resource` to the topic ARN. Unpinned `*` or `Service` principals are
  rejected.
- `http` subscriptions are rejected (use `https`); `firehose` needs `subscription_role_arn`.
- An `https` subscriber needs `acknowledge_https_forwarder = true`: its endpoint must answer SNS's
  SubscriptionConfirmation (a Lambda function URL, API Gateway, AWS Chatbot), or the subscription
  stays PendingConfirmation and delivers nothing. Known raw chat-webhook hosts (Slack, Office/Teams,
  Discord) are rejected by name, best effort.
- A subscriber's `dead_letter_queue_arn` takes an sqs instance's queue (Cloud Posse's built-in DLQ
  is not ported).
