output "ai_assistant_function_url" {
  description = "Public URL of the ai-assistant Lambda function."
  value       = aws_lambda_function_url.ai_assistant.function_url
}

output "document_store_bucket" {
  description = "Name of the S3 bucket holding the document-store, machinery-mirror and partner-connector data sources."
  value       = aws_s3_bucket.documents.bucket
}

output "machinery_docs_efs_id" {
  description = "ID of the EFS file system representing the FSx complex machinery and processes documentation data source."
  value       = aws_efs_file_system.machinery_docs.id
}

output "maintenance_engineers_group" {
  description = "Name of the IAM group (SSO group stand-in) with full access to all data sources."
  value       = aws_iam_group.maintenance_engineers.name
}

output "general_staff_group" {
  description = "Name of the IAM group (SSO group stand-in) restricted to general documentation only."
  value       = aws_iam_group.general_staff.name
}
