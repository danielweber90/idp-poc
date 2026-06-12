# IDP PoC - OpenTofu: EKS + RDS + ElastiCache + S3
# Uses existing VPC vpc-05cea9ef3bd3f58c0 with pre-existing IGW.
# EKS nodes → public subnets (internet access via IGW).
# RDS + Redis → private subnets (VPC-internal only).

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

variable "aws_region"      { default = "eu-central-1" }
variable "cluster_name"    { default = "idp-poc" }
variable "cluster_version" { default = "1.32" }

# ── Existing Network ───────────────────────────────────────────────────────────
data "aws_vpc" "existing" {
  id = "vpc-05cea9ef3bd3f58c0"
}

data "aws_caller_identity" "current" {}

locals {
  # Public subnets (100.64.0.0/24, MapPublicIpOnLaunch=true, IGW route present)
  public_subnet_ids = [
    "subnet-0d1af1d2f53c3bfe2",  # eu-central-1a  100.64.0.0/25
    "subnet-0233a76ce90cd0360",  # eu-central-1b  100.64.0.128/25
  ]
  # Private subnets (10.31.23.0/24, no NAT GW — used only for backing services)
  private_subnet_ids = [
    "subnet-0e890c07faacc7f68",  # eu-central-1a  10.31.23.0/25
    "subnet-05843d29f58bbf626",  # eu-central-1b  10.31.23.128/25
  ]
  # Both VPC CIDRs — used in security group ingress rules
  vpc_cidrs = ["10.31.23.0/24", "100.64.0.0/24"]
}

# ── EKS ───────────────────────────────────────────────────────────────────────
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id                         = data.aws_vpc.existing.id
  subnet_ids                     = local.public_subnet_ids
  cluster_endpoint_public_access = true
  enable_irsa                    = true

  eks_managed_node_groups = {
    platform = {
      subnet_ids     = local.public_subnet_ids
      min_size       = 2
      max_size       = 4
      desired_size   = 3
      instance_types = ["t3.large"]
      labels         = { role = "platform" }
    }
  }

  cluster_addons = {
    coredns              = {}
    kube-proxy           = {}
    vpc-cni              = {}
    aws-ebs-csi-driver   = {}
  }
}

# ── EBS CSI permissions on node role ─────────────────────────────────────────
# Addon uses node instance profile (no IRSA for PoC); node role needs EBS perms.
resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = module.eks.eks_managed_node_groups["platform"].iam_role_name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ── EKS Admin Access (SSO role) ───────────────────────────────────────────────
# bootstrap_cluster_creator_admin_permissions=false so we must add this explicitly.
resource "aws_eks_access_entry" "admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = "arn:aws:iam::084375542523:role/aws-reserved/sso.amazonaws.com/eu-central-1/AWSReservedSSO_FactoryAdmin-dev_983349fd8ebe2c6e"
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_eks_access_entry.admin.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
}

# ── RDS PostgreSQL ─────────────────────────────────────────────────────────────
resource "aws_db_subnet_group" "poc" {
  name       = "${var.cluster_name}-db"
  subnet_ids = local.private_subnet_ids
}

resource "aws_security_group" "rds" {
  name   = "${var.cluster_name}-rds-sg"
  vpc_id = data.aws_vpc.existing.id

  ingress {
    description = "PostgreSQL from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = local.vpc_cidrs
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
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
  subnet_ids = local.private_subnet_ids
}

resource "aws_security_group" "redis" {
  name   = "${var.cluster_name}-redis-sg"
  vpc_id = data.aws_vpc.existing.id

  ingress {
    description = "Redis from VPC"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = local.vpc_cidrs
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
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
resource "aws_s3_bucket" "demo" {
  bucket        = "${var.cluster_name}-demo-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "demo" {
  bucket = aws_s3_bucket.demo.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

# ── Crossplane IRSA role ──────────────────────────────────────────────────────
# Crossplane AWS provider pods use this role via IRSA to manage RDS/ElastiCache/S3.
resource "aws_iam_role" "crossplane_provider" {
  name = "${var.cluster_name}-crossplane-provider"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = module.eks.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          "${module.eks.oidc_provider}:sub" = "system:serviceaccount:crossplane-system:provider-aws-*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "crossplane_rds" {
  role       = aws_iam_role.crossplane_provider.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
}

resource "aws_iam_role_policy_attachment" "crossplane_elasticache" {
  role       = aws_iam_role.crossplane_provider.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonElastiCacheFullAccess"
}

resource "aws_iam_role_policy_attachment" "crossplane_s3" {
  role       = aws_iam_role.crossplane_provider.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

output "crossplane_provider_role_arn" {
  value = aws_iam_role.crossplane_provider.arn
}

# ── HTTPS: ACM certificate + Route53 ─────────────────────────────────────────
variable "domain"          { default = "idp-poc.impact-tracking.dev.uptimize.merckgroup.com" }
variable "hosted_zone_id"  { default = "Z012541820X8HHJYQM4EA" }

resource "aws_acm_certificate" "idp" {
  domain_name       = var.domain
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.idp.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }
  zone_id         = var.hosted_zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "idp" {
  certificate_arn         = aws_acm_certificate.idp.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# Route53 alias: subdomain → Kong CLB
resource "aws_route53_record" "idp" {
  zone_id = var.hosted_zone_id
  name    = var.domain
  type    = "A"
  alias {
    name                   = "ab8d1efe13ac04f1f8fd382b3aabd806-1571709816.eu-central-1.elb.amazonaws.com"
    zone_id                = "Z215JYRZR1TBD5"
    evaluate_target_health = false
  }
}

output "domain"          { value = var.domain }
output "certificate_arn" { value = aws_acm_certificate_validation.idp.certificate_arn }

# ── Outputs ───────────────────────────────────────────────────────────────────
output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}"
}
output "rds_endpoint"   { value = aws_db_instance.demo.endpoint }
output "redis_endpoint" { value = aws_elasticache_replication_group.demo.primary_endpoint_address }
output "s3_bucket"      { value = aws_s3_bucket.demo.bucket }
output "db_password" {
  value     = random_password.db.result
  sensitive = true
}
