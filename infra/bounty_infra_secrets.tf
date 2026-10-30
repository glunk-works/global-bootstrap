# ---------------------------------------------------------
# bounty-infra's pipeline secrets (SSM Parameter Store, GB-D8)
# ---------------------------------------------------------
# The parameters are declared here; their values never are. Each value is a write-only
# argument (value_wo): OpenTofu sends it to AWS and never stores it in state or a plan.
# The read grant is on the bounty-infra apply role only (project_policies.tf).
#
# Supplying the values: the variables have no default, so every host plan and apply of this
# module asks for all three. Set them from a prompt that does not echo, never from a tfvars
# file or a CI variable, for example in PowerShell:
#   $s = Read-Host -AsSecureString 'bounty_infra_vultr_api_key'
#   $env:TF_VAR_bounty_infra_vultr_api_key = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
#   ... (the same for the other two) ...
#   tofu apply
#   Remove-Item Env:TF_VAR_bounty_infra_*; Remove-Variable s
#
# A value is only rewritten when its value_wo_version changes: bump it on rotation. A null
# value_wo is not an option (the provider refuses the plan), which is why there is no
# default. CI is unaffected: validate.yml runs fmt and validate only, which need no values.
#
# Never declare one of these through `value`, never use a placeholder `value` with
# lifecycle { ignore_changes = [value] }, and never `tofu import` one (delete and recreate
# instead): in each case the provider reads the parameter back on refresh, and the real
# value would land in state.

data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"
}

variable "bounty_infra_vultr_api_key" {
  description = "bounty-infra's Vultr API key, written to /bounty-infra/vultr_api_key. Write-only: never stored in state."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "bounty_infra_operator_ssh_key" {
  description = "bounty-infra's operator SSH key, written to /bounty-infra/operator_ssh_key. Write-only: never stored in state."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "bounty_infra_operator_ip" {
  description = "bounty-infra's operator IP, written to /bounty-infra/operator_ip. Write-only: never stored in state."
  type        = string
  sensitive   = true
  ephemeral   = true
}

resource "aws_ssm_parameter" "bounty_infra_vultr_api_key" {
  name             = "/bounty-infra/vultr_api_key"
  type             = "SecureString"
  value_wo         = var.bounty_infra_vultr_api_key
  value_wo_version = 1
}

resource "aws_ssm_parameter" "bounty_infra_operator_ssh_key" {
  name             = "/bounty-infra/operator_ssh_key"
  type             = "SecureString"
  value_wo         = var.bounty_infra_operator_ssh_key
  value_wo_version = 1
}

resource "aws_ssm_parameter" "bounty_infra_operator_ip" {
  name             = "/bounty-infra/operator_ip"
  type             = "SecureString"
  value_wo         = var.bounty_infra_operator_ip
  value_wo_version = 1
}
