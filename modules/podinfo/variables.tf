variable "project" {
  type = string
}

variable "tld" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_public_subnets" {
  type = list(string)
}

variable "vpc_private_subnets" {
  type = list(string)
}

variable "ecs_cluster_arn" {
  type = string
}

variable "keycloak_url" {
  type = string
}

variable "keycloak_admin_username" {
  type = string
}

variable "keycloak_admin_password" {
  type = string
}
