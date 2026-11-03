# ── Observabilidade: dashboard e alarmes no CloudWatch ────────────────────────
# Cobre a parte de autenticacao/gateway do requisito de monitoramento (latencia,
# erros, volume). Datadog/New Relic do grupo podem ler as mesmas metricas via integracao AWS.

locals {
  api_id         = aws_apigatewayv2_api.main.id
  dashboard_name = "oficina-auth-${var.environment}"
}

resource "aws_sns_topic" "alarmes" {
  count = var.alarm_email != "" ? 1 : 0
  name  = "${local.name_prefix}-alarmes"
}

resource "aws_sns_topic_subscription" "alarmes_email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarmes[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

locals {
  alarm_actions = aws_sns_topic.alarmes[*].arn
}

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${local.name_prefix}-api-5xx"
  alarm_description   = "API Gateway respondendo 5xx (falha na Lambda ou na aplicacao)"
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  dimensions          = { ApiId = local.api_id }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "api_latencia" {
  alarm_name          = "${local.name_prefix}-api-latencia-p95"
  alarm_description   = "Latencia p95 do API Gateway acima de ${var.latency_alarm_ms} ms"
  namespace           = "AWS/ApiGateway"
  metric_name         = "Latency"
  dimensions          = { ApiId = local.api_id }
  extended_statistic  = "p95"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.latency_alarm_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "lambda_erros" {
  for_each = {
    auth       = aws_lambda_function.auth.function_name
    authorizer = aws_lambda_function.authorizer.function_name
  }

  alarm_name          = "${each.value}-erros"
  alarm_description   = "Erros nao tratados na Lambda ${each.value}"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = each.value }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_dashboard" "auth" {
  dashboard_name = local.dashboard_name

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 8, height = 6
        properties = {
          title   = "API Gateway - requisicoes"
          region  = var.aws_region
          stat    = "Sum"
          period  = 60
          view    = "timeSeries"
          metrics = [["AWS/ApiGateway", "Count", "ApiId", local.api_id]]
        }
      },
      {
        type = "metric", x = 8, y = 0, width = 8, height = 6
        properties = {
          title  = "API Gateway - latencia (ms)"
          region = var.aws_region
          period = 60
          view   = "timeSeries"
          metrics = [
            ["AWS/ApiGateway", "Latency", "ApiId", local.api_id, { stat = "p50", label = "p50" }],
            ["...", { stat = "p95", label = "p95" }],
            ["AWS/ApiGateway", "IntegrationLatency", "ApiId", local.api_id, { stat = "p95", label = "integracao p95" }],
          ]
        }
      },
      {
        type = "metric", x = 16, y = 0, width = 8, height = 6
        properties = {
          title  = "API Gateway - erros"
          region = var.aws_region
          stat   = "Sum"
          period = 60
          view   = "timeSeries"
          metrics = [
            ["AWS/ApiGateway", "4xx", "ApiId", local.api_id, { label = "4xx (CPF invalido, sem token...)" }],
            ["AWS/ApiGateway", "5xx", "ApiId", local.api_id, { label = "5xx", color = "#d62728" }],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 8, height = 6
        properties = {
          title  = "Lambdas - invocacoes e erros"
          region = var.aws_region
          stat   = "Sum"
          period = 60
          view   = "timeSeries"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.auth.function_name, { label = "auth" }],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.authorizer.function_name, { label = "authorizer" }],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.auth.function_name, { label = "erros auth", color = "#d62728" }],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.authorizer.function_name, { label = "erros authorizer", color = "#ff7f0e" }],
          ]
        }
      },
      {
        type = "metric", x = 8, y = 6, width = 8, height = 6
        properties = {
          title  = "Lambdas - duracao p95 (ms)"
          region = var.aws_region
          stat   = "p95"
          period = 60
          view   = "timeSeries"
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.auth.function_name, { label = "auth" }],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.authorizer.function_name, { label = "authorizer" }],
          ]
        }
      },
      {
        type = "alarm", x = 16, y = 6, width = 8, height = 6
        properties = {
          title = "Alarmes"
          alarms = concat(
            [aws_cloudwatch_metric_alarm.api_5xx.arn, aws_cloudwatch_metric_alarm.api_latencia.arn],
            [for a in aws_cloudwatch_metric_alarm.lambda_erros : a.arn],
          )
        }
      },
      {
        type = "log", x = 0, y = 12, width = 12, height = 6
        properties = {
          title  = "Autenticacoes por resultado"
          region = var.aws_region
          view   = "bar"
          query  = "SOURCE '${aws_cloudwatch_log_group.auth.name}' | filter ispresent(correlationId) | stats count(*) as total by message"
        }
      },
      {
        type = "log", x = 12, y = 12, width = 12, height = 6
        properties = {
          title  = "Ultimas requisicoes no gateway"
          region = var.aws_region
          view   = "table"
          query  = "SOURCE '${aws_cloudwatch_log_group.api_access.name}' | fields @timestamp, method, path, status, latencyMs, requestId, clienteId | sort @timestamp desc | limit 20"
        }
      },
    ]
  })
}
