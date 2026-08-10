# ==============================================================================
# PR-TIME PLAN ROLES (read-only)
# ==============================================================================
# A second, deliberately weaker identity per opted-in project, for `tofu plan`
# on pull requests.
#
# WHY THIS IS NOT just a wider `sub` condition on `github_actions_role`:
# that role can apply. Workflow changes in a pull request take effect for
# `pull_request` runs, so allowlisting the `:pull_request` subject on the apply
# role would mean that merely OPENING a PR grants apply-capable AWS credentials
# with no human approval — defeating the environment-approval gate it sits
# behind (bounty-infra #9). The apply role stays pinned to the `main` ref
# subject; PR-time reads get their own role, and it can only read.
#
# Grants are the read-only mirror of each project's workload policy, scoped to
# what `tofu plan` actually refreshes. Notably NOT the AWS-managed
# `ReadOnlyAccess`, which would grant `s3:GetObject` across every bucket in the
# account, including the bug-bounty findings archive.

locals {
  # Only projects that opt in via `plan_role = true` get one.
  plan_role_projects = { for k, v in var.projects : k => v if v.plan_role }
}

resource "aws_iam_role" "github_actions_plan_role" {
  for_each = local.plan_role_projects

  name        = "github-actions-${each.key}-plan"
  description = "Read-only PR-time tofu plan role for ${each.value.repo_name}"

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
          # StringEquals, not StringLike: every rendered subject below is an exact,
          # wildcard-free string, so there is no reason to accept a pattern.
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            # A one-element list where a bare string used to stand. IAM treats a
            # condition value as a set, so the two are equivalent -- this exists so a
            # project can also trust a push-triggered plan job (extra_plan_oidc_subjects,
            # F56 gap a), e.g. "ref:refs/heads/main" for a push-triggered tofu-plan-main.
            "token.actions.githubusercontent.com:sub" = concat(
              ["${local.subject_prefix[each.key]}:pull_request"],
              [for s in each.value.extra_plan_oidc_subjects : "${local.subject_prefix[each.key]}:${s}"]
            )
          }
        }
      }
    ]
  })
}

