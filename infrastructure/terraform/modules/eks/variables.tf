variable "cluster_name"        { type = string }
variable "kubernetes_version"  { type = string; default = "1.29" }
variable "vpc_id"              { type = string }
variable "public_subnet_ids"   { type = list(string) }
variable "private_subnet_ids"  { type = list(string) }
variable "public_access"       { type = bool;   default = true }
variable "public_access_cidrs" { type = list(string); default = ["0.0.0.0/0"] }
variable "tags"                { type = map(string); default = {} }

variable "node_groups" {
  type = map(object({
    instance_types = list(string)
    capacity_type  = string
    desired_size   = number
    min_size       = number
    max_size       = number
    labels         = map(string)
    taints         = optional(list(object({ key = string; value = string; effect = string })), [])
  }))
}
