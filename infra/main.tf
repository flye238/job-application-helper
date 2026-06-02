# ==============================================================================
# Job Application Helper - Azure Infrastructure
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
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    secret_permissions = ["Get", "List", "Set", "Delete", "Purge", "Recover"]
  }

  #tags = var.tags
}

# ------------------------------------------------------------------------------
# Storage Account
# ------------------------------------------------------------------------------

resource "azurerm_storage_account" "functions" {
  name                     = "${var.prefix}sa${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  #tags                     = var.tags
}

# ------------------------------------------------------------------------------
# App Service Plan
# ------------------------------------------------------------------------------

resource "azurerm_service_plan" "main" {
  name                = "${var.prefix}-asp-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "B1"
  #tags                = var.tags
}

# ------------------------------------------------------------------------------
# Azure Function App
# ------------------------------------------------------------------------------

resource "azurerm_linux_function_app" "backend" {
  name                       = "${var.prefix}-func-${random_string.suffix.result}"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  service_plan_id            = azurerm_service_plan.main.id
  storage_account_name       = azurerm_storage_account.functions.name
  storage_account_access_key = azurerm_storage_account.functions.primary_access_key

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      python_version = "3.11"
    }
    cors {
      allowed_origins = [
        "https://${var.prefix}-web-${random_string.suffix.result}.azurewebsites.net",
        "http://localhost:3000",
        "http://localhost:5500"
      ]
    }
  }

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME       = "python"
    AzureWebJobsFeatureFlags       = "EnableWorkerIndexing"
    KEY_VAULT_URI                  = azurerm_key_vault.main.vault_uri
    OPENAI_MODEL                   = var.openai_model
    SCM_DO_BUILD_DURING_DEPLOYMENT = "false"
    WEBSITE_RUN_FROM_PACKAGE       = "1"
  }

  #tags = var.tags
}

# Grant Function App read access to Key Vault
resource "azurerm_key_vault_access_policy" "function_app" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_linux_function_app.backend.identity[0].principal_id
  secret_permissions = ["Get", "List"]
  depends_on   = [azurerm_linux_function_app.backend]
}

# ------------------------------------------------------------------------------
# Azure Web App (Frontend)
# ------------------------------------------------------------------------------

resource "azurerm_linux_web_app" "frontend" {
  name                = "${var.prefix}-web-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id

  site_config {
    application_stack {
      node_version = "18-lts"
    }
    always_on = true
  }

  app_settings = {
    FUNCTION_APP_URL = "https://${azurerm_linux_function_app.backend.default_hostname}"
  }

  #tags = var.tags
}
