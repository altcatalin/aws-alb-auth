locals {
  fqdn = "${var.project}-keycloak.${var.tld}"
  port = 8080

  admin_username = "admin"

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

# tfsec:ignore:aws-elb-alb-not-public
# tfsec:ignore:aws-ec2-no-public-ingress-sgr
# tfsec:ignore:aws-ec2-no-public-egress-sgr
module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.0"

  name                        = "${var.project}-keycloak"
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
      name             = "${var.project}-keycloak"
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
      action_type        = "forward"
      target_group_index = 0
    }
  ]
}

resource "aws_route53_record" "fqdn" {
  name    = local.fqdn
  type    = "CNAME"
  ttl     = "300"
  zone_id = data.aws_route53_zone.tld.zone_id
  records = [module.alb.lb_dns_name]
}

resource "random_password" "admin" {
  length = 32
}

resource "aws_ssm_parameter" "admin_password" {
  name  = "/digital/${var.project}/keycloak/admin_password"
  type  = "SecureString"
  value = random_password.admin.result
  tags  = local.tags
}

resource "aws_ssm_parameter" "admin_username" {
  name  = "/digital/${var.project}/keycloak/admin_username"
  type  = "String"
  value = local.admin_username
  tags  = local.tags
}

data "aws_region" "current" {}

# tfsec:ignore:aws-ec2-no-public-egress-sgr
module "ecs_service" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 5.0"

  name               = "${var.project}-keycloak"
  cluster_arn        = var.ecs_cluster_arn
  cpu                = 1024
  memory             = 2048
  subnet_ids         = var.vpc_private_subnets
  tags               = local.tags
  enable_autoscaling = false

  container_definitions = {
    keycloak = {
      cpu                         = 1024
      memory                      = 2048
      memory_reservation          = 512
      essential                   = true
      image                       = "quay.io/keycloak/keycloak:21.1.1"
      readonly_root_filesystem    = false
      create_cloudwatch_log_group = false
      start_timeout               = 120

      environment = [
        {
          name  = "KC_HOSTNAME"
          value = aws_route53_record.fqdn.fqdn
        },
        {
          name  = "KC_PROXY"
          value = "edge"
        },
        {
          name  = "KC_LOG_CONSOLE_OUTPUT"
          value = "json"
        }
      ]

      secrets = [
        {
          name      = "KEYCLOAK_ADMIN"
          valueFrom = aws_ssm_parameter.admin_username.arn
        },
        {
          name      = "KEYCLOAK_ADMIN_PASSWORD"
          valueFrom = aws_ssm_parameter.admin_password.arn
        }
      ]

      command = [
        "start-dev"
      ]

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
          awslogs-stream-prefix = "keycloak"
        }
      }
    }
  }

  load_balancer = {
    keycloak = {
      target_group_arn = module.alb.target_group_arns[0]
      container_name   = "keycloak"
      container_port   = local.port
    }
  }

  security_group_rules = {
    alb_ingress_keycloak = {
      type                     = "ingress"
      from_port                = local.port
      to_port                  = local.port
      protocol                 = "tcp"
      description              = "Keycloak"
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
