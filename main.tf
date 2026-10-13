# ─── S3: document store (one bucket, one prefix per data source) ────────────
#
# "Data sources" in the architecture (S3 document bucket, FSx machinery
# documentation, third-party enterprise app/document repository connector)
# are modeled as per-source prefixes inside a single searchable bucket:
#   general/           -- the S3 "document bucket" data source itself
#   machinery/          -- content mirrored from the FSx data source (see note below)
#   partner-connector/  -- content synced in by the third-party connector data source

resource "aws_s3_bucket" "documents" {
  bucket = "${local.name_prefix}-${var.document_store_bucket_name}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.document_store_bucket_name}"
  })
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket = aws_s3_bucket.documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─── FSx data source: "complex machinery and processes documentation" ───────
#
# Floci (our local AWS emulator) does not support Amazon FSx, nor the VPC
# networking (subnets, security groups, ENIs) a Lambda function would need in
# order to mount an FSx file system. To keep this scaffold applyable locally
# while still representing the FSx data source in the IaC, we provision an
# Amazon EFS file system instead (a conceptually equivalent managed file
# storage service whose bare resource needs no VPC to create). The actual
# content the `ai-assistant` Lambda searches for this data source is kept in
# the `machinery/` prefix of the documents bucket above, mirroring how an
# FSx-to-S3 sync/connector would expose indexed FSx content to a search layer
# in a real deployment.

resource "aws_efs_file_system" "machinery_docs" {
  creation_token = "${local.name_prefix}-${var.machinery_docs_efs_name}"
  encrypted      = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.machinery_docs_efs_name}"
  })
}

# ─── Manage access and single sign-on: IAM groups representing SSO groups ───
#
# Floci/Terraform cannot provision a real IAM Identity Center (AWS SSO)
# instance -- it must already exist and be enabled through the AWS console,
# and the Terraform `aws_ssoadmin_*`/`aws_identitystore_*` resources only
# manage permission sets and assignments against a pre-existing instance.
# We represent the "Manage access and single sign-on" component with plain
# IAM groups + users instead: the `ai-assistant` Lambda resolves the caller's
# group membership through `iam:ListGroupsForUser`, exactly as it would call
# the SSO identity store to resolve a federated user's groups in production.

resource "aws_iam_group" "maintenance_engineers" {
  name = "${local.name_prefix}-${var.maintenance_engineers_group_name}"
}

resource "aws_iam_group" "general_staff" {
  name = "${local.name_prefix}-${var.general_staff_group_name}"
}

resource "aws_iam_group_policy" "maintenance_engineers_access" {
  name  = "${local.name_prefix}-maintenance-engineers-access"
  group = aws_iam_group.maintenance_engineers.name

  # Full access: general docs, FSx-mirrored machinery docs and the
  # third-party connector's synced content.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.documents.arn, "${aws_s3_bucket.documents.arn}/*"]
    }]
  })
}

resource "aws_iam_group_policy" "general_staff_access" {
  name  = "${local.name_prefix}-general-staff-access"
  group = aws_iam_group.general_staff.name

  # Restricted access: only the general/ data source prefix.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [
        aws_s3_bucket.documents.arn,
        "${aws_s3_bucket.documents.arn}/general/*",
      ]
      Condition = {
        StringLike = { "s3:prefix" = ["general/*"] }
      }
    }]
  })
}

resource "aws_iam_user" "jane_maintenance_engineer" {
  name = "${local.name_prefix}-jane"

  tags = merge(local.common_tags, {
    Role = "maintenance-engineer"
  })
}

resource "aws_iam_user_group_membership" "jane_groups" {
  user   = aws_iam_user.jane_maintenance_engineer.name
  groups = [aws_iam_group.maintenance_engineers.name]
}

resource "aws_iam_user" "bob_general_staff" {
  name = "${local.name_prefix}-bob"

  tags = merge(local.common_tags, {
    Role = "general-staff"
  })
}

resource "aws_iam_user_group_membership" "bob_groups" {
  user   = aws_iam_user.bob_general_staff.name
  groups = [aws_iam_group.general_staff.name]
}

# ─── IAM role assumed by the ai-assistant Lambda function ───────────────────

resource "aws_iam_role" "lambda_exec" {
  name = "${local.name_prefix}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_documents_read" {
  name = "${local.name_prefix}-lambda-documents-read"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.documents.arn, "${aws_s3_bucket.documents.arn}/*"]
    }]
  })
}

resource "aws_iam_role_policy" "lambda_resolve_identity" {
  name = "${local.name_prefix}-lambda-resolve-identity"
  role = aws_iam_role.lambda_exec.id

  # Lets the assistant call "Manage access and single sign-on" to resolve the
  # caller's group membership before filtering results.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["iam:ListGroupsForUser", "iam:GetUser"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_bedrock" {
  name = "${local.name_prefix}-lambda-bedrock"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel"]
      Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.generation_model_id}"
    }]
  })
}

# ─── Lambda: ai-assistant ────────────────────────────────────────────────────

resource "null_resource" "ai_assistant_package" {
  triggers = {
    handler_sha = filesha256("${path.module}/src/lambda/ai_assistant/handler.py")
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/build_lambda_package.sh ${path.module} ai_assistant"
  }
}

data "archive_file" "ai_assistant_zip" {
  type        = "zip"
  source_file = "${path.module}/src/lambda/ai_assistant/handler.py"
  output_path = "${path.module}/.build/ai_assistant.zip"

  depends_on = [null_resource.ai_assistant_package]
}

resource "aws_lambda_function" "ai_assistant" {
  function_name = "${local.name_prefix}-ai-assistant"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.ai_assistant_zip.output_path
  source_code_hash = data.archive_file.ai_assistant_zip.output_base64sha256

  environment {
    variables = {
      REGION              = var.aws_region
      DOCUMENT_BUCKET     = aws_s3_bucket.documents.bucket
      GENERATION_MODEL_ID = var.generation_model_id
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ai-assistant"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.lambda_documents_read,
    aws_iam_role_policy.lambda_resolve_identity,
    aws_iam_role_policy.lambda_bedrock,
  ]
}

resource "aws_lambda_function_url" "ai_assistant" {
  function_name      = aws_lambda_function.ai_assistant.function_name
  authorization_type = "NONE"
}
