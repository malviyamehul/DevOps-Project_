variable "cluster_name"        { type = string }
variable "namespace"           { type = string; default = "opsforge" }
variable "oidc_provider_arn"   { type = string }
variable "oidc_provider_url"   { type = string }
variable "sqs_queue_arn"       { type = string }
variable "sqs_dlq_arn"         { type = string }
variable "db_secret_arn"       { type = string }
variable "ecr_repository_arns" { type = list(string) }
variable "cicd_external_id"    { type = string; default = "opsforge-cicd" }
variable "tags"                { type = map(string); default = {} }

# Optional — smtp secret may not exist yet at first apply
variable "smtp_secret_arn" {
  type    = string
  default = "*"   # wildcard until the secret is created
}
