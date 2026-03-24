variable "name"               { type = string }
variable "cluster_name"       { type = string }
variable "vpc_cidr"           { type = string; default = "10.0.0.0/16" }
variable "single_nat_gateway" { type = bool;   default = false }
variable "enable_flow_logs"   { type = bool;   default = true }
variable "tags"               { type = map(string); default = {} }
