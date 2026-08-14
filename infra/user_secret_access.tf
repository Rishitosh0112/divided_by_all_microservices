# ------------------------------------------------------------------------------
# SUMMARY — What this IAM policy tells AWS to do
#
# Permit the existing ECS task execution role to read exactly one application
# secret: divided-by-all/user-service/runtime.
#
# That secret contains the User service's MONGO_URL and JWT settings. ECS needs
# this permission before the User Docker container starts so it can inject the
# secret values as environment variables. This does not give the User
# application code broad Secrets Manager access, and it does not create a new
# IAM role or a new secret.
# ------------------------------------------------------------------------------

# Read the existing User runtime secret by its stable name. The ARN ends with a
# random AWS-generated suffix, so this lookup avoids hard-coding that suffix in
# Terraform. This block reads metadata only; it never reads or stores values.
data "aws_secretsmanager_secret" "user_runtime" {
  name = "divided-by-all/user-service/runtime"
}

# Attach a least-privilege inline policy to the shared ECS execution role.
# The execution role is used by ECS itself to pull ECR images, write CloudWatch
# logs, and fetch secrets before the application process begins.
resource "aws_iam_role_policy" "user_runtime_secret_read" {
  name = "divided-by-all-user-runtime-secret-read"
  role = data.aws_iam_role.ecs_task_execution.name

  # IAM policies are JSON documents. jsonencode converts this readable
  # Terraform object into valid JSON for AWS.
  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "ReadUserRuntimeSecret"
        Effect = "Allow"

        # GetSecretValue retrieves the MONGO_URL, JWT_SECRET, and JWT_EXPIRES_IN
        # JSON keys for ECS injection. DescribeSecret permits the required
        # metadata lookup. No write, delete, rotate, or wildcard permission is
        # granted.
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]

        # Restrict access to this single secret only.
        Resource = data.aws_secretsmanager_secret.user_runtime.arn
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# RUNTIME FLOW — What happens when the User ECS task later starts
#
# ECS assumes divided-by-all-ecs-task-execution-role
# → ECS pulls the User image from ECR and finds its secret references
# → this policy permits ECS to read only the User runtime secret
# → ECS injects MONGO_URL, JWT_SECRET, and JWT_EXPIRES_IN into the container
# → Node/Mongoose reads MONGO_URL and connects privately to DocumentDB
# ------------------------------------------------------------------------------
