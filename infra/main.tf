# ==============================================================================
# Job Application Helper - Azure Container Apps Infrastructure
# ==============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.95.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ------------------------------------------------------------------------------
# Resource Group
# ------------------------------------------------------------------------------

resource "azurerm_resource_group" "main" {
  name     = "${var.prefix}-rg-${random_string.suffix.result}"
  location = var.location
  #tags     = var.tags
}

# ------------------------------------------------------------------------------
# Key Vault
# ------------------------------------------------------------------------------

resource "azurerm_key_vault" "main" {
  name                       = "${var.prefix}-kv-${random_string.suffix.result}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = false
  soft_delete_retention_days = 7

  access_policy {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    object_id          = data.azurerm_client_config.current.object_id
    secret_permissions = ["Get", "List", "Set", "Delete", "Purge", "Recover"]
  }

  #tags = var.tags
}

# ------------------------------------------------------------------------------
# Azure Container Registry (ACR)
# ------------------------------------------------------------------------------

resource "azurerm_container_registry" "main" {
  name                = "${var.prefix}acr${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = true
  #tags                = var.tags
}

# ------------------------------------------------------------------------------
# Log Analytics Workspace (required by Container Apps)
# ------------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.prefix}-law-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  #tags                = var.tags
}

# ------------------------------------------------------------------------------
# Container Apps Environment
# ------------------------------------------------------------------------------

resource "azurerm_container_app_environment" "main" {
  name                       = "${var.prefix}-cae-${random_string.suffix.result}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  #tags                       = var.tags
}

# ------------------------------------------------------------------------------
# Container App
# Uses a placeholder image initially. GitHub Actions replaces it after push.
# ------------------------------------------------------------------------------

resource "azurerm_container_app" "main" {
  name                         = "${var.prefix}-app-${random_string.suffix.result}"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"

  identity {
    type = "SystemAssigned"
  }

  template {
    min_replicas = 0
    max_replicas = 1

    container {
      name   = "job-assistant"
      image  = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "KEY_VAULT_URI"
        value = azurerm_key_vault.main.vault_uri
      }

      env {
        name  = "OPENAI_MODEL"
        value = var.openai_model
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 80
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  #tags = var.tags
}

# Grant Container App Managed Identity access to Key Vault
resource "azurerm_key_vault_access_policy" "container_app" {
  key_vault_id       = azurerm_key_vault.main.id
  tenant_id          = data.azurerm_client_config.current.tenant_id
  object_id          = azurerm_container_app.main.identity[0].principal_id
  secret_permissions = ["Get", "List"]
  depends_on         = [azurerm_container_app.main]
}

# Grant GitHub Actions service principal push access to ACR
resource "azurerm_role_assignment" "github_acr_push" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPush"
  principal_id         = var.github_sp_object_id
}
