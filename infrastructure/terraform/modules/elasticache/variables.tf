variable "cluster_id"                  { type = string }
variable "vpc_id"                      { type = string }
variable "subnet_ids"                  { type = list(string) }
variable "eks_node_security_group_id"  { type = string }
variable "node_type"                   { type = string; default = "cache.t3.micro" }
variable "num_cache_nodes"             { type = number; default = 1 }
variable "tags"                        { type = map(string); default = {} }
