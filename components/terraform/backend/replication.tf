/*
 * Cross-region replication of the state bucket (Cloud Posse tfstate-backend's
 * s3_replication_enabled): every state and lock object is copied to
 * <bucket_name>-replica in replica_region, so the state survives, and stays
 * readable, through an outage of the bucket's region (owner decision, B1 DR).
 *
 * Cloud Posse's module replicates into a bucket that a second tfstate-backend
 * instance creates in the DR region (s3_replica_bucket_arn). Deviation: the
 * replica bucket and its key are created here, through the AWS provider's
 * per-resource region (v6), because the one backend instance owns the account's
 * state-access roles and a second instance would collide on their names.
 *
 * Encryption: the state key is multi-region (s3-backend.tf) and its replica in
 * replica_region encrypts the replica bucket, so the same key material protects
 * both copies, as kms/main's DR replica does (#339).
 *
 * The replica is read-only for everyone but S3 replication: the access roles
 * may list and read it (iam.tf), never write. A Terraform run pointed at it
 * (TFSTATE_SOURCE=replica, docs/OPERATIONS.md) can plan with -lock=false and
 * fails on any lock or write, which is the point: the primary may come back.
 */

locals {
  replication_enabled = var.s3_replication_enabled
  replica_bucket_name = "${var.bucket_name}-replica"
}

resource "aws_kms_replica_key" "terraform_state" {
  count = local.replication_enabled ? 1 : 0

  region = var.replica_region

  description             = "Replica of the Terraform state key, for ${local.replica_bucket_name}"
  primary_key_arn         = aws_kms_key.terraform_state_key.arn
  deletion_window_in_days = 30

  # The primary's policy: administration delegated to IAM (the account root);
  # the access roles' and the replication role's policies grant key use.
  policy = aws_kms_key.terraform_state_key.policy
}

resource "aws_kms_alias" "terraform_state_replica" {
  count = local.replication_enabled ? 1 : 0

  region        = var.replica_region
  name          = "alias/${var.tenant}-terraform-state-key"
  target_key_id = aws_kms_replica_key.terraform_state[0].key_id
}

#trivy:ignore:AWS-0089 Access logs need a target bucket in the same region; see the CKV_AWS_18 skip
resource "aws_s3_bucket" "terraform_state_replica" {
  #checkov:skip=CKV_AWS_144:This is the replication destination; replicating the replica again adds a third copy for no recovery gain
  #checkov:skip=CKV_AWS_18:Server access logs need a target bucket in the replica's region; only S3 replication writes here, and the access roles only read during an outage of the primary region
  #checkov:skip=CKV2_AWS_62:Nothing consumes object-created notifications; replication writes, Terraform reads
  count = local.replication_enabled ? 1 : 0

  region = var.replica_region
  bucket = local.replica_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "terraform_state_replica" {
  count = local.replication_enabled ? 1 : 0

  region = var.replica_region
  bucket = aws_s3_bucket.terraform_state_replica[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state_replica" {
  count = local.replication_enabled ? 1 : 0

  region = var.replica_region
  bucket = aws_s3_bucket.terraform_state_replica[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_replica" {
  count = local.replication_enabled ? 1 : 0

  region = var.replica_region
  bucket = aws_s3_bucket.terraform_state_replica[0].id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_replica_key.terraform_state[0].arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# Replication needs versioning on both buckets.
resource "aws_s3_bucket_versioning" "terraform_state_replica" {
  count = local.replication_enabled ? 1 : 0

  region = var.replica_region
  bucket = aws_s3_bucket.terraform_state_replica[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

# The primary's retention for noncurrent versions (s3-backend.tf).
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state_replica" {
  count = local.replication_enabled ? 1 : 0

  region = var.replica_region
  bucket = aws_s3_bucket.terraform_state_replica[0].id

  rule {
    id     = "state-retention"
    status = "Enabled"

    filter {}

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.terraform_state_replica]
}

# TLS-only (TLS 1.2+), as every bucket in s3-backend.tf.
data "aws_iam_policy_document" "terraform_state_replica" {
  count = local.replication_enabled ? 1 : 0

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.terraform_state_replica[0].arn, "${aws_s3_bucket.terraform_state_replica[0].arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid       = "DenyOutdatedTLS"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.terraform_state_replica[0].arn, "${aws_s3_bucket.terraform_state_replica[0].arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "NumericLessThan"
      variable = "s3:TlsVersion"
      values   = ["1.2"]
    }
  }
}

# Write protection beyond IAM: no principal but the replication role may put,
# tag or delete objects in the replica, whatever its own policies grant (an
# administrator included; lifting it is an explicit bucket-policy change).
# Replication itself writes with s3:ReplicateObject, s3:ReplicateDelete and
# s3:ReplicateTags on the destination, never s3:PutObject (AWS S3 User Guide,
# "Setting up permissions for live replication",
# https://docs.aws.amazon.com/AmazonS3/latest/userguide/setting-repl-config-perm-overview.html).
data "aws_iam_policy_document" "terraform_state_replica_writes" {
  count = local.replication_enabled ? 1 : 0

  source_policy_documents = [data.aws_iam_policy_document.terraform_state_replica[0].json]

  statement {
    sid    = "DenyWritesButReplication"
    effect = "Deny"
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:PutObjectTagging",
      "s3:PutObjectVersionTagging",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:DeleteObjectTagging",
      "s3:DeleteObjectVersionTagging",
    ]
    resources = ["${aws_s3_bucket.terraform_state_replica[0].arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "StringNotEquals"
      variable = "aws:PrincipalArn"
      values   = [aws_iam_role.replication[0].arn]
    }
  }
}

resource "aws_s3_bucket_policy" "terraform_state_replica" {
  count = local.replication_enabled ? 1 : 0

  region = var.replica_region
  bucket = aws_s3_bucket.terraform_state_replica[0].id
  policy = data.aws_iam_policy_document.terraform_state_replica_writes[0].json

  depends_on = [aws_s3_bucket_public_access_block.terraform_state_replica]
}

# The replication role, least privilege as in Cloud Posse's
# terraform-aws-tfstate-backend (replication.tf): read the source's object
# versions, write replicas into the destination, and the two keys' use only
# through S3 in their own regions. With S3 Bucket Keys the KMS encryption
# context is the bucket ARN, else the object ARN: both are allowed.
data "aws_iam_policy_document" "replication_assume" {
  count = local.replication_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.terraform_state.arn]
    }
  }
}

