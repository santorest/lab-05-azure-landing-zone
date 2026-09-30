resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_in_days
  tags                = var.tags
}

resource "azurerm_sentinel_log_analytics_workspace_onboarding" "this" {
  workspace_id = azurerm_log_analytics_workspace.this.id
}

# Platform secret store; also a diagnostics source. Purge protection (not prevent_destroy) guards its
# contents: prevent_destroy would block the documented teardown and `terraform test` (security/EXCEPTIONS.md).
# tflint-ignore: azurerm_resources_missing_prevent_destroy
resource "azurerm_key_vault" "this" {
  name                          = var.key_vault_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  public_network_access_enabled = false
  tags                          = var.tags

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }
}

resource "azurerm_private_endpoint" "key_vault" {
  name                = "pe-${var.key_vault_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.key_vault_name}"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "vault"
    private_dns_zone_ids = [var.key_vault_private_dns_zone_id]
  }
}

resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                       = "to-${azurerm_log_analytics_workspace.this.name}"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }
}

resource "azurerm_monitor_diagnostic_setting" "activity_log" {
  name                       = "to-${azurerm_log_analytics_workspace.this.name}"
  target_resource_id         = "/subscriptions/${var.subscription_id}"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  dynamic "enabled_log" {
    for_each = ["Administrative", "Security", "Policy", "Alert"]
    content {
      category = enabled_log.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "targets" {
  for_each                   = var.diagnostic_targets
  name                       = "to-${azurerm_log_analytics_workspace.this.name}"
  target_resource_id         = each.value.resource_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  dynamic "enabled_log" {
    for_each = each.value.category_groups
    content {
      category_group = enabled_log.value
    }
  }
}

resource "azurerm_monitor_aad_diagnostic_setting" "entra" {
  count                      = var.enable_entra_diagnostics ? 1 : 0
  name                       = "to-${azurerm_log_analytics_workspace.this.name}"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  dynamic "enabled_log" {
    for_each = ["SignInLogs", "AuditLogs"]
    content {
      category = enabled_log.value
    }
  }
}
