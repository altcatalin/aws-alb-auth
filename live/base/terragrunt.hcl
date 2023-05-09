terraform {
  source = "../..//modules/base"
}

locals {
  global_vars = yamldecode(file(find_in_parent_folders("global.yaml")))
}

inputs = {
  project = local.global_vars.project
}
