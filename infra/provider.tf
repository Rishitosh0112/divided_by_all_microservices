provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "divided-by-all"
      ManagedBy = "terraform"
    }
  }
}
