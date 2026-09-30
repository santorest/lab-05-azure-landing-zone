# Remote-state storage for the landing zone. Applied once with local state (see docs/deploy.md).
provider "azurerm" {
  features {
    # Storage accounts here have public network access off (workload) or IP-restricted (state), so the
    # deployer can't reach their data plane: manage them through ARM only.
    storage {
      data_plane_available = false
    }
  }
  subscription_id     = var.subscription_id
  storage_use_azuread = true
}

resource "azurerm_resource_group" "state" {
  name     = "rg-${var.prefix}-tfstate"
  location = var.location
  tags     = var.tags
}

# prevent_destroy would also block the documented teardown and `terraform test`; the CanNotDelete
# lock below protects the account from anyone, not only from Terraform (security/EXCEPTIONS.md).
# tflint-ignore: azurerm_resources_missing_prevent_destroy
resource "azurerm_storage_account" "state" {
  #checkov:skip=CKV_AZURE_59:Bootstrap runs from the deployer's machine before any network exists; network_rules deny all but deployer_ip.
  #checkov:skip=CKV2_AZURE_33:Same chicken-and-egg: no VNet exists at bootstrap time; access is limited to deployer_ip and Entra auth.
  #checkov:skip=CKV_AZURE_33:Queue service is not used; queue logging would also need shared-key access, which is disabled.
  #checkov:skip=CKV_AZURE_206:ZRS (zone-redundant) by design; geo-replication would copy state outside allowed_locations.
  #checkov:skip=CKV2_AZURE_1:Platform-managed keys plus infrastructure encryption; CMK needs a vault key and rotation process (revisit for regulated data).
  name                              = var.storage_account_name
  resource_group_name               = azurerm_resource_group.state.name
  location                          = azurerm_resource_group.state.location
  account_tier                      = "Standard"
  account_replication_type          = "ZRS"
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
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
      days = 30
    }
    container_delete_retention_policy {
      days = 30
    }
  }

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
    ip_rules       = [var.deployer_ip]
  }
}

# Protected by the account lock, versioning and container soft delete (see the account above).
# tflint-ignore: azurerm_resources_missing_prevent_destroy
resource "azurerm_storage_container" "tfstate" {
  #checkov:skip=CKV2_AZURE_21:The Log Analytics workspace doesn't exist at bootstrap time; add the state account to diagnostic_targets after the landing zone is applied.
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

# Remove this lock deliberately (docs/teardown-and-cost.md) before destroying the state account.
resource "azurerm_management_lock" "state" {
  name       = "lock-${var.storage_account_name}"
  scope      = azurerm_storage_account.state.id
  lock_level = "CanNotDelete"
  notes      = "Terraform state for the landing zone."
}
