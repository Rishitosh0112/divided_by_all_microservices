# ------------------------------------------------------------------------------
# SUMMARY — What this DocumentDB configuration tells AWS to do
#
# Create the private MongoDB-compatible database for the User service.
#
# Create exactly:
# - one DocumentDB cluster, which owns the durable database storage
# - one db.t3.medium primary instance, which provides the database compute
#
# Keep it private:
# - use the existing two-private-subnet DocumentDB subnet group
# - attach the existing User DocumentDB security group
# - never assign a public database endpoint
#
# Store the master credential in AWS Secrets Manager. Terraform never receives,
# prints, or writes that password into a .tf file or Terraform state.
#
# COST GUARDRAIL
# This is intentionally ONE instance. Do not add replicas for this learning
# deployment. A replica is another billable DocumentDB instance.
# ------------------------------------------------------------------------------

# Read the existing firewall dedicated to DocumentDB. Its inbound rule will be
# used later to allow only User ECS tasks to connect on the MongoDB port 27017.
data "aws_security_group" "user_documentdb" {
  id = "sg-0774deeeef2d87ae0"
}

# Create the DocumentDB cluster, which manages the replicated storage layer and
# database endpoint. A cluster alone cannot accept application connections; the
# single cluster instance below supplies the compute that serves those requests.
resource "aws_docdb_cluster" "user" {
  cluster_identifier = "divided-by-all-user-documentdb"

  # Amazon DocumentDB's managed MongoDB-compatible engine and the version
  # selected for this deployment.
  engine         = "docdb"
  engine_version = "5.0.0"

  # Use only private subnets in two Availability Zones and the database-only
  # security group. There is no public-IP setting for a DocumentDB cluster.
  db_subnet_group_name   = aws_docdb_subnet_group.user_documentdb.name
  vpc_security_group_ids = [data.aws_security_group.user_documentdb.id]

  # AWS creates and stores the randomly generated master password in Secrets
  # Manager. Later, the User service will receive a separate application
  # connection secret; the master password will never be hard-coded here.
  master_username            = "user_documentdb_admin"
  manage_master_user_password = true

  # Encrypt database storage using the AWS-managed DocumentDB KMS key.
  storage_encrypted = true

  # Keep only one day of automatic backups during learning to limit storage
  # charges. This can be increased deliberately for production.
  backup_retention_period = 1

  # This is a learning environment, so deletion protection stays off. Before a
  # production deployment, enable deletion protection and set a longer backup
  # retention period.
  deletion_protection = false

  tags = {
    Service     = "user"
    Environment = "learning"
  }
}

# Create exactly one primary DocumentDB compute instance. This is the billable
# database-server capacity. Do not add a replica instance unless availability
# requirements justify the additional ongoing cost.
resource "aws_docdb_cluster_instance" "user_primary" {
  identifier         = "divided-by-all-user-documentdb-primary"
  cluster_identifier = aws_docdb_cluster.user.id
  instance_class     = "db.t3.medium"

  tags = {
    Service     = "user"
    Environment = "learning"
  }
}

# ------------------------------------------------------------------------------
# RUNTIME FLOW — What happens when this configuration is applied
#
# Terraform asks AWS to create the DocumentDB cluster in private subnets
# → AWS creates a master credential in Secrets Manager
# → AWS provisions one db.t3.medium primary instance
# → the instance becomes the private cluster endpoint on port 27017
# → later, Terraform creates a User-service connection secret and a narrowly
#   scoped security-group rule for the User ECS tasks
# → the User ECS container connects privately through that endpoint
# ------------------------------------------------------------------------------
