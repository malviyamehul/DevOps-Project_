variable "queue_name"           { type = string }
variable "publisher_role_arns"  { type = list(string); default = [] }
variable "consumer_role_arns"   { type = list(string); default = [] }
variable "tags"                 { type = map(string); default = {} }