data "aws_iam_policy_document" "replication" {
  count = local.replication_enabled ? 1 : 0

  statement {
    sid       = "ReadSourceConfiguration"
    actions   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
    resources = [aws_s3_bucket.terraform_state.arn]
  }

  statement {
    sid       = "ReadSourceVersions"
    actions   = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging"]
    resources = ["${aws_s3_bucket.terraform_state.arn}/*"]
  }

  statement {
    sid       = "WriteReplicas"
    actions   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
    resources = ["${aws_s3_bucket.terraform_state_replica[0].arn}/*"]
  }

  statement {
    sid       = "DecryptSource"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.terraform_state_key.arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.region}.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:s3:arn"
      values   = [aws_s3_bucket.terraform_state.arn, "${aws_s3_bucket.terraform_state.arn}/*"]
    }
  }

  statement {
    sid       = "EncryptReplicas"
    actions   = ["kms:Encrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_replica_key.terraform_state[0].arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.replica_region}.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:s3:arn"
      values   = [aws_s3_bucket.terraform_state_replica[0].arn, "${aws_s3_bucket.terraform_state_replica[0].arn}/*"]
    }
  }
}

resource "aws_iam_role" "replication" {
  count = local.replication_enabled ? 1 : 0

  name               = "${var.bucket_name}-replication"
  description        = "S3 replication of ${var.bucket_name} to ${local.replica_bucket_name} (${var.replica_region})"
  assume_role_policy = data.aws_iam_policy_document.replication_assume[0].json
}

resource "aws_iam_role_policy" "replication" {
  count = local.replication_enabled ? 1 : 0

  name   = "StateReplication"
  role   = aws_iam_role.replication[0].id
  policy = data.aws_iam_policy_document.replication[0].json
}

resource "aws_s3_bucket_replication_configuration" "terraform_state" {
  count = local.replication_enabled ? 1 : 0

  role   = aws_iam_role.replication[0].arn
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "state-to-${var.replica_region}"
    status = "Enabled"

    # Every object: state files and their .tflock lock files.
    filter {}

    # A deleted state (a removed workspace) is deleted in the replica too; its
    # versions stay there, as in the source.
    delete_marker_replication {
      status = "Enabled"
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }

    destination {
      bucket        = aws_s3_bucket.terraform_state_replica[0].arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = aws_kms_replica_key.terraform_state[0].arn
      }
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.terraform_state,
    aws_s3_bucket_versioning.terraform_state_replica,
    aws_iam_role_policy.replication,
  ]
}
