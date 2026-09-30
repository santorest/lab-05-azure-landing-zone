# Mock providers still run the real provider's argument validation, so IDs that other resources
# consume must look like real Azure resource IDs.
mock_provider "azurerm" {
  mock_resource "azurerm_storage_account" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-tfstate/providers/Microsoft.Storage/storageAccounts/corptfstate01"
    }
  }
}

variables {
  prefix               = "corp"
  location             = "eastus2"
  subscription_id      = "00000000-0000-0000-0000-000000000000"
  deployer_ip          = "203.0.113.10"
  storage_account_name = "corptfstate01"
  tags                 = { owner = "platform-team", env = "prod", "cost-center" = "cc-001" }
}

run "state_storage_is_locked_down" {
  command = apply

  assert {
    condition     = azurerm_storage_account.state.shared_access_key_enabled == false
    error_message = "State storage must use Entra auth only (shared keys off)."
  }
  assert {
    condition     = azurerm_storage_account.state.min_tls_version == "TLS1_2"
    error_message = "TLS 1.2 minimum."
  }
  assert {
    condition     = azurerm_storage_account.state.blob_properties[0].versioning_enabled && azurerm_storage_account.state.blob_properties[0].delete_retention_policy[0].days >= 7
    error_message = "State blobs need versioning and soft delete."
  }
  assert {
    condition     = azurerm_storage_account.state.network_rules[0].default_action == "Deny" && azurerm_storage_account.state.network_rules[0].ip_rules == toset(["203.0.113.10"])
    error_message = "Only the deployer IP may reach the state account."
  }
  assert {
    condition     = azurerm_storage_container.tfstate.container_access_type == "private"
    error_message = "State container must be private."
  }
}

run "deployer_ip_must_be_single_public_ipv4" {
  command = plan
  variables {
    deployer_ip = "0.0.0.0/0"
  }
  expect_failures = [var.deployer_ip]
}

run "deployer_ip_rejects_private_range" {
  command = plan
  variables {
    deployer_ip = "10.0.0.5"
  }
  expect_failures = [var.deployer_ip]
}
