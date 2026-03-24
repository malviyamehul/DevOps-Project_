output "user_service_role_arn"         { value = aws_iam_role.user_service.arn }
output "task_service_role_arn"         { value = aws_iam_role.task_service.arn }
output "notification_service_role_arn" { value = aws_iam_role.notification_service.arn }
output "cicd_role_arn"                 { value = aws_iam_role.cicd.arn }
output "jwt_secret_arn"               { value = aws_secretsmanager_secret.jwt.arn }
output "smtp_secret_arn"              { value = aws_secretsmanager_secret.smtp.arn }
