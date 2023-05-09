output "fqdn" {
  value = "https://${local.fqdn}"
}

output "admin_username" {
  value = local.admin_username
}

output "admin_password" {
  value     = random_password.admin.result
  sensitive = true
}

output "ssm_parameter_admin_username" {
  value = "https://${data.aws_region.current.name}.console.aws.amazon.com/systems-manager/parameters${aws_ssm_parameter.admin_username.name}/description?region=${data.aws_region.current.name}"
}

output "ssm_parameter_admin_password" {
  value = "https://${data.aws_region.current.name}.console.aws.amazon.com/systems-manager/parameters${aws_ssm_parameter.admin_password.name}/description?region=${data.aws_region.current.name}"
}
