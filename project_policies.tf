# ==============================================================================
# CUSTOMER MANAGED POLICIES
# These policies dictate exactly what AWS services each project's CI/CD pipeline
# is allowed to provision.
# ==============================================================================

# ---------------------------------------------------------
# 1. Bounty Infra (Zero-Trust Fargate Scanner)
# ---------------------------------------------------------
resource "aws_iam_policy" "bounty_infra_policy" {
  name        = "glunk-works-bounty-infra-workload"
  description = "Strict least-privilege permissions for the bounty-infra pipeline"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          # Network Provisioning
          "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:DescribeVpcs", "ec2:ModifyVpcAttribute",
          "ec2:DescribeVpcAttribute", "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:DescribeSubnets", "ec2:ModifySubnetAttribute",
          "ec2:CreateInternetGateway", "ec2:AttachInternetGateway", "ec2:DetachInternetGateway", "ec2:DeleteInternetGateway",
          "ec2:DescribeInternetGateways", "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:DescribeRouteTables",
          "ec2:CreateRoute", "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
          "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup", "ec2:DescribeSecurityGroups",
          "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupEgress",
          # bounty-infra SE Phase 2: tearing down the VPC/subnet/SG for the
          # first time (nothing had ever deleted them before) surfaced that
          # the AWS provider calls DescribeNetworkInterfaces as a safety
          # check before it will delete a security group or subnet, to
          # detach/force-delete any ENI still attached first -- a call this
          # policy never needed for CREATE. DeleteNetworkInterface travels
          # with it so that check can actually clear a stray ENI, not just
          # observe one.
          "ec2:DescribeNetworkInterfaces", "ec2:DeleteNetworkInterface",
          "ec2:CreateTags", "ec2:DeleteTags",

          # ECS / Fargate Compute
          "ecs:CreateCluster", "ecs:DeleteCluster", "ecs:DescribeClusters",
          "ecs:RegisterTaskDefinition", "ecs:DeregisterTaskDefinition", "ecs:DescribeTaskDefinition",
          "ecs:RunTask",

          # ECR (Container Registry & Image Pushes)
          "ecr:CreateRepository", "ecr:DeleteRepository", "ecr:DescribeRepositories",
          "ecr:ListTagsForResource", "ecr:PutImageTagMutability",
          "ecr:GetAuthorizationToken", "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer", "ecr:GetRepositoryPolicy", "ecr:ListImages",
          "ecr:DescribeImages", "ecr:BatchGetImage", "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage",

          # CloudWatch Logs
          "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:DescribeLogGroups",
          "logs:ListTagsForResource", "logs:PutRetentionPolicy",

          # IAM Policy Management (Required to construct container Execution/Task roles)
          "iam:PassRole", "iam:CreateRole", "iam:DeleteRole",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRole",
          "iam:GetRolePolicy", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy",
          "iam:GetPolicyVersion", "iam:ListPolicyVersions", "iam:ListInstanceProfilesForRole",
          "iam:ListRolePolicies", "iam:ListAttachedRolePolicies"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowECSTaskExecutionAndMonitoring"
        Effect = "Allow"
        Action = [
          "ecs:RunTask",
          "ecs:DescribeTasks",
          "ecs:StopTask"
        ]
        # Scoped down to your cluster and task definitions for security
        Resource = [
          "arn:aws:ecs:*:*:task-definition/bounty-scanner-task:*",
          "arn:aws:ecs:*:*:task-definition/bounty-scanner-task",
          "arn:aws:ecs:*:*:cluster/bounty-scanner-cluster",
          "arn:aws:ecs:*:*:task/bounty-scanner-cluster/*"
        ]
      },
      {
        Sid    = "AllowPassingExecutionAndTaskRoles"
        Effect = "Allow"
        Action = "iam:PassRole"
        # The actions role must be able to pass these roles to the ECS service
        Resource = [
          "arn:aws:iam::*:role/*-ecs-execution-role",
          "arn:aws:iam::*:role/*-ecs-task-role"
        ]
      },
      {
        # SE (bounty-infra sprints/SE_egress_migration, BI-D5/SE-MG2):
        # run-scan.yml chains into bounty-scanner-s3-writer for the per-scan
        # Vultr VM's ONLY credential -- scoped further at each assume-role
        # call by an inline session policy. Not a widened trust condition:
        # this grants the ALREADY-TRUSTED bounty-infra pipeline identity
        # permission to assume ONE specific, narrower role, nothing more.
        Sid      = "AllowChainingIntoScannerWriter"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = aws_iam_role.bounty_scanner_s3_writer.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "bounty_infra_attach" {
  role       = aws_iam_role.github_actions_role["bounty-infra"].name
  policy_arn = aws_iam_policy.bounty_infra_policy.arn
}

# ---------------------------------------------------------
# 2. Tri-Loop Dev
# ---------------------------------------------------------
resource "aws_iam_policy" "tri_loop_policy" {
  name        = "glunk-works-tri-loop-workload"
  description = "Permissions for the Tri-Loop application pipeline"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:*", "ecr:*", "ssm:GetParameter", "ssm:GetParameters", "rds:*",
          # Standard IAM workload management capabilities
          "iam:PassRole", "iam:CreateRole", "iam:DeleteRole", "iam:PutRolePolicy",
          "iam:DeleteRolePolicy", "iam:GetRole", "iam:GetRolePolicy",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "tri_loop_attach" {
  role       = aws_iam_role.github_actions_role["tri-loop-dev"].name
  policy_arn = aws_iam_policy.tri_loop_policy.arn
}

# ---------------------------------------------------------
# 3. Bedrock Serverless RAG -- REMOVED, deliberately. Do not re-add here.
# ---------------------------------------------------------
# `aws_iam_policy.bedrock_rag_policy` and its attachment lived here, and the matching entry
# in `var.projects` generated the role they applied to. All three are gone. Two reasons, and
# the second is the one that made it urgent:
#
#   1. The policy did not describe that workload. It granted `lambda:*` and `apigateway:*` --
#      the permission set of a Lambda + API Gateway application. That project provisions an
#      S3 bucket, an OpenSearch Serverless collection, and a Bedrock Knowledge Base. It
#      granted none of what it needed and a great deal of what it did not.
#
#   2. It was a dormant escalation path waiting on a settings change. The role's trust subject
#      names this organization, so today it matches nothing -- that repo is still under a
#      personal namespace. The instant it transfers in, the role becomes assumable, and this
#      policy granted `iam:CreateRole`, `iam:PutRolePolicy`, `iam:AttachRolePolicy` and
#      `iam:PassRole` on `Resource = "*"`, in the account that also holds the bounty-findings
#      archive. No pull request, no IaC diff, no review surface -- just an owner clicking
#      Transfer.
#
# It returns when that repo's identity sprint runs, rebuilt against what the module actually
# declares and constrained by a permissions boundary plus an IAM role-path scope. The
# corrected specification lives in that repo's sprint plan; a bare re-add reopens (2).
#
# The section numbering below is left alone on purpose: renumbering would churn every
# following block and hide this one-block diff.
#
# The same `Resource = "*"` IAM grant is present in the sibling policies below. Deleting
# this one does NOT fix the pattern -- see the linked issue.

# ---------------------------------------------------------
# 4. Resume Optimizer
# ---------------------------------------------------------
resource "aws_iam_policy" "resume_optimizer_policy" {
  name        = "glunk-works-resume-optimizer-workload"
  description = "Permissions for the Resume Optimizer pipeline"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:*", "s3:*",
          # Standard IAM workload management capabilities
          "iam:PassRole", "iam:CreateRole", "iam:DeleteRole", "iam:PutRolePolicy",
          "iam:DeleteRolePolicy", "iam:GetRole", "iam:GetRolePolicy",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "resume_optimizer_attach" {
  role       = aws_iam_role.github_actions_role["resume-optimizer"].name
  policy_arn = aws_iam_policy.resume_optimizer_policy.arn
}

# ---------------------------------------------------------
# 5. Bedrock Serverless RAG (S2-T0c, re-added per ST Task 2b's normative spec)
# ---------------------------------------------------------
# NOT a bare re-add of the F42/F45 grant deleted in section 3 above -- see variables.tf's entry
# comment. Every Resource below is re-derived from what modules/aws-bedrock-rag/ actually
# declares; the verbs are bootstrap/state-backend.tf's MEASURED list (MW-T5/T6's real
# create-then-destroy dry run under CI), not re-guessed. Where a verb genuinely has no
# resource-level permission support in AWS's own IAM implementation -- confirmed 2026-08-10
# against the OpenSearch Serverless and Bedrock service authorization references, not assumed
# -- it stays Resource = "*" on its own dedicated statement, so the residual is auditable
# rather than hidden inside a mixed statement. iam:CreatePolicy (Task 2b(3)'s fix) is
# deliberately absent: this workload creates zero managed policies (inline
# aws_iam_role_policy only, matching ST Task 2b's "must therefore stay inline" note), and
# MW's measured dry run never needed it either -- granting an unneeded verb is not
# least-privilege just because a superseded draft assumed it.

# 5a. Permissions boundary -- the ceiling for every role modules/aws-bedrock-rag/ creates
# (today, just bedrock_kb_role). Written out per Task 2b(5): "too loose and the boundary is
# decorative; too tight and every apply breaks." Not yet referenced by the module -- S2-T1
# threads `permissions_boundary` from environments/ai-lab and points it at this ARN.
resource "aws_iam_policy" "bedrock_rag_boundary" {
  name        = "bedrock-rag-workload-boundary"
  path        = "/bedrock-rag/"
  description = "Permissions boundary for every IAM role modules/aws-bedrock-rag/ creates (S2-T1)."
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowEmbeddingModelInvocation"
        Effect   = "Allow"
        Action   = "bedrock:InvokeModel"
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0"
      },
      {
        Sid    = "AllowSourceBucketRead"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${var.bedrock_rag_source_bucket_name}",
          "arn:aws:s3:::${var.bedrock_rag_source_bucket_name}/*"
        ]
      },
      {
        # bootstrap/ (and this root) cannot see the collection ID generated in
        # environments/ai-lab's state -- region-wildcarded, matching
        # bootstrap/state-backend.tf's aoss:APIAccessAll reasoning.
        Sid      = "AllowCollectionDataPlaneAccess"
        Effect   = "Allow"
        Action   = "aoss:APIAccessAll"
        Resource = "arn:aws:aoss:*:${data.aws_caller_identity.current.account_id}:collection/*"
      },
      {
        # Task 2b(6)/F58 gap b, replicated here per Task 0c's own constraint: putting this in
        # the boundary too means ANY role our CI creates inherits it as a ceiling, regardless
        # of that role's own policy -- not just the two roles it is directly attached to below.
        Sid    = "DenyFindingsDataAndKeyAccess"
        Effect = "Deny"
        Action = ["s3:*", "kms:*"]
        Resource = [
          aws_s3_bucket.findings_bucket.arn,
          "${aws_s3_bucket.findings_bucket.arn}/*",
          aws_kms_key.findings_key.arn
        ]
      }
    ]
  })
}

# 5b. Workload policy -- the CI apply role.
resource "aws_iam_policy" "bedrock_rag_workload_policy" {
  name        = "glunk-works-bedrock-serverless-rag-workload"
  description = "Least-privilege permissions for the bedrock-serverless-rag apply pipeline (S2-T0c)."
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # aws_s3_bucket.bedrock_source's lifecycle. Bucket-level actions only -- CI never
        # reads/writes objects in this bucket, only creates/configures/destroys it.
        Sid    = "ManageSourceBucketLifecycle"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket", "s3:DeleteBucket", "s3:ListBucket",
          "s3:PutBucket*", "s3:GetBucket*",
          "s3:GetEncryptionConfiguration", "s3:PutEncryptionConfiguration",
          "s3:GetLifecycleConfiguration", "s3:GetReplicationConfiguration",
          "s3:GetAccelerateConfiguration"
        ]
        Resource = "arn:aws:s3:::${var.bedrock_rag_source_bucket_name}"
      },
      {
        # aws_iam_role.bedrock_kb_role: read/delete/update/tag. Task 2b(1) fix: S2-T5 needs
        # UpdateAssumeRolePolicy to rewrite the trust policy, and the iam:PermissionsBoundary
        # condition key is NOT evaluated for UpdateAssumeRolePolicy/UpdateRole/TagRole/etc, so
        # Resource-scoping is the only containment available for these -- never "*".
        Sid    = "ReadUpdateTagKBExecutionRole"
        Effect = "Allow"
        Action = [
          "iam:GetRole", "iam:DeleteRole",
          "iam:ListRolePolicies", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:UpdateAssumeRolePolicy", "iam:UpdateRole", "iam:UpdateRoleDescription",
          "iam:TagRole", "iam:UntagRole"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/bedrock-rag/*"
      },
      {
        # The permission-MODIFYING verbs -- the iam:PermissionsBoundary condition key IS
        # evaluated for these, so every role this statement can create or reconfigure must
        # carry OUR boundary, not none and not a different one.
        Sid    = "CreateModifyKBExecutionRoleUnderBoundary"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:PutRolePolicy", "iam:AttachRolePolicy",
          "iam:DetachRolePolicy", "iam:DeleteRolePolicy", "iam:PutRolePermissionsBoundary"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/bedrock-rag/*"
        Condition = {
          StringEquals = {
            "iam:PermissionsBoundary" = aws_iam_policy.bedrock_rag_boundary.arn
          }
        }
      },
      {
        # iam:PassRole -- CreateKnowledgeBase's roleArn parameter. Scoped by BOTH Resource and
        # PassedToService (Task 2b(2) fix: either alone is insufficient); mirrors
        # bootstrap/state-backend.tf's already-scoped statement verbatim -- one of the two
        # "model" statements Task 0c names directly.
        Sid      = "PassKBExecutionRoleToBedrock"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/bedrock-rag/*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "bedrock.amazonaws.com"
          }
        }
      },
      {
        # aws_opensearchserverless_collection.vector_store's lifecycle. AWS's own
        # "administering collections" example policy scopes exactly these three verbs to
        # collection/* -- confirmed 2026-08-10 against the OpenSearch Serverless developer
        # guide's IAM security page.
        Sid      = "ManageCollectionLifecycle"
        Effect   = "Allow"
        Action   = ["aoss:CreateCollection", "aoss:DeleteCollection", "aoss:UpdateCollection"]
        Resource = "arn:aws:aoss:*:${data.aws_caller_identity.current.account_id}:collection/*"
      },
      {
        # The two security policies (encryption, network) and the one data-access policy.
        # AOSS's *SecurityPolicy/*AccessPolicy actions do not support a Resource ARN at all --
        # confirmed against the same guide: CreateAccessPolicy/CreateSecurityPolicy's own
        # official example uses Resource = "*". The only real containment available is the
        # aoss:collection condition key, which inspects the policy document's own Rules[].
        # Resource content -- meaningful here because the collection name is a static literal
        # (local.collection_name in opensearch.tf), not something this root can't see.
        Sid      = "WriteCollectionPoliciesForOurCollection"
        Effect   = "Allow"
        Action   = ["aoss:CreateSecurityPolicy", "aoss:CreateAccessPolicy", "aoss:UpdateAccessPolicy"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aoss:collection" = "bedrock-rag-store"
          }
        }
      },
      {
        # Get/Delete/List *Policy calls address the policy by NAME, not by a collection
        # pattern in the request body, so aoss:collection does not resolve for them -- adding
        # it here would make the condition never match and silently deny every call. Resource
        # = "*" is AWS's own requirement for this group, not a residual we chose.
        Sid    = "ReadDeleteListCollectionPolicies"
        Effect = "Allow"
        Action = [
          "aoss:GetSecurityPolicy", "aoss:DeleteSecurityPolicy", "aoss:ListSecurityPolicies",
          "aoss:GetAccessPolicy", "aoss:DeleteAccessPolicy",
          "aoss:BatchGetCollection", "aoss:ListTagsForResource"
        ]
        Resource = "*"
      },
      {
        # Data-plane grant so create_index.py's local-exec can reach the collection at all --
        # distinct from the data-access-policy Principal above (F55's "two independent
        # grants" gap). Mirrors bootstrap/state-backend.tf's already-scoped statement verbatim
        # -- the second of the two "model" statements Task 0c names directly, including its
        # region-wildcard reasoning (this root cannot see the collection ID either).
        Sid      = "CollectionDataPlaneAccess"
        Effect   = "Allow"
        Action   = "aoss:APIAccessAll"
        Resource = "arn:aws:aoss:*:${data.aws_caller_identity.current.account_id}:collection/*"
      },
      {
        # aws_bedrockagent_knowledge_base.rag_kb / aws_bedrockagent_data_source.rag_source's
        # CREATE calls. Neither resource is addressable before it exists -- confirmed against
        # AWS's own worked example (Bedrock Knowledge Bases permissions guide), whose
        # CreateKnowledgeBase statement is Resource = "*" for the identical reason.
        # CreateDataSource has no equivalent worked example; grouped here as the conservative
        # read (a Create action, same unaddressable-before-creation shape) rather than assumed
        # scopeable -- INFERRED, not measured against a real 403.
        Sid      = "CreateKnowledgeBaseAndDataSource"
        Effect   = "Allow"
        Action   = ["bedrock:CreateKnowledgeBase", "bedrock:CreateDataSource"]
        Resource = "*"
      },
      {
        # Once created, both nest under the knowledge-base ARN -- AWS's worked example scopes
        # GetKnowledgeBase/DeleteKnowledgeBase/ListTagsForResource to knowledge-base/{{*}}
        # exactly this way; DataSource's Get/Delete are grouped here on the same
        # parent-resource reasoning (data sources have no independent top-level ARN).
        Sid    = "ReadDeleteKnowledgeBaseAndDataSource"
        Effect = "Allow"
        Action = [
          "bedrock:GetKnowledgeBase", "bedrock:DeleteKnowledgeBase",
          "bedrock:GetDataSource", "bedrock:DeleteDataSource", "bedrock:ListTagsForResource"
        ]
        Resource = "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:knowledge-base/*"
      },
      {
        # Mirrors bootstrap/state-backend.tf's already-scoped budgets statement verbatim --
        # the third of the "model" statements Task 0c names directly.
        Sid      = "ManageCostBudget"
        Effect   = "Allow"
        Action   = ["budgets:ModifyBudget", "budgets:ViewBudget", "budgets:ListTagsForResource"]
        Resource = "arn:aws:budgets::${data.aws_caller_identity.current.account_id}:budget/bedrock-serverless-rag-ai-lab-monthly"
      },
      {
        # BR-D22 state-encryption key access (Task 0c step 1b's decision) -- both this and the
        # plan role's mirror in plan_roles.tf get all three verbs, not an asymmetric
        # read/write split, per that step's own text.
        Sid      = "StateEncryptionKeyAccess"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = aws_kms_key.state_key.arn
      },
      {
        # This workload uses inline role policies only (aws_iam_role_policy, never
        # aws_iam_policy) -- ST Task 2b's own recorded note: a blanket Deny here means it can
        # never accidentally start managing a customer-managed policy version, which is the
        # one action a permissions boundary's iam:PermissionsBoundary condition key cannot
        # constrain.
        Sid      = "DenyManagedPolicyVersionUpdates"
        Effect   = "Deny"
        Action   = "iam:CreatePolicyVersion"
        Resource = "*"
      },
      {
        # Protects the boundary FROM the role it constrains -- without this, the CI role could
        # edit or delete the very policy that is supposed to cap what it can create.
        Sid      = "DenyModifyingOwnBoundary"
        Effect   = "Deny"
        Action   = "iam:*"
        Resource = aws_iam_policy.bedrock_rag_boundary.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "bedrock_rag_workload_attach" {
  role       = aws_iam_role.github_actions_role["bedrock-serverless-rag"].name
  policy_arn = aws_iam_policy.bedrock_rag_workload_policy.arn
}

# 5c. Findings Deny (F58 gap b) -- extended to kms: as well as s3:, per Task 2b(6). A new,
# standalone policy: bounty_infra_plan_policy's own inline Deny is bounty-infra's to fix
# (glunk-works/global-bootstrap#6, gap (a)), not touched here. Attached to BOTH
# bedrock-serverless-rag roles -- the apply-role attachment is below; the plan-role attachment
# lives in plan_roles.tf alongside everything else about that identity.
resource "aws_iam_policy" "bedrock_rag_findings_deny" {
  name        = "bedrock-serverless-rag-deny-findings-access"
  description = "Deny s3: and kms: on the shared findings bucket/key for both bedrock-serverless-rag roles (F58 gap b)."
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyFindingsDataAndKeyAccess"
        Effect = "Deny"
        Action = ["s3:*", "kms:*"]
        Resource = [
          aws_s3_bucket.findings_bucket.arn,
          "${aws_s3_bucket.findings_bucket.arn}/*",
          aws_kms_key.findings_key.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "bedrock_rag_findings_deny_attach" {
  role       = aws_iam_role.github_actions_role["bedrock-serverless-rag"].name
  policy_arn = aws_iam_policy.bedrock_rag_findings_deny.arn
}