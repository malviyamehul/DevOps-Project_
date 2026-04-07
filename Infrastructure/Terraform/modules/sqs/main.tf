# modules/sqs/main.tf
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.queue_name}-dlq"
  message_retention_seconds = 1209600   # 14 days
  kms_master_key_id         = "alias/aws/sqs"
  tags                      = var.tags
}

resource "aws_sqs_queue" "this" {
  name                       = var.queue_name
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400    # 1 day
  receive_wait_time_seconds  = 20       # long polling
  kms_master_key_id          = "alias/aws/sqs"

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = var.tags
}

resource "aws_sqs_queue_policy" "this" {
  queue_url = aws_sqs_queue.this.id
  policy    = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowSendFromTaskService"
      Effect    = "Allow"
      Principal = { AWS = var.publisher_role_arns }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.this.arn
    }, {
      Sid       = "AllowReceiveFromNotificationService"
      Effect    = "Allow"
      Principal = { AWS = var.consumer_role_arns }
      Action    = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
      Resource  = aws_sqs_queue.this.arn
    }]
  })
}
