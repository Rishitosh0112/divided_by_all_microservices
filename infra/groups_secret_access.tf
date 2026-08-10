# This data block does NOT create a secret.
# It looks up the existing Secrets Manager secret by its stable name.
# AWS secret ARNs have a random suffix, so looking it up by name avoids hardcoding that suffix.
data "aws_secretsmanager_secret" "groups_database_url" {
  name = "divided-by-all/groups-service/database-url"
}

# This resource creates an inline IAM policy and attaches it to the existing ECS
# task execution role. The execution role is used by ECS BEFORE the Groups
# container starts: it pulls the image, sends logs, and fetches injected secrets.
resource "aws_iam_role_policy" "groups_database_secret_read" {
  # The visible policy name in the IAM Console.
  name = "divided-by-all-groups-database-secret-read"

  # Read the existing execution-role name from our Terraform data source.
  # We do not create another role.
  role = data.aws_iam_role.ecs_task_execution.name

  # IAM expects the permission document in JSON.
  # jsonencode lets Terraform generate valid JSON from this HCL object.
  policy = jsonencode({
    # Standard IAM policy language version.
    Version = "2012-10-17"

    Statement = [
      {
        # A descriptive identifier for this one rule inside the policy.
        Sid = "ReadGroupsDatabaseUrl"

        # Grant the listed actions. Nothing is allowed unless explicitly listed.
        Effect = "Allow"

        # ECS needs the secret value to inject DATABASE_URL into the container.
        # DescribeSecret permits reading the secret metadata required during lookup.
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]

        # Least privilege: this policy applies to exactly one secret ARN.
        # It does NOT allow reading every secret in this AWS account.
        Resource = data.aws_secretsmanager_secret.groups_database_url.arn
      }
    ]
  })
}
