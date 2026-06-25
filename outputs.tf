output "state_bucket_name" {
  description = "The name of the S3 bucket used for OpenTofu state."
  value       = aws_s3_bucket.state_bucket.bucket
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table used for state locking."
  value       = aws_dynamodb_table.state_locks.name
}

output "github_actions_role_arns" {
  description = "A map of IAM Role ARNs to be used in the GitHub Actions workflows for each project."
  value       = { for k, v in aws_iam_role.github_actions_role : k => v.arn }
}

output "findings_bucket_name" {
  description = "The name of the centralized S3 findings archive."
  value       = aws_s3_bucket.findings_bucket.bucket
}

output "findings_kms_key_arn" {
  description = "The ARN of the KMS key used to encrypt the findings bucket."
  value       = aws_kms_key.findings_key.arn
}