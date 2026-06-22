variable "aws_region" {
  description = "The AWS region to deploy the bootstrap infrastructure."
  type        = string
  default     = "us-east-1"
}

variable "bootstrap_bucket_name" {
  description = "The globally unique name for the S3 state bucket."
  type        = string
}

variable "github_organization" {
  description = "Your GitHub organization handle (e.g., glunk-works)."
  type        = string
}

variable "projects" {
  description = "Map of all projects and their strictly permitted AWS actions."
  type = map(object({
    repo_name       = string
    allowed_actions = list(string)
  }))
  default = {
    "tri-loop" = {
      repo_name       = "tri-loop-dev"
      allowed_actions = [
        "ecs:*",
        "ecr:*",
        "ssm:GetParameter",
        "ssm:GetParameters",
        "rds:*"
      ]
    }
    "bedrock-rag" = {
      repo_name       = "bedrock-serverless-rag"
      allowed_actions = [
        "lambda:*",
        "apigateway:*",
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ]
    }
    "bounty-infra" = {
      repo_name       = "bounty-infra"
      allowed_actions = [
        "ec2:*",
        "vpc:*",
        "route53:*"
      ]
    }
    "resume-optimizer" = {
      repo_name       = "resume-optimizer"
      allowed_actions = [
        "lambda:*",
        "s3:*"
      ]
    }
  }
}