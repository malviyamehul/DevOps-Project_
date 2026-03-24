# environments/production/main.tf
# Production: multi-AZ RDS, Redis replication, larger nodes,
# separate S3 state bucket, separate AWS account recommended.

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws    = { source = "hashicorp/aws";    version = "~> 5.0" }
    random = { source = "hashicorp/random"; version = "~> 3.6" }
    tls    = { source = "hashicorp/tls";    version = "~> 4.0" }
  }

  backend "s3" {
    bucket         = "opsforge-tfstate-production"
    key            = "production/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "opsforge-tfstate-lock-production"
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.common_tags
  }
}

locals {
  env         = "production"
  name_prefix = "opsforge-${local.env}"
  common_tags = {
    Project     = "opsforge"
    Environment = local.env
    ManagedBy   = "terraform"
  }
}

module "vpc" {
  source = "../../modules/vpc"

  name               = local.name_prefix
  cluster_name       = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  single_nat_gateway = false  # one NAT per AZ in production
  enable_flow_logs   = true
  tags               = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name       = local.name_prefix
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  node_groups = {
    general = {
      instance_types = ["m5.large"]
      capacity_type  = "ON_DEMAND"
      desired_size   = 3
      min_size       = 2
      max_size       = 10
      labels         = { role = "general" }
    }
    spot = {
      instance_types = ["m5.large", "m5a.large", "m4.large"]
      capacity_type  = "SPOT"
      desired_size   = 2
      min_size       = 0
      max_size       = 8
      labels         = { role = "spot" }
      taints         = [{ key = "spot", value = "true", effect = "NO_SCHEDULE" }]
    }
  }

  tags = local.common_tags
}

module "ecr" {
  source = "../../modules/ecr"
  tags   = local.common_tags
}

module "rds" {
  source = "../../modules/rds"

  identifier                 = local.name_prefix
  vpc_id                     = module.vpc.vpc_id
  db_subnet_group_name       = module.vpc.db_subnet_group_name
  eks_node_security_group_id = module.eks.cluster_security_group_id

  instance_class        = "db.m5.large"
  allocated_storage     = 100
  multi_az              = true         # HA in production
  deletion_protection   = true
  backup_retention_days = 14

  tags = local.common_tags
}

module "elasticache" {
  source = "../../modules/elasticache"

  cluster_id                 = local.name_prefix
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.private_subnet_ids
  eks_node_security_group_id = module.eks.cluster_security_group_id

  node_type       = "cache.m5.large"
  num_cache_nodes = 2    # primary + replica

  tags = local.common_tags
}

module "sqs" {
  source = "../../modules/sqs"

  queue_name           = "${local.name_prefix}-events"
  publisher_role_arns  = [module.iam.task_service_role_arn]
  consumer_role_arns   = [module.iam.notification_service_role_arn]

  tags = local.common_tags
}

module "iam" {
  source = "../../modules/iam"

  cluster_name       = local.name_prefix
  namespace          = "opsforge"
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider_url  = module.eks.oidc_provider_url
  sqs_queue_arn      = module.sqs.queue_arn
  sqs_dlq_arn        = module.sqs.dlq_arn
  db_secret_arn      = module.rds.db_secret_arn

  ecr_repository_arns = [
    for url in values(module.ecr.repository_urls) :
    "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${split("/", url)[1]}"
  ]

  tags = local.common_tags
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "assets" {
  bucket = "${local.name_prefix}-assets-${data.aws_caller_identity.current.account_id}"
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
