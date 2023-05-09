terraform {
  source = "../..//modules/keycloak"
}

dependency "base" {
  config_path = "../base"
}

locals {
  global_vars = yamldecode(file(find_in_parent_folders("global.yaml")))
}

inputs = {
  project = local.global_vars.project
  tld     = local.global_vars.tld

  vpc_id              = dependency.base.outputs.vpc_id
  vpc_public_subnets  = dependency.base.outputs.vpc_public_subnets
  vpc_private_subnets = dependency.base.outputs.vpc_private_subnets

  ecs_cluster_arn = dependency.base.outputs.ecs_cluster_arn
}
