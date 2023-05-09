output "fqdn" {
  value = "https://${local.fqdn}"
}

output "demo_username" {
  value = local.demo_username
}

output "demo_password" {
  value     = random_password.demo.result
  sensitive = true
}

output "ssm_parameter_demo_username" {
  value = "https://${data.aws_region.current.name}.console.aws.amazon.com/systems-manager/parameters${aws_ssm_parameter.demo_username.name}/description?region=${data.aws_region.current.name}"
}

output "ssm_parameter_demo_password" {
  value = "https://${data.aws_region.current.name}.console.aws.amazon.com/systems-manager/parameters${aws_ssm_parameter.demo_password.name}/description?region=${data.aws_region.current.name}"
}
