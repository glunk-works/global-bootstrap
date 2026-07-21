variable "aws_region" {
  description = "The AWS region to deploy the bootstrap infrastructure."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "The SSO profile to use for the bootstrap infrastructure."
  type        = string
  default     = "admin-sso"
}

variable "bootstrap_bucket_name" {
  description = "The globally unique name for the S3 state bucket."
  type        = string
}

variable "findings_bucket_name" {
  description = "The globally unique name for the centralized bug bounty findings bucket."
  type        = string
  default     = "glunk-works-bounty-findings-archive"
}

variable "github_organization" {
  description = "Your GitHub organization handle (e.g., glunk-works)."
  type        = string
}

variable "projects" {
  description = "Map of all projects integrating with the centralized state."
  type = map(object({
    repo_name = string
    # Opt in to a second, READ-ONLY role for `tofu plan` on pull requests
    # (see plan_roles.tf). Off by default: a project without plan-on-PR should
    # not have an extra assumable identity sitting around.
    plan_role = optional(bool, false)

    # Extra OIDC subject suffixes the apply role will also trust, appended to
    # "repo:<org>/<repo>:". Needed because a job referencing a GitHub
    # Environment presents `environment:<name>` INSTEAD OF the branch subject.
    extra_oidc_subjects = optional(list(string), [])
  }))
  default = {
    "tri-loop-dev"           = { repo_name = "tri-loop-dev" }
    "bedrock-serverless-rag" = { repo_name = "bedrock-serverless-rag" }
    "resume-optimizer"       = { repo_name = "resume-optimizer" }
    "bounty-infra" = {
      repo_name = "bounty-infra"
      plan_role = true
      # deploy-infra.yml's apply job runs `environment: production`.
      extra_oidc_subjects = ["environment:production"]
    }
  }
}