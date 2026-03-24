output "redis_endpoint"         { value = aws_elasticache_replication_group.this.primary_endpoint_address }
output "redis_port"             { value = 6379 }
output "redis_security_group_id" { value = aws_security_group.redis.id }
