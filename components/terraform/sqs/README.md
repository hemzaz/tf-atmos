# sqs

One SQS queue per instance with an optional dead-letter queue, both encrypted with a customer
managed key. Modelled on Cloud Posse `aws-sqs-queue` (input names, defaults and the `iam_policy`
queue policy) as plain resources.

## Wiring

- No instance in the fnx stacks. `sqs/defaults` reads `kms/main .key_arn`; the `batch-processing`
  and `microservices-platform` templates create queues from it (`serverless-api` also declares one).
- Consumers read `.queue_arn`, `.queue_name` and `.dead_letter_queue_*` (null unless `dlq_enabled`).
- Deploys in the `deploy-full-stack` storage layer, with `s3`: an s3 instance notifying a queue
  builds its ARN from the queue's name instead of reading its state.

## Notes

- A service producer needs both a key-policy grant and `sqs:SendMessage` in `iam_policy`.
  `kms/main` already covers EventBridge (`allow_eventbridge`), SNS (`allow_sns`) and S3
  (`allow_s3`) in this account and region.
- `iam_policy` statements are scoped to the queue. Allow statements need named principals, no
  wildcard actions or principals, and a `Service` principal must be pinned to its caller
  (`aws:SourceArn`, `aws:SourceAccount`, ...).
- `iam_policy_limit_to_current_account` (default `true`) adds `aws:SourceAccount` to Allow
  statements, which never matches IAM role principals; set it `false` for those.
- `iam_policy` applies to the main queue only. For an EventBridge bus DLQ, use a separate sqs
  instance whose policy lets the bus send.
- The DLQ keeps messages 14 days by default (Cloud Posse: 4) and accepts only this queue.
- Queue names are `<Environment>-<name>` (plus `.fifo`), at most 80 characters.
