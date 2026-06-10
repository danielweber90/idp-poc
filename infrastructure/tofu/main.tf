# IDP PoC - OpenTofu: EKS + VPC + RDS + ElastiCache + S3
# Claude Code: cd infrastructure/tofu && tofu init && tofu plan && tofu apply

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws    = { source = "hashicorp/aws",    version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
  # Uncomment after creating a state bucket manually:
  # backend "s3" {
  #   bucket = "idp-poc-tofu-state-<account-id>"
  #   key    = "idp-poc/terraform.tfstate"
  #   region = "eu-central-1"
  # }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { project = "idp-poc", managed-by = "opentofu" }
  }
}

variable "aws_region"       { default = "eu-central-1" }
variable "cluster_name"     { default = "idp-poc" }
variable "cluster_version"  { default = "1.30" }

# ── VPC ───────────────────────────────────────────────────────────────────────
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"
  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true   # cost-optimised for PoC
  enable_dns_hostnames = true

  public_subnet_tags  = { "kubernetes.io/role/elb"                    = 1 }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"          = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# ── EKS ───────────────────────────────────────────────────────────────────────
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true
  enable_irsa                    = true   # required for Crossplane AWS provider

  eks_managed_node_groups = {
    platform = {
      min_size       = 2
      max_size       = 4
      desired_size   = 3
      instance_types = ["t3.large"]   # 2 vCPU / 8GB RAM - enough for all platform components
      labels         = { role = "platform" }
    }
  }

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }
}

# ── RDS PostgreSQL ─────────────────────────────────────────────────────────────
resource "aws_db_subnet_group" "poc" {
  name       = "${var.cluster_name}-db"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_security_group" "rds" {
  name   = "${var.cluster_name}-rds-sg"
  vpc_id = module.vpc.vpc_id
  ingress {
    description = "PostgreSQL from VPC"
    from_port   = 5432; to_port = 5432; protocol = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }
  egress {
    from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "random_password" "db" {
  length  = 24
  special = false
}

resource "aws_db_instance" "demo" {
  identifier             = "${var.cluster_name}-demo"
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = "demoapp"
  username               = "demouser"
  password               = random_password.db.result
  db_subnet_group_name   = aws_db_subnet_group.poc.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = true
  deletion_protection    = false
  publicly_accessible    = false
}

# ── ElastiCache Redis ─────────────────────────────────────────────────────────
resource "aws_elasticache_subnet_group" "poc" {
  name       = "${var.cluster_name}-redis"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_security_group" "redis" {
  name   = "${var.cluster_name}-redis-sg"
  vpc_id = module.vpc.vpc_id
  ingress {
    description = "Redis from VPC"
    from_port   = 6379; to_port = 6379; protocol = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }
  egress {
    from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elasticache_replication_group" "demo" {
  replication_group_id = "${var.cluster_name}-demo"
  description          = "IDP PoC demo Redis"
  node_type            = "cache.t3.micro"
  num_cache_clusters   = 1
  engine_version       = "7.1"
  subnet_group_name    = aws_elasticache_subnet_group.poc.name
  security_group_ids   = [aws_security_group.redis.id]
}

# ── S3 Bucket ─────────────────────────────────────────────────────────────────
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "demo" {
  bucket        = "${var.cluster_name}-demo-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "demo" {
  bucket = aws_s3_bucket.demo.id
  rule   { object_ownership = "BucketOwnerEnforced" }
}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}"
}
output "rds_endpoint"      { value = aws_db_instance.demo.endpoint }
output "redis_endpoint"    { value = aws_elasticache_replication_group.demo.primary_endpoint_address }
output "s3_bucket"         { value = aws_s3_bucket.demo.bucket }
output "db_password" {
  value     = random_password.db.result
  sensitive = true
}
