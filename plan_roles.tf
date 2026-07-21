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
          # StringEquals, not StringLike: the pull_request subject is an exact,
          # wildcard-free string, so there is no reason to accept a pattern.
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_organization}/${each.value.repo_name}:pull_request"
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
