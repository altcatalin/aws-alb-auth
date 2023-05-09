terraform {
  source = "../..//modules/podinfo"
}

dependency "base" {
  config_path = "../base"
}

dependency "keycloak" {
  config_path = "../keycloak"
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
  ecs_cluster_arn     = dependency.base.outputs.ecs_cluster_arn

  keycloak_url            = dependency.keycloak.outputs.fqdn
  keycloak_admin_username = dependency.keycloak.outputs.admin_username
  keycloak_admin_password = dependency.keycloak.outputs.admin_password
}
