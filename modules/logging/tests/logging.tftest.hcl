mock_provider "azurerm" {
  mock_resource "azurerm_log_analytics_workspace" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-management/providers/Microsoft.OperationalInsights/workspaces/log-corp"
    }
  }
  mock_resource "azurerm_sentinel_log_analytics_workspace_onboarding" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-management/providers/Microsoft.OperationalInsights/workspaces/log-corp/providers/Microsoft.SecurityInsights/onboardingStates/default"
    }
  }
  mock_resource "azurerm_key_vault" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-management/providers/Microsoft.KeyVault/vaults/kv-corp-platform"
    }
  }
}

variables {
  prefix              = "corp"
  location            = "eastus2"
  resource_group_name = "rg-corp-management"
  tenant_id           = "00000000-0000-0000-0000-000000000000"
  subscription_id     = "00000000-0000-0000-0000-000000000000"
  key_vault_name      = "kv-corp-platform"
  rules_file          = "../../detections/rules.yaml"
  queries_dir         = "../../detections"
  tags                = { owner = "platform-team", env = "prod", "cost-center" = "cc-001" }
  diagnostic_targets = {
    "nsg-online-snet-app" = {
      resource_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-connectivity/providers/Microsoft.Network/networkSecurityGroups/nsg-corp-online-snet-app"
      category_groups = ["allLogs"]
    }
  }
}

run "workspace_and_sentinel" {
  command = apply

  assert {
    condition     = azurerm_log_analytics_workspace.this.retention_in_days == 90 && azurerm_log_analytics_workspace.this.sku == "PerGB2018"
    error_message = "Workspace: PerGB2018, 90-day retention by default."
  }
  assert {
    condition     = azurerm_sentinel_log_analytics_workspace_onboarding.this.workspace_id == azurerm_log_analytics_workspace.this.id
    error_message = "Sentinel must be onboarded on the workspace."
  }
}

run "five_detections_with_attack_mapping" {
  command = apply

  assert {
    condition     = toset(keys(azurerm_sentinel_alert_rule_scheduled.this)) == toset(["privileged-role-assignment", "nsg-open-to-internet", "conditional-access-change", "mass-resource-deletion", "signin-outside-allowed-countries"])
    error_message = "One scheduled rule per rules.yaml entry (5)."
  }
  assert {
    condition     = alltrue([for r in azurerm_sentinel_alert_rule_scheduled.this : length(r.tactics) > 0 && length(r.techniques) > 0])
    error_message = "Every rule maps to ATT&CK tactics and techniques."
  }
  assert {
    condition     = alltrue([for r in azurerm_sentinel_alert_rule_scheduled.this : length(trimspace(r.query)) > 0 && r.log_analytics_workspace_id == azurerm_log_analytics_workspace.this.id])
    error_message = "Every rule has a non-empty query and runs on the landing-zone workspace."
  }
  assert {
    condition     = length(output.unreferenced_queries) == 0 && length(output.rules_without_tactics) == 0
    error_message = "rules.yaml and *.kql must match one-to-one."
  }
}

run "key_vault_hardened" {
  command = apply

  assert {
    condition     = azurerm_key_vault.this.purge_protection_enabled && azurerm_key_vault.this.public_network_access_enabled == false && azurerm_key_vault.this.rbac_authorization_enabled
    error_message = "Key Vault: purge protection, RBAC, no public access."
  }
}

run "diagnostics_go_to_workspace" {
  command = apply

  assert {
    condition     = azurerm_monitor_diagnostic_setting.activity_log.target_resource_id == "/subscriptions/00000000-0000-0000-0000-000000000000"
    error_message = "Subscription activity log must be exported."
  }
  assert {
    condition     = azurerm_monitor_diagnostic_setting.key_vault.target_resource_id == azurerm_key_vault.this.id
    error_message = "Key Vault logs must be exported."
  }
  assert {
    condition     = toset(keys(azurerm_monitor_diagnostic_setting.targets)) == toset(["nsg-online-snet-app"])
    error_message = "One diagnostic setting per external target."
  }
  assert {
    condition = alltrue(concat(
      [for d in azurerm_monitor_diagnostic_setting.targets : d.log_analytics_workspace_id == azurerm_log_analytics_workspace.this.id],
      [
        azurerm_monitor_diagnostic_setting.activity_log.log_analytics_workspace_id == azurerm_log_analytics_workspace.this.id,
        azurerm_monitor_diagnostic_setting.key_vault.log_analytics_workspace_id == azurerm_log_analytics_workspace.this.id,
      ]
    ))
    error_message = "Every diagnostic setting targets the workspace."
  }
  assert {
    condition     = length(azurerm_monitor_aad_diagnostic_setting.entra) == 1
    error_message = "Entra sign-in/audit logs exported by default."
  }
}

run "entra_diagnostics_can_be_disabled" {
  command = apply
  variables {
    enable_entra_diagnostics = false
  }

  assert {
    condition     = length(azurerm_monitor_aad_diagnostic_setting.entra) == 0
    error_message = "Toggle must remove the tenant diagnostic setting."
  }
}

# --- Review Focus 3: detection drift --------------------------------------------------------

run "orphan_query_and_missing_tactics_fail" {
  command = plan
  variables {
    rules_file  = "tests/fixtures/bad-detections/rules.yaml"
    queries_dir = "tests/fixtures/bad-detections"
  }
  expect_failures = [terraform_data.detection_checks]
}

run "retention_too_short_rejected" {
  command = plan
  variables {
    retention_in_days = 7
  }
  expect_failures = [var.retention_in_days]
}
