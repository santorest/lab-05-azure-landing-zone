# Sample workload storage, reachable only through a private endpoint. Versioning and soft delete guard
# its data; prevent_destroy would block teardown and `terraform test` (security/EXCEPTIONS.md).
# tflint-ignore: azurerm_resources_missing_prevent_destroy
resource "azurerm_storage_account" "workload" {
  #checkov:skip=CKV_AZURE_33:Queue service is not used; blob logs go to Log Analytics through a diagnostic setting (landing-zone root).
  #checkov:skip=CKV_AZURE_206:ZRS (zone-redundant) by design; geo-replication would copy data outside allowed_locations.
  #checkov:skip=CKV2_AZURE_1:Platform-managed keys plus infrastructure encryption; CMK needs a vault key and rotation process (revisit for regulated data).
  name                              = var.storage_account_name
  resource_group_name               = var.workload_resource_group_name
  location                          = var.location
  account_tier                      = "Standard"
  account_replication_type          = "ZRS"
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  public_network_access_enabled     = false
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true
  local_user_enabled                = false
  tags                              = var.tags

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  for_each              = azurerm_virtual_network.this
  name                  = "link-${each.key}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = each.value.id
  registration_enabled  = false
  tags                  = var.tags
}

# Zone for Key Vault private endpoints (the vault itself lives in the logging module).
resource "azurerm_private_dns_zone" "vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "vault" {
  for_each              = azurerm_virtual_network.this
  name                  = "link-${each.key}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.vault.name
  virtual_network_id    = each.value.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "blob" {
  name                = "pe-${var.storage_account_name}-blob"
  location            = var.location
  resource_group_name = var.workload_resource_group_name
  subnet_id           = azurerm_subnet.this[var.private_endpoint_subnet_key].id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.storage_account_name}-blob"
    private_connection_resource_id = azurerm_storage_account.workload.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}
