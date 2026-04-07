# modules/elasticache/main.tf
resource "aws_security_group" "redis" {
  name        = "${var.cluster_id}-redis-sg"
  description = "Redis - EKS nodes only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.eks_node_security_group_id]
  }
  egress { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
  tags = merge(var.tags, { Name = "${var.cluster_id}-redis-sg" })
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.cluster_id}-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = var.tags
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = var.cluster_id
  description          = "OpsForge Redis - ${var.cluster_id}"

  node_type            = var.node_type
  num_cache_clusters   = var.num_cache_nodes
  engine_version       = "7.1"
  port                 = 6379

  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  automatic_failover_enabled = var.num_cache_nodes > 1

  snapshot_retention_limit = 1
  snapshot_window          = "03:00-04:00"

  tags = var.tags
}
