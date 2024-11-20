# S3 Bucket
resource "aws_s3_bucket" "claims_bucket" {
  bucket        = "medical-claims-data-bucket"
  force_destroy = true

  tags = {
    Name = "MedicalClaimsBucket"
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "claims_bucket_public_access_block" {
  bucket                  = aws_s3_bucket.claims_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# S3 Bucket Policy
resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.claims_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.claims_bucket.arn}/*"
      }
    ]
  })
}

# DynamoDB Table
resource "aws_dynamodb_table" "claims_table" {
  name           = "MedicalClaimsTable"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "ClaimID"

  attribute {
    name = "ClaimID"
    type = "S"
  }

  tags = {
    Name = "MedicalClaimsTable"
  }
}

# IAM Policy for Lambda
resource "aws_iam_policy" "lambda_policy" {
  name        = "lambda_s3_dynamodb_policy"
  description = "Allows Lambda to access S3 and DynamoDB"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["s3:GetObject", "s3:ListBucket"],
        Effect   = "Allow",
        Resource = [
          aws_s3_bucket.claims_bucket.arn,
          "${aws_s3_bucket.claims_bucket.arn}/*"
        ]
      },
      {
        Action   = ["dynamodb:PutItem", "dynamodb:BatchWriteItem"],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.claims_table.arn
      },
      {
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Attach IAM Policy to Role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Lambda Function
resource "aws_lambda_function" "s3_to_dynamodb" {
  s3_bucket        = aws_s3_bucket.lambda_deployment_bucket.bucket
  s3_key           = aws_s3_object.lambda_deployment_package.key
  function_name    = "s3_to_dynamodb_function"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = filebase64sha256("lambda_function.zip") # Ensures updates trigger deployment
  environment {
    variables = {
      S3_BUCKET_NAME       = aws_s3_bucket.claims_bucket.id
      DYNAMODB_TABLE_NAME  = aws_dynamodb_table.claims_table.name
    }
  }
}

# S3 Bucket Notification for Lambda
resource "aws_s3_bucket_notification" "s3_notification" {
  bucket = aws_s3_bucket.claims_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_to_dynamodb.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "sample_data/" # Only trigger on objects in this prefix
  }

  depends_on = [aws_lambda_permission.allow_s3_invocation]
}

# Lambda Permission for S3
resource "aws_lambda_permission" "allow_s3_invocation" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_to_dynamodb.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.claims_bucket.arn
}


# S3 Bucket for Lambda deployment package
resource "aws_s3_bucket" "lambda_deployment_bucket" {
  bucket = "lambda-deployment-bucket-medical101"
  force_destroy = true
}

# Upload Lambda deployment package to S3
resource "aws_s3_object" "lambda_deployment_package" {
  bucket = aws_s3_bucket.lambda_deployment_bucket.bucket
  key    = "lambda_function.zip"
  source = "lambda_function.zip"
}

# Outputs
output "s3_bucket_name" {
  value = aws_s3_bucket.claims_bucket.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.claims_table.name
}

