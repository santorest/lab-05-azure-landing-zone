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

provider "azuread" {
  tenant_id = var.tenant_id
}
