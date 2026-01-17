# -----------------------------------------------------------------------------
# CI/CD Pipeline Module - Main Configuration
# -----------------------------------------------------------------------------
# AWS CodePipeline for automated deployment of the governance platform.
# Uses GitHub as source, CodeBuild for terraform operations, and manual approval.
# -----------------------------------------------------------------------------

# =============================================================================
# CodeStar Connection to GitHub
# =============================================================================

resource "aws_codestarconnections_connection" "github" {
  name          = "${var.name_prefix}-github"
  provider_type = "GitHub"

  tags = var.tags
}

# =============================================================================
# Artifact Bucket
# =============================================================================

resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.name_prefix}-pipeline-artifacts"
  
  tags = var.tags
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# =============================================================================
# CodeBuild Projects
# =============================================================================

# Validate Project - terraform fmt, validate, tflint
resource "aws_codebuild_project" "validate" {
  name         = "${var.name_prefix}-validate"
  description  = "Validates Terraform code (fmt, validate)"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "hashicorp/terraform:1.14"
    type         = "LINUX_CONTAINER"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = <<-EOF
      version: 0.2
      phases:
        install:
          commands:
            - echo "Terraform version:"
            - terraform version
        build:
          commands:
            - echo "Checking formatting..."
            - terraform fmt -check -recursive
            - echo "Validating configuration..."
            - cd terraform/environments/governance
            - terraform init -backend=false
            - terraform validate
      artifacts:
        files:
          - '**/*'
    EOF
  }

  tags = var.tags
}

# Plan Project - terraform plan for each environment
resource "aws_codebuild_project" "plan" {
  name         = "${var.name_prefix}-plan"
  description  = "Runs terraform plan for governance environment"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "hashicorp/terraform:1.14"
    type         = "LINUX_CONTAINER"

    environment_variable {
      name  = "TF_STATE_BUCKET"
      value = var.tf_state_bucket
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = <<-EOF
      version: 0.2
      phases:
        install:
          commands:
            - terraform version
        pre_build:
          commands:
            - echo "Downloading terraform.tfvars from S3..."
            - aws s3 cp s3://$TF_STATE_BUCKET/config/governance.tfvars terraform/environments/governance/terraform.tfvars
        build:
          commands:
            - cd terraform/environments/governance
            - terraform init
            - terraform plan -out=tfplan -no-color | tee plan_output.txt
      artifacts:
        files:
          - terraform/environments/governance/tfplan
          - terraform/environments/governance/plan_output.txt
    EOF
  }

  tags = var.tags
}

# Apply Project - terraform apply
resource "aws_codebuild_project" "apply" {
  name         = "${var.name_prefix}-apply"
  description  = "Applies terraform plan for governance environment"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "hashicorp/terraform:1.14"
    type         = "LINUX_CONTAINER"

    environment_variable {
      name  = "TF_STATE_BUCKET"
      value = var.tf_state_bucket
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = <<-EOF
      version: 0.2
      phases:
        pre_build:
          commands:
            - echo "Downloading terraform.tfvars from S3..."
            - aws s3 cp s3://$TF_STATE_BUCKET/config/governance.tfvars terraform/environments/governance/terraform.tfvars
        build:
          commands:
            - cd terraform/environments/governance
            - terraform init
            - terraform apply -auto-approve tfplan
    EOF
  }

  tags = var.tags
}

# =============================================================================
# CodePipeline
# =============================================================================

resource "aws_codepipeline" "governance" {
  name     = "${var.name_prefix}-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  # Stage 1: Source from GitHub
  stage {
    name = "Source"

    action {
      name             = "GitHub_Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = replace(replace(var.github_repo, "https://github.com/", ""), ".git", "")
        BranchName       = var.github_branch
      }
    }
  }

  # Stage 2: Validate
  stage {
    name = "Validate"

    action {
      name             = "Terraform_Validate"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["validated_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.validate.name
      }
    }
  }

  # Stage 3: Plan
  stage {
    name = "Plan"

    action {
      name             = "Terraform_Plan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["validated_output"]
      output_artifacts = ["plan_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.plan.name
      }
    }
  }

  # Stage 4: Manual Approval
  stage {
    name = "Approval"

    action {
      name     = "Manual_Approval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        NotificationArn = var.notification_topic_arn
        CustomData      = "Review the Terraform plan and approve to deploy."
      }
    }
  }

  # Stage 5: Apply
  stage {
    name = "Deploy"

    action {
      name            = "Terraform_Apply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["plan_output"]
      version         = "1"

      configuration = {
        ProjectName = aws_codebuild_project.apply.name
      }
    }
  }

  tags = var.tags
}

# =============================================================================
# IAM Roles
# =============================================================================

# CodePipeline Role
resource "aws_iam_role" "codepipeline" {
  name = "${var.name_prefix}-pipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "codepipeline.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "codepipeline" {
  name = "${var.name_prefix}-pipeline-policy"
  role = aws_iam_role.codepipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:GetBucketVersioning"
        ]
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:StartBuild",
          "codebuild:BatchGetBuilds"
        ]
        Resource = [
          aws_codebuild_project.validate.arn,
          aws_codebuild_project.plan.arn,
          aws_codebuild_project.apply.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codestar-connections:UseConnection"
        ]
        Resource = aws_codestarconnections_connection.github.arn
      },
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = var.notification_topic_arn
      }
    ]
  })
}

# CodeBuild Role
resource "aws_iam_role" "codebuild" {
  name = "${var.name_prefix}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "codebuild.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "codebuild" {
  name = "${var.name_prefix}-codebuild-policy"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.artifacts.arn}/*",
          "arn:aws:s3:::${var.tf_state_bucket}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "arn:aws:s3:::${var.tf_state_bucket}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:*:*:table/*-terraform-locks"
      },
      {
        # Terraform needs broad permissions to manage resources
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = "us-east-1"
          }
        }
      }
    ]
  })
}
