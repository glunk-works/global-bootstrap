provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------
# 1. Global State Storage (S3 Bucket)
# ---------------------------------------------------------
resource "aws_s3_bucket" "state_bucket" {
  bucket        = var.bootstrap_bucket_name
  force_destroy = false
}

resource "aws_s3_bucket_versioning" "state_versioning" {
  bucket = aws_s3_bucket.state_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state_encryption" {
  bucket = aws_s3_bucket.state_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ---------------------------------------------------------
# 2. Distributed State Lock (DynamoDB Table)
# ---------------------------------------------------------
resource "aws_dynamodb_table" "state_locks" {
  name         = "global-tofu-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# ---------------------------------------------------------
# 3. Centralized Vulnerability Findings Storage
# ---------------------------------------------------------
resource "aws_kms_key" "findings_key" {
  description             = "KMS Key for Bug Bounty Findings S3 Bucket"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_s3_bucket" "findings_bucket" {
  bucket        = var.findings_bucket_name
  force_destroy = false
}

resource "aws_s3_bucket_server_side_encryption_configuration" "findings_encryption" {
  bucket = aws_s3_bucket.findings_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.findings_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "findings_privacy" {
  bucket                  = aws_s3_bucket.findings_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------
# 4. Secure Identity Federation (GitHub OIDC Provider)
# ---------------------------------------------------------
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# ---------------------------------------------------------
# 5. Dynamic CI/CD Roles (Generated 1 per project)
# ---------------------------------------------------------

# The OIDC subject prefix each project's roles are built from. Defaults to the
# plain computed form; a project can override via `oidc_subject_prefix` when it
# presents an ID-qualified subject instead (BR-D27). The default preserves
# every existing project's rendered value byte-for-byte.
locals {
  subject_prefix = {
    for k, v in var.projects :
    k => coalesce(v.oidc_subject_prefix, "repo:${var.github_organization}/${v.repo_name}")
  }
}

resource "aws_iam_role" "github_actions_role" {
  for_each = var.projects

  name = "github-actions-${each.key}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          # StringEquals, not StringLike (F2): in IAM StringLike, '*' matches ':' too, so an
          # extra_oidc_subjects entry containing a wildcard would glob silently past this
          # role's federated principal. Every rendered subject is wildcard-free today, which
          # is what makes this behaviour-preserving -- it removes the mechanism rather than
          # relying on the values staying clean.
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            # A job that references a GitHub Environment does NOT present the
            # branch subject: the environment filter takes precedence, so the
            # subject becomes `...:environment:<name>` and this role would
            # reject it. A project gating a deploy behind an Environment must
            # therefore list that subject in `extra_oidc_subjects` — an
            # addition, not a replacement, because sibling workflows on the same
            # role (image build, scan dispatch) still present the branch subject.
            "token.actions.githubusercontent.com:sub" = concat(
              ["${local.subject_prefix[each.key]}:ref:refs/heads/main"],
              [for s in each.value.extra_oidc_subjects : "${local.subject_prefix[each.key]}:${s}"]
            )
          }
        }
      }
    ]
  })
}

# Ensure the ECS Service Linked Role exists for Fargate ENI provisioning
resource "aws_iam_service_linked_role" "ecs" {
  aws_service_name = "ecs.amazonaws.com"
}

# ---------------------------------------------------------
# 6. Dynamic State Access Policy (Inline - State Scope Only)
# ---------------------------------------------------------
resource "aws_iam_role_policy" "pipeline_state_policy" {
  for_each = var.projects

  name = "${each.key}-state-policy"
  role = aws_iam_role.github_actions_role[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowListBucketOfSpecificPrefix"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.state_bucket.arn
        Condition = {
          StringLike = { "s3:prefix" : ["${each.key}/*"] }
        }
      },
      {
        Sid      = "AllowReadWriteToSpecificPrefix"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.state_bucket.arn}/${each.key}/*"
      },
      {
        Sid      = "AllowDynamoDBStateLocking"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = aws_dynamodb_table.state_locks.arn
      }
    ]
  })
}