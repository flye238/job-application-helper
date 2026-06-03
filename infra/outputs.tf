output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "acr_name" {
  value = azurerm_container_registry.main.name
}

output "container_app_name" {
  value = azurerm_container_app.main.name
}

output "container_app_url" {
  value = "https://${azurerm_container_app.main.ingress[0].fqdn}"
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "resource_suffix" {
  value = random_string.suffix.result
}

output "next_step" {
  value = "az keyvault secret set --vault-name ${azurerm_key_vault.main.name} --name openai-api-key --value <YOUR_OPENAI_KEY>"
}
