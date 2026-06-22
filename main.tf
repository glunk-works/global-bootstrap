provider "aws" {
  region = var.aws_region
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
  bucket = aws_s3_bucket.state_bucket.bucket
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
# 3. Secure Identity Federation (GitHub OIDC Provider)
# ---------------------------------------------------------
data "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
}

# ---------------------------------------------------------
# 4. Dynamic CI/CD Roles (Generated 1 per project)
# ---------------------------------------------------------
resource "aws_iam_role" "github_actions_role" {
  for_each = var.projects

  name = "github-actions-${each.key}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = [data.aws_iam_openid_connect_provider.github.arn]
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_organization}/${each.value.repo_name}:ref:refs/heads/main"
          }
        }
      }
    ]
  })
}

# ---------------------------------------------------------
# 5. Dynamic Prefix Policies (Generated 1 per project)
# ---------------------------------------------------------
resource "aws_iam_role_policy" "pipeline_restricted_policy" {
  for_each = var.projects

  name = "${each.key}-pipeline-policy"
  role = aws_iam_role.github_actions_role[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowListBucketOfSpecificPrefix"
        Effect = "Allow"
        Action = "s3:ListBucket"
        Resource = aws_s3_bucket.state_bucket.arn
        Condition = {
          StringLike = { "s3:prefix" : ["${each.key}/*"] }
        }
      },
      {
        Sid    = "AllowReadWriteToSpecificPrefix"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.state_bucket.arn}/${each.key}/*"
      },
      {
        Sid    = "AllowDynamoDBStateLocking"
        Effect = "Allow"
        Action = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = aws_dynamodb_table.state_locks.arn
      },
      {
        Sid    = "AllowWorkloadManagement"
        Effect = "Allow"
        Action = concat(
          [
            "iam:PassRole",
            "iam:CreateRole",
            "iam:DeleteRole",
            "iam:PutRolePolicy",
            "iam:DeleteRolePolicy",
            "iam:GetRole",
            "iam:GetRolePolicy",
            "iam:AttachRolePolicy",
            "iam:DetachRolePolicy"
          ],
          each.value.allowed_actions
        )
        Resource = "*"
      }
    ]
  })
}