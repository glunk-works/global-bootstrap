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
    "tri-loop-dev"     = { repo_name = "tri-loop-dev" }
    "resume-optimizer" = { repo_name = "resume-optimizer" }

    # NOTE: "bedrock-serverless-rag" is deliberately ABSENT -- do not re-add it here.
    #
    # That repo is about to transfer into this organization. Its entry generated a CI role
    # trusting `repo:glunk-works/bedrock-serverless-rag:...`, which matches nothing while the
    # repo still lives under a personal namespace -- so the role sits inert. The moment the
    # transfer completes it becomes assumable, and the policy attached to it granted
    # `iam:CreateRole`/`PutRolePolicy`/`AttachRolePolicy`/`PassRole` on `Resource = "*"` in
    # the account that also holds the bounty-findings archive. A repository-settings change,
    # with no IaC diff anywhere, would have created a new path to account administrator.
    #
    # Removing the entry closes that off entirely, and costs nothing: the repo authenticates
    # through its own deployment role today and does not use this one.
    #
    # It comes back -- WITH a permissions boundary, an IAM role-path scope, and a findings
    # `Deny` covering `kms:` as well as `s3:` -- when that repo's identity sprint runs. The
    # corrected specification is written down there; re-adding a bare entry in the meantime
    # reopens exactly what this deletion closed.
    "bounty-infra" = {
      repo_name = "bounty-infra"
      plan_role = true
      # deploy-infra.yml's apply job runs `environment: production`.
      extra_oidc_subjects = ["environment:production"]
    }
  }
}