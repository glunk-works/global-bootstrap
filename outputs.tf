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