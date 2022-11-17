provider "aws" {
  region = "eu-west-1"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

variable "ssh_key_name" {
  type = string
}

resource "aws_iam_policy" "manage_environment_iam_policy" {
  name = "ManageEnvPolicy"
  policy = "${file("manage-environment-policy.json")}"
}

resource "aws_iam_role" "manage_environment_iam_role" {
  name = "ManageEnvRoleTer"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy_attachment" "manage_environment_iam_policy_attachment" {
    name = "ManageEnvPolicyAttachment"
    policy_arn = "${aws_iam_policy.manage_environment_iam_policy.arn}"
    roles = ["${aws_iam_role.manage_environment_iam_role.name}"]
}

data "archive_file" "start_environment_lambda_zip" {
    type        = "zip"
    source_dir  = "start_env_lambda"
    output_path = "lambda-packages/start_environment_lambda_payload.zip"
}

resource "aws_lambda_function" "start_environment_lambda" {
  filename         = "lambda-packages/start_environment_lambda_payload.zip"
  function_name    = "StartEnvironment"
  role             = "${aws_iam_role.manage_environment_iam_role.arn}"
  handler          = "index.handler"
  source_code_hash = "${data.archive_file.start_environment_lambda_zip.output_base64sha256}"
  runtime          = "nodejs16.x"
  memory_size      = 128
  timeout          = 15
}

data "archive_file" "stop_environment_lambda_zip" {
    type        = "zip"
    source_dir  = "stop_env_lambda"
    output_path = "lambda-packages/stop_environment_lambda_payload.zip"
}

resource "aws_lambda_function" "stop_environment_lambda" {
  filename         = "lambda-packages/stop_environment_lambda_payload.zip"
  function_name    = "StopEnvironment"
  role             = "${aws_iam_role.manage_environment_iam_role.arn}"
  handler          = "index.handler"
  source_code_hash = "${data.archive_file.stop_environment_lambda_zip.output_base64sha256}"
  runtime          = "nodejs16.x"
  memory_size      = 128
  timeout          = 15
}

resource "aws_cloudwatch_event_rule" "start_environment_rule" {
  name                = "StartEnvironmentRule"
  schedule_expression = "cron(30 14 ? * 2-6 *)"
}

resource "aws_cloudwatch_event_rule" "stop_environment_rule" {
  name                = "StopEnvironmentRule"
  schedule_expression = "cron(0 15 ? * 2-6 *)"
}

resource "aws_cloudwatch_event_target" "start_environment_rule_target" {
  target_id = "start_environment_rule_target"
  rule      = "${aws_cloudwatch_event_rule.start_environment_rule.name}"
  arn       = "${aws_lambda_function.start_environment_lambda.arn}"
  input     = <<EOF
{ "stackName": "MyStack", "keyPairName": "${var.ssh_key_name}" }
EOF
}

resource "aws_cloudwatch_event_target" "stop_environment_rule_target" {
  target_id = "stop_environment_rule_target"
  rule      = "${aws_cloudwatch_event_rule.stop_environment_rule.name}"
  arn       = "${aws_lambda_function.stop_environment_lambda.arn}"
  input     = <<EOF
{ "stackName": "MyStack" }
EOF
}

resource "aws_lambda_permission" "allow_cloudwatch_start_env" {
  statement_id   = "AllowExecutionFromCloudWatch"
  action         = "lambda:InvokeFunction"
  function_name  = "${aws_lambda_function.start_environment_lambda.function_name}"
  principal      = "events.amazonaws.com"
  source_arn     = "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/StartEnvironmentRule"
}

resource "aws_lambda_permission" "allow_cloudwatch_stop_env" {
  statement_id   = "AllowExecutionFromCloudWatch"
  action         = "lambda:InvokeFunction"
  function_name  = "${aws_lambda_function.stop_environment_lambda.function_name}"
  principal      = "events.amazonaws.com"
  source_arn     = "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/StopEnvironmentRule"
}

