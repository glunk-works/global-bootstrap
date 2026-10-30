# State lives at bootstrap/global-bootstrap.tfstate regardless of where this module sits in
# the repo: the S3 backend locates state by bucket and key, not by path. The module moved from
# the repo root into infra/ in #35 with no state change (`tofu -chdir=infra plan`: No changes).
terraform {
  # Write-only arguments (value_wo, bounty_infra_secrets.tf) need OpenTofu 1.11; an older
  # version must fail here rather than run.
  required_version = ">= 1.11.0"

  backend "s3" {
    bucket         = "glunk-works-tofu-state-00042"
    key            = "bootstrap/global-bootstrap.tfstate"
    region         = "us-east-1"
    dynamodb_table = "global-tofu-lock"
    encrypt        = true
  }
}