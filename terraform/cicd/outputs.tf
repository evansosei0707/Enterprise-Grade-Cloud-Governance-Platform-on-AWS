# -----------------------------------------------------------------------------
# CI/CD Pipeline Module - Outputs
# -----------------------------------------------------------------------------

output "pipeline_arn" {
  description = "ARN of the CodePipeline"
  value       = aws_codepipeline.governance.arn
}

output "pipeline_name" {
  description = "Name of the CodePipeline"
  value       = aws_codepipeline.governance.name
}

output "github_connection_arn" {
  description = "ARN of the GitHub CodeStar connection (requires manual authorization)"
  value       = aws_codestarconnections_connection.github.arn
}

output "github_connection_status" {
  description = "Status of the GitHub connection"
  value       = aws_codestarconnections_connection.github.connection_status
}

output "artifacts_bucket" {
  description = "S3 bucket for pipeline artifacts"
  value       = aws_s3_bucket.artifacts.bucket
}
