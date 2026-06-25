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
          "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:DescribeSubnets", "ec2:ModifySubnetAttribute",
          "ec2:CreateInternetGateway", "ec2:AttachInternetGateway", "ec2:DetachInternetGateway", "ec2:DeleteInternetGateway", "ec2:DescribeInternetGateways",
          "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:DescribeRouteTables", "ec2:CreateRoute",
          "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
          "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup", "ec2:DescribeSecurityGroups",
          "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupEgress",
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
          "iam:GetPolicyVersion", "iam:ListPolicyVersions", "iam:ListInstanceProfilesForRole"
        ]
        Resource = "*"
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
# 3. Bedrock Serverless RAG
# ---------------------------------------------------------
resource "aws_iam_policy" "bedrock_rag_policy" {
  name        = "glunk-works-bedrock-rag-workload"
  description = "Permissions for the Bedrock RAG AI pipeline"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:*", "apigateway:*", "bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream",
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

resource "aws_iam_role_policy_attachment" "bedrock_rag_attach" {
  role       = aws_iam_role.github_actions_role["bedrock-serverless-rag"].name
  policy_arn = aws_iam_policy.bedrock_rag_policy.arn
}

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