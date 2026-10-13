variable "project_name" {
  description = "Project name used as prefix for all resources."
  type        = string
  default     = "floci-ai-assistant"
}

variable "aws_region" {
  description = "AWS region (simulated by floci)."
  type        = string
  default     = "us-east-1"
}

variable "document_store_bucket_name" {
  description = "Name of the S3 bucket holding the documents the AI assistant searches, organized in per-data-source prefixes (general/, machinery/, partner-connector/)."
  type        = string
  default     = "document-store"
}

variable "machinery_docs_efs_name" {
  description = "Name of the EFS file system representing the complex machinery and processes documentation data source."
  type        = string
  default     = "machinery-docs"
}

variable "generation_model_id" {
  description = "Bedrock foundation model id used to generate the assistant's permission-filtered answers."
  type        = string
  default     = "anthropic.claude-3-haiku-20240307-v1:0"
}

variable "maintenance_engineers_group_name" {
  description = "IAM group representing SSO users in the maintenance-engineers permission group (full access to all data sources)."
  type        = string
  default     = "maintenance-engineers"
}

variable "general_staff_group_name" {
  description = "IAM group representing SSO users in the general-staff permission group (access to general documentation only)."
  type        = string
  default     = "general-staff"
}
