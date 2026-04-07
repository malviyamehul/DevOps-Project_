variable "identifier"                  { type = string }
variable "vpc_id"                      { type = string }
variable "db_subnet_group_name"        { type = string }
variable "eks_node_security_group_id"  { type = string }
variable "db_name"                     { type = string; default = "opsforge" }
variable "db_username"                 { type = string; default = "opsforge" }
variable "instance_class"              { type = string; default = "db.t3.medium" }
variable "allocated_storage"           { type = number; default = 20 }
variable "multi_az"                    { type = bool;   default = false }
variable "deletion_protection"         { type = bool;   default = false }
variable "backup_retention_days"       { type = number; default = 7 }
variable "tags"                        { type = map(string); default = {} }
