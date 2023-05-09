locals {
  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    project = var.project
  }
}

data "aws_availability_zones" "available" {}

# tfsec:ignore:aws-ec2-require-vpc-flow-logs-for-all-vpcs
# tfsec:ignore:aws-ec2-no-excessive-port-access
# tfsec:ignore:aws-ec2-no-public-ingress-acl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 4.0"

  name                   = var.project
  cidr                   = local.vpc_cidr
  azs                    = local.azs
  private_subnets        = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  public_subnets         = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 4)]
  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false
  tags                   = local.tags
}

module "ecs_cluster" {
  source  = "terraform-aws-modules/ecs/aws//modules/cluster"
  version = "~> 5.0"

  cluster_name = var.project
  tags         = local.tags

  fargate_capacity_providers = {
    FARGATE = {
      default_capacity_provider_strategy = {
        weight = 100
      }
    }
  }
}
