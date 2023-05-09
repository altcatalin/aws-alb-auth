locals {
  fqdn = "${var.project}-podinfo.${var.tld}"
  port = 9898

  demo_username = "demo"

  tags = {
    project = var.project
  }
}

data "aws_route53_zone" "tld" {
  name         = var.tld
  private_zone = false
}

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 4.3"

  domain_name = local.fqdn
  zone_id     = data.aws_route53_zone.tld.id
  tags        = local.tags
}

resource "keycloak_realm" "project" {
  realm = var.project
}

resource "random_password" "demo" {
  length = 32
}

resource "aws_ssm_parameter" "demo_password" {
  name  = "/digital/${var.project}/podinfo/demo_password"
  type  = "SecureString"
  value = random_password.demo.result
  tags  = local.tags
}

resource "aws_ssm_parameter" "demo_username" {
  name  = "/digital/${var.project}/podinfo/demo_username"
  type  = "String"
  value = local.demo_username
  tags  = local.tags
}

resource "keycloak_user" "demo" {
  realm_id = keycloak_realm.project.id
  username = local.demo_username

  initial_password {
    value     = random_password.demo.result
    temporary = false
  }
}

resource "keycloak_openid_client" "podinfo" {
  realm_id              = keycloak_realm.project.id
  client_id             = "podinfo"
  name                  = "$${client_podinfo}"
  access_type           = "CONFIDENTIAL"
  standard_flow_enabled = true
  valid_redirect_uris   = ["https://${local.fqdn}/oauth2/idpresponse"]
}

# tfsec:ignore:aws-elb-alb-not-public
# tfsec:ignore:aws-ec2-no-public-ingress-sgr
# tfsec:ignore:aws-ec2-no-public-egress-sgr
module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.0"

  name                        = "${var.project}-podinfo"
  load_balancer_type          = "application"
  vpc_id                      = var.vpc_id
  subnets                     = var.vpc_public_subnets
  drop_invalid_header_fields  = true
  listener_ssl_policy_default = "ELBSecurityPolicy-TLS-1-2-2017-01"
  tags                        = local.tags

  security_group_rules = {
    ingress_all_http = {
      type        = "ingress"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "HTTPS"
      cidr_blocks = ["0.0.0.0/0"]
    }

    ingress_all_icmp = {
      type        = "ingress"
      from_port   = -1
      to_port     = -1
      protocol    = "icmp"
      description = "ICMP"
      cidr_blocks = ["0.0.0.0/0"]
    }

    egress_all = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  target_groups = [
    {
      name             = "${var.project}-podinfo"
      backend_protocol = "HTTP"
      backend_port     = local.port
      target_type      = "ip"
    }
  ]

  https_listeners = [
    {
      port               = 443
      protocol           = "HTTPS"
      certificate_arn    = module.acm.acm_certificate_arn
      action_type        = "authenticate-oidc"
      target_group_index = 0

      authenticate_oidc = {
        issuer                 = "${var.keycloak_url}/realms/${var.project}"
        authorization_endpoint = "${var.keycloak_url}/realms/${var.project}/protocol/openid-connect/auth"
        token_endpoint         = "${var.keycloak_url}/realms/${var.project}/protocol/openid-connect/token"
        user_info_endpoint     = "${var.keycloak_url}/realms/${var.project}/protocol/openid-connect/userinfo"
        client_id              = keycloak_openid_client.podinfo.client_id
        client_secret          = keycloak_openid_client.podinfo.client_secret
      }
    },
  ]

  https_listener_rules = [
    {
      https_listener_index = 0
      priority             = 1

      actions = [
        {
          type               = "forward"
          target_group_index = 0
        }
      ]

      conditions = [{
        path_patterns = ["/version"]
      }]
    },
  ]
}

resource "aws_route53_record" "fqdn" {
  name    = local.fqdn
  type    = "CNAME"
  ttl     = "300"
  zone_id = data.aws_route53_zone.tld.zone_id
  records = [module.alb.lb_dns_name]
}

data "aws_region" "current" {}

# tfsec:ignore:aws-ec2-no-public-egress-sgr
module "ecs_service" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 5.0"

  name                     = "${var.project}-podinfo"
  cluster_arn              = var.ecs_cluster_arn
  cpu                      = 256
  memory                   = 512
  subnet_ids               = var.vpc_private_subnets
  tags                     = local.tags
  autoscaling_max_capacity = 5
  autoscaling_min_capacity = 3

  container_definitions = {
    podinfo = {
      cpu                         = 256
      memory                      = 512
      memory_reservation          = 256
      essential                   = true
      image                       = "stefanprodan/podinfo:6.3.6"
      readonly_root_filesystem    = false
      create_cloudwatch_log_group = false

      port_mappings = [
        {
          name          = "http"
          containerPort = local.port
          protocol      = "tcp"
        }
      ]

      log_configuration = {
        logDriver = "awslogs"

        options = {
          awslogs-region        = data.aws_region.current.name
          awslogs-group         = "/aws/ecs/${var.project}"
          awslogs-stream-prefix = "podinfo"
        }
      }
    }
  }

  load_balancer = {
    podinfo = {
      target_group_arn = module.alb.target_group_arns[0]
      container_name   = "podinfo"
      container_port   = local.port
    }
  }

  security_group_rules = {
    alb_ingress_podinfo = {
      type                     = "ingress"
      from_port                = local.port
      to_port                  = local.port
      protocol                 = "tcp"
      description              = "Podinfo"
      source_security_group_id = module.alb.security_group_id
    }

    egress_all = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
}
