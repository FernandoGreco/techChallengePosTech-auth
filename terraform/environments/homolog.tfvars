environment = "homolog"
aws_region  = "us-east-1"

# VPC padrao da conta do AWS Academy (mesma do RDS)
vpc_id = "vpc-0b43c457a8789dcfc"
subnet_ids = [
  "subnet-04accc46dbe86e2d3",
  "subnet-0ce6aa0ccf82e55a8",
  "subnet-0ab00aaf8c0519d64",
  "subnet-0eefa5790f1bde61f",
]

# Segredos (database_url, jwt_secret) e app_base_url vem do GitHub Actions via TF_VAR_*
