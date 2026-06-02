output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "function_app_name" {
  value = azurerm_linux_function_app.backend.name
}

output "function_app_url" {
  value = "https://${azurerm_linux_function_app.backend.default_hostname}"
}

output "frontend_url" {
  value = "https://${azurerm_linux_web_app.frontend.default_hostname}"
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "resource_suffix" {
  description = "Random suffix used in resource names. Save this for GitHub secrets."
  value       = random_string.suffix.result
}

output "next_step" {
  value = "az keyvault secret set --vault-name ${azurerm_key_vault.main.name} --name openai-api-key --value <YOUR_OPENAI_KEY>"
}
