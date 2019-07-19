# https://docs.aws.amazon.com/AmazonVPC/latest/UserGuide/flow-logs.html

data aws_iam_policy_document trust {
  statement {
    sid     = "VPCFlowLogsAssumeRole"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

data aws_iam_policy_document flowlog {
  statement {
    sid = "vpcflowlogpolicydoc"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutSubscriptionFilter"
    ]

    resources = ["*"]
  }
}

resource aws_iam_policy flowlog {
  name        = "vpc-flowlog-policy-${local.vpc_id}"
  path        = "/"
  description = "VPC Flow Logs Policy"
  policy      = "${data.aws_iam_policy_document.flowlog.json}"
}

resource aws_iam_role flowlog {
  name               = "vpc-flowlogs-role-${local.vpc_id}"
  assume_role_policy = "${data.aws_iam_policy_document.trust.json}"
}

resource aws_iam_role_policy_attachment flowlog {
  role       = "${aws_iam_role.flowlog.name}"
  policy_arn = "${aws_iam_policy.flowlog.arn}"
}

###########
# FlowLogs
###########

resource "aws_cloudwatch_log_group" "flowlog_log_group" {
  name = "vpc-flowlog-loggroup-${local.vpc_id}"
}

resource "aws_flow_log" "default_vpc_flow_logs" {
  log_destination = "${aws_cloudwatch_log_group.flowlog_log_group.arn}"
  iam_role_arn    = "${aws_iam_role.flowlog.arn}"
  vpc_id          = "${local.vpc_id}"
  traffic_type    = "ALL"
}

resource "aws_cloudwatch_log_subscription_filter" "flowlog_subscription_filter" {
  name            = "flowlog-subscription-filter-${local.vpc_id}"
  log_group_name  = "${aws_cloudwatch_log_group.flowlog_log_group.name}"
  filter_pattern  = ""
  destination_arn = "${var.vpc_flowlogs_cloudwatch_destination_arn}"
}
