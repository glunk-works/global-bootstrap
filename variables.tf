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

    # Extra OIDC subject suffixes the PLAN role will also trust, appended to
    # the same computed prefix. The plan role otherwise trusts only
    # ":pull_request", so a project whose plan-on-push job needs to run (e.g.
    # a push-triggered tofu-plan-main) must list that context here. Declared
    # here; NOT YET consumed — plan_roles.tf still hardcodes ":pull_request"
    # until that is wired up separately (BR-D27, F56 gap a).
    extra_plan_oidc_subjects = optional(list(string), [])

    # Override for the computed subject prefix ("repo:<org>/<repo_name>").
    # An org-owned repo can present an ID-QUALIFIED subject instead of the
    # plain form (repo:<owner>@<org_id>/<repo>@<repo_id>:<context>), which the
    # plain computed prefix will never match — this lets a project supply its
    # measured prefix instead. null (the default) preserves today's computed
    # plain form for every existing project (BR-D27).
    oidc_subject_prefix = optional(string, null)
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

    # Re-added per S2-T0c, per ST Task 2b's normative spec. NOT a bare re-add of the F45/F42
    # entry removed above -- this one carries oidc_subject_prefix (the repo is org-owned and
    # presents an ID-qualified subject, BR-D27), a permissions boundary + role-path scope
    # (project_policies.tf), and a findings Deny extended to kms: as well as s3: (F58 gap b).
    "bedrock-serverless-rag" = {
      repo_name = "bedrock-serverless-rag"
      plan_role = true
      # The repo transferred into this org (BR-D13) and presents
      # repo:<owner>@<org_id>/<repo>@<repo_id>:<context>, which the plain computed prefix
      # never matches -- ids read with `gh api repos/glunk-works/bedrock-serverless-rag
      # --jq '.id, .owner.id'`. Not BR-D4 restricted: a public org name, a public repo name,
      # and two GitHub numeric ids.
      oidc_subject_prefix = "repo:glunk-works@295891085/bedrock-serverless-rag@1253604712"
      # deploy.yml's apply job runs `environment: production` (S1a-T5).
      extra_oidc_subjects = ["environment:production"]
      # Without this, deploy.yml's push-triggered tofu-plan-main can never assume the plan
      # role at all (F56 gap a) -- it is a READ-ONLY role, so trusting the `main` ref costs
      # nothing that `:pull_request` did not already cost.
      extra_plan_oidc_subjects = ["ref:refs/heads/main"]
    }
  }

  # Mirrors bootstrap/oidc-setup.tf's validations for github_oidc_subject_prefixes.
  # Load-bearing in THIS PR specifically: this is the one window in which
  # oidc_subject_prefix exists while both roles' operators are still StringLike,
  # where '*' matches ':' too.
  validation {
    condition = alltrue([
      for k, v in var.projects :
      v.oidc_subject_prefix == null || startswith(v.oidc_subject_prefix, "repo:")
    ])
    error_message = "A project's oidc_subject_prefix, if set, must start with 'repo:' — a bare owner/repo would not match any GitHub OIDC subject."
  }

  validation {
    condition = alltrue([
      for k, v in var.projects :
      v.oidc_subject_prefix == null || (!strcontains(v.oidc_subject_prefix, "*") && !strcontains(v.oidc_subject_prefix, "?"))
    ])
    error_message = "A project's oidc_subject_prefix may not contain '*' or '?': in IAM StringLike both are wildcards that match ':' too, so one would widen that project's trust policy far beyond the intended repository."
  }
}

# bedrock-serverless-rag's S3 source bucket name -- needed to scope project_policies.tf's and
# plan_roles.tf's S3 statements to this one bucket instead of Resource = "*", which is exactly
# the escape S2-T0c exists to close (an unscoped s3:DeleteBucket reaches THIS bucket, the org
# state bucket above, and the findings bucket). Not a `var.projects` map field: that map's
# whole value is a COMMITTED default, and this value is BR-D4 restricted (a bucket name on a
# public repo is free reconnaissance) -- environments/ai-lab's own `data_source_bucket_name`
# variable has no default for the identical reason. No default here either; set via
# TF_VAR_bedrock_rag_source_bucket_name at apply time, same as that repo's own convention.
variable "bedrock_rag_source_bucket_name" {
  description = "bedrock-serverless-rag's S3 source bucket name (environments/ai-lab's data_source_bucket_name). Restricted, not secret (BR-D4) -- set via TF_VAR_, never committed."
  type        = string

  # Same hazard oidc_subject_prefix's own validation exists for, three lines up in this file:
  # this string is spliced directly into an ARN that project_policies.tf grants
  # s3:PutBucket*/DeleteBucket on. A value of "*" (or containing one) would render
  # arn:aws:s3:::*, reopening exactly the account-wide S3 reach this variable exists to close
  # -- including onto the org state bucket and the findings bucket below.
  validation {
    condition     = !strcontains(var.bedrock_rag_source_bucket_name, "*") && !strcontains(var.bedrock_rag_source_bucket_name, "?")
    error_message = "bedrock_rag_source_bucket_name may not contain '*' or '?' -- both are ARN/glob wildcards and this value is spliced directly into an arn:aws:s3::: Resource."
  }

  validation {
    condition     = var.bedrock_rag_source_bucket_name != var.bootstrap_bucket_name && var.bedrock_rag_source_bucket_name != var.findings_bucket_name
    error_message = "bedrock_rag_source_bucket_name must not equal the org state bucket or the findings bucket -- a collision (typo or copy-paste) would scope bedrock-serverless-rag's S3 bucket-lifecycle grant onto one of those shared resources instead."
  }
}