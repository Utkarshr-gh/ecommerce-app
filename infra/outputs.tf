output "app_name" {
  value = azurerm_linux_web_app.app.name
}

output "app_gateway_public_url" {
  value = "http://${azurerm_public_ip.agw.ip_address}"
}

output "app_service_default_hostname" {
  value = azurerm_linux_web_app.app.default_hostname
}
