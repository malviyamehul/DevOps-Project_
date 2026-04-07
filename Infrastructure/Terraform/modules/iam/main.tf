# modules/iam/main.tf
# IRSA = IAM Roles for Service Accounts
# Each pod assumes an IAM role via the OIDC provider — zero static credentials.

data "aws_caller_identity" "current" {}

# ── Helper: build IRSA trust policy ──────────────────────────────────────────
locals {
  oidc_host = replace(var.oidc_provider_url, "https://", "")
}

# ── task-service: can publish to SQS + read Secrets Manager ──────────────────
resource "aws_iam_role" "task_service" {
  name = "${var.cluster_name}-task-service"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:sub" = "system:serviceaccount:${var.namespace}:task-service"
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "task_service" {
  name = "${var.cluster_name}-task-service-policy"
  role = aws_iam_role.task_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SQSPublish"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage", "sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
        Resource = var.sqs_queue_arn
      },
      {
        Sid      = "SecretsManagerRead"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = [var.db_secret_arn]
      },
      {
        Sid      = "KMSDecrypt"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = "*"
        Condition = { StringLike = { "kms:ViaService" = "secretsmanager.*.amazonaws.com" } }
      }
    ]
  })
}

# ── notification-service: SQS consume + Secrets Manager ──────────────────────
resource "aws_iam_role" "notification_service" {
  name = "${var.cluster_name}-notification-service"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:sub" = "system:serviceaccount:${var.namespace}:notification-service"
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "notification_service" {
  name = "${var.cluster_name}-notification-service-policy"
  role = aws_iam_role.notification_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSConsume"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = [var.sqs_queue_arn, var.sqs_dlq_arn]
      },
      {
        Sid      = "SecretsManagerRead"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = [var.smtp_secret_arn]
      }
    ]
  })
}

# ── user-service: Secrets Manager (DB creds) + Redis auth ────────────────────
resource "aws_iam_role" "user_service" {
  name = "${var.cluster_name}-user-service"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:sub" = "system:serviceaccount:${var.namespace}:user-service"
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "user_service" {
  name = "${var.cluster_name}-user-service-policy"
  role = aws_iam_role.user_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "SecretsManagerRead"
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = [var.db_secret_arn, var.jwt_secret_arn]
    }]
  })
}

# ── CI/CD role: used by Jenkins/GitLab to push images to ECR ─────────────────
resource "aws_iam_role" "cicd" {
  name = "${var.cluster_name}-cicd-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "sts:ExternalId" = var.cicd_external_id } }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "cicd" {
  name = "${var.cluster_name}-cicd-policy"
  role = aws_iam_role.cicd.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuth"
        Effect = "Allow"
        Action = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:ListImages"
        ]
        Resource = var.ecr_repository_arns
      }
    ]
  })
}

# ── JWT secret in Secrets Manager (created here, referenced by user-service) ──
resource "aws_secretsmanager_secret" "jwt" {
  name                    = "${var.cluster_name}/jwt-secret"
  recovery_window_in_days = 7
  tags                    = var.tags
}

resource "random_password" "jwt" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret_version" "jwt" {
  secret_id     = aws_secretsmanager_secret.jwt.id
  secret_string = jsonencode({ jwt_secret = random_password.jwt.result })
}

# ── SMTP secret placeholder (populated manually or via CI) ───────────────────
resource "aws_secretsmanager_secret" "smtp" {
  name                    = "${var.cluster_name}/smtp-credentials"
  recovery_window_in_days = 7
  tags                    = var.tags
}
