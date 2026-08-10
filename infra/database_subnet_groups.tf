resource "aws_db_subnet_group" "groups_postgres_private" {
  name        = "divided-by-all-groups-rds-private-subnet-group"
  description = "Private subnets for Divided By All Groups PostgreSQL"

  subnet_ids = [
    data.aws_subnet.private_a.id,
    data.aws_subnet.private_b.id,
  ]

  tags = {
    Name = "divided-by-all-groups-rds-private-subnet-group"
  }
}

resource "aws_docdb_subnet_group" "user_documentdb" {
  name        = "divided-by-all-documentdb-subnet-group"
  description = "Private subnets for Divided By All User DocumentDB"

  subnet_ids = [
    data.aws_subnet.private_a.id,
    data.aws_subnet.private_b.id,
  ]

  tags = {
    Name = "divided-by-all-documentdb-subnet-group"
  }
}