# ---------------------------------------------------------
# State access: READ ONLY, and no lock
# ---------------------------------------------------------
# The apply role's equivalent (`pipeline_state_policy`) grants PutObject,
# DeleteObject and the DynamoDB lock verbs. None of those appear here:
# a plan must never write state, and it runs with `-lock=false` precisely so it
# cannot block a concurrent apply on the lock table.
resource "aws_iam_role_policy" "plan_state_read_policy" {
  for_each = local.plan_role_projects

  name = "${each.key}-plan-state-read"
  role = aws_iam_role.github_actions_plan_role[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowListStateBucketOfSpecificPrefix"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.state_bucket.arn
        Condition = {
          StringLike = { "s3:prefix" : ["${each.key}/*"] }
        }
      },
      {
        Sid      = "AllowReadOnlyOfSpecificPrefix"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.state_bucket.arn}/${each.key}/*"
      }
    ]
  })
}

# ---------------------------------------------------------
# bounty-infra: read-only mirror of the workload policy
# ---------------------------------------------------------
# Lives here rather than in project_policies.tf so that everything about the
# plan identity is readable in one place.
#
# The Describe/List/Get actions below have no resource-level scoping in IAM, so
# `Resource = "*"` is unavoidable — the containment comes from the action list
# being read-only and from the explicit Deny at the end.
resource "aws_iam_policy" "bounty_infra_plan_policy" {
  name        = "glunk-works-bounty-infra-plan-readonly"
  description = "Read-only permissions for bounty-infra PR-time tofu plan"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowReadOfManagedResources"
        Effect = "Allow"
        Action = [
          # Network (aws_vpc, aws_subnet, aws_internet_gateway,
          # aws_route_table[_association], aws_security_group)
          "ec2:DescribeVpcs", "ec2:DescribeVpcAttribute", "ec2:DescribeSubnets",
          "ec2:DescribeInternetGateways", "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups", "ec2:DescribeSecurityGroupRules",
          "ec2:DescribeNetworkAcls", "ec2:DescribeAvailabilityZones", "ec2:DescribeTags",

          # ECS (aws_ecs_cluster, aws_ecs_task_definition)
          "ecs:DescribeClusters", "ecs:DescribeTaskDefinition", "ecs:ListTagsForResource",

          # ECR (aws_ecr_repository)
          "ecr:DescribeRepositories", "ecr:ListTagsForResource",
          "ecr:GetRepositoryPolicy", "ecr:GetLifecyclePolicy",

          # CloudWatch Logs (aws_cloudwatch_log_group)
          "logs:DescribeLogGroups", "logs:ListTagsForResource",

          # IAM (aws_iam_role x2, aws_iam_policy, the attachments)
          "iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole",
          "iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions"
        ]
        Resource = "*"
      },
      {
        # Belt and braces for BI-D4. `tofu plan` never touches the findings
        # archive — it only interpolates the bucket NAME into a policy document
        # — so denying it outright costs nothing and makes it structurally
        # impossible for a PR-triggered role to read third-party vulnerability
        # data, even if a later edit widens the Allow above.
        Sid    = "DenyBountyFindingsDataAccess"
        Effect = "Deny"
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.findings_bucket.arn,
          "${aws_s3_bucket.findings_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "bounty_infra_plan_attach" {
  role       = aws_iam_role.github_actions_plan_role["bounty-infra"].name
  policy_arn = aws_iam_policy.bounty_infra_plan_policy.arn
}

# ---------------------------------------------------------
# bedrock-serverless-rag: read-only mirror of the workload policy (F56 gap b, S2-T0c)
# ---------------------------------------------------------
# Without this, github-actions-bedrock-serverless-rag-plan holds state-read (from
# plan_state_read_policy above, generic to every plan_role_projects entry) and NOTHING else --
# no iam:GetRole, no aoss:*, no bedrock:Get*, no s3:GetBucket* -- and every PR plan 403s on
# refresh, same gap this file's own header comment names for bounty-infra. Read-only subset of
# project_policies.tf's bedrock_rag_workload_policy: every Create/Delete/Put/Update/Attach/
# Detach verb dropped, every Resource scope kept identical.
resource "aws_iam_policy" "bedrock_rag_plan_policy" {
  name        = "glunk-works-bedrock-serverless-rag-plan-readonly"
  description = "Read-only permissions for bedrock-serverless-rag PR-time tofu plan"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Mirrors ManageSourceBucketLifecycle, read-only. s3:ListBucket travels with the
        # Get* verbs for the same reason bootstrap/state-backend.tf grants it to the apply
        # role: HeadBucket's anti-enumeration 403 makes the provider's refresh misreport the
        # bucket as deleted without it.
        Sid    = "ReadSourceBucketLifecycle"
        Effect = "Allow"
        Action = [
          "s3:ListBucket", "s3:GetBucket*",
          "s3:GetEncryptionConfiguration", "s3:GetLifecycleConfiguration",
          "s3:GetReplicationConfiguration", "s3:GetAccelerateConfiguration"
        ]
        Resource = "arn:aws:s3:::${var.bedrock_rag_source_bucket_name}"
      },
      {
        # Mirrors ReadUpdateTagKBExecutionRole's read-only subset.
        Sid    = "ReadKBExecutionRole"
        Effect = "Allow"
        Action = [
          "iam:GetRole", "iam:ListRolePolicies", "iam:GetRolePolicy",
          "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/bedrock-rag/*"
      },
      {
        # Mirrors ReadDeleteListCollectionPolicies -- see that statement's comment for why
        # Resource = "*" is AWS's own requirement here, not a residual we chose.
        Sid    = "ReadCollectionPolicies"
        Effect = "Allow"
        Action = [
          "aoss:GetSecurityPolicy", "aoss:ListSecurityPolicies",
          "aoss:GetAccessPolicy", "aoss:BatchGetCollection", "aoss:ListTagsForResource"
        ]
        Resource = "*"
      },
      {
        # Mirrors ReadDeleteKnowledgeBaseAndDataSource's read-only subset. No aoss:APIAccessAll
        # here -- that is a data-plane grant `tofu plan` never exercises.
        Sid      = "ReadKnowledgeBaseAndDataSource"
        Effect   = "Allow"
        Action   = ["bedrock:GetKnowledgeBase", "bedrock:GetDataSource", "bedrock:ListTagsForResource"]
        Resource = "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:knowledge-base/*"
      },
      {
        # Mirrors ManageCostBudget's read-only subset (drops budgets:ModifyBudget).
        Sid      = "ReadCostBudget"
        Effect   = "Allow"
        Action   = ["budgets:ViewBudget", "budgets:ListTagsForResource"]
        Resource = "arn:aws:budgets::${data.aws_caller_identity.current.account_id}:budget/bedrock-serverless-rag-ai-lab-monthly"
      },
      {
        # BR-D22 state-encryption key access, read-only subset. Deliberately asymmetric with
        # the apply role despite Task 0c step 1b's text naming all three verbs for "both
        # roles": kms:GenerateDataKey is the encrypt-side verb (mints a NEW data key, i.e.
        # writes), and this whole file's own design invariant -- stated in its header comment
        # and in plan_state_read_policy above -- is that the plan role can only read. Granting
        # a write-side verb to the one identity assumable from any pull_request contradicts
        # that invariant for no operational benefit: a plan only ever decrypts.
        Sid      = "StateEncryptionKeyReadAccess"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = aws_kms_key.state_key.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "bedrock_rag_plan_attach" {
  role       = aws_iam_role.github_actions_plan_role["bedrock-serverless-rag"].name
  policy_arn = aws_iam_policy.bedrock_rag_plan_policy.arn
}

# Same findings Deny (F58 gap b) as the apply role -- "Attach our Deny to BOTH our roles"
# (Task 0c's own constraint). The policy resource itself lives in project_policies.tf.
resource "aws_iam_role_policy_attachment" "bedrock_rag_plan_findings_deny_attach" {
  role       = aws_iam_role.github_actions_plan_role["bedrock-serverless-rag"].name
  policy_arn = aws_iam_policy.bedrock_rag_findings_deny.arn
}
