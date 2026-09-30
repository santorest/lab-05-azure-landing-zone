mock_provider "azurerm" {}

mock_provider "azuread" {
  mock_resource "azuread_group" {
    defaults = {
      object_id = "33333333-3333-3333-3333-333333333333"
    }
  }
}

variables {
  prefix          = "corp"
  subscription_id = "00000000-0000-0000-0000-000000000000"
}

run "conditional_access_is_report_only" {
  command = apply

  assert {
    condition = alltrue([
      for p in [azuread_conditional_access_policy.mfa_admins, azuread_conditional_access_policy.mfa_all_users, azuread_conditional_access_policy.block_legacy_auth] :
      p.state == "enabledForReportingButNotEnforced"
    ])
    error_message = "All CA policies start in report-only mode."
  }
  assert {
    condition     = toset(azuread_conditional_access_policy.block_legacy_auth.conditions[0].client_app_types) == toset(["exchangeActiveSync", "other"]) && toset(azuread_conditional_access_policy.block_legacy_auth.grant_controls[0].built_in_controls) == toset(["block"])
    error_message = "Legacy-auth policy must block exchangeActiveSync and other clients."
  }
  assert {
    condition     = contains(azuread_conditional_access_policy.mfa_admins.conditions[0].users[0].included_roles, "62e90394-69f5-4237-9190-012177145e10")
    error_message = "Admin MFA policy must include Global Administrator."
  }
  assert {
    condition     = contains(azuread_conditional_access_policy.mfa_all_users.conditions[0].users[0].included_users, "All") && toset(azuread_conditional_access_policy.mfa_all_users.grant_controls[0].built_in_controls) == toset(["mfa"])
    error_message = "All-users policy must require MFA for everyone."
  }
}

run "break_glass_excluded_everywhere" {
  command = apply
  variables {
    break_glass_group_id = "22222222-2222-2222-2222-222222222222"
  }

  assert {
    condition = alltrue([
      for p in [azuread_conditional_access_policy.mfa_admins, azuread_conditional_access_policy.mfa_all_users, azuread_conditional_access_policy.block_legacy_auth] :
      contains(p.conditions[0].users[0].excluded_groups, "22222222-2222-2222-2222-222222222222")
    ])
    error_message = "Break-glass group must be excluded from every CA policy."
  }
}

run "privileged_access_is_eligible_only" {
  command = apply

  assert {
    condition = toset([for a in azurerm_pim_eligible_role_assignment.subscription : a.role_definition_id]) == toset([
      "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/8e3af657-a8ff-443c-a75c-2fe8c4bcb635",
      "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/18d7d88d-d35e-4fb5-a5c3-7773c20a72d9",
    ])
    error_message = "Owner and User Access Administrator are PIM-eligible at subscription scope."
  }
  assert {
    condition     = alltrue([for a in azurerm_pim_eligible_role_assignment.subscription : a.principal_id == azuread_group.this["platform-admins"].object_id && a.schedule[0].expiration[0].duration_days == 365])
    error_message = "Eligibility goes to platform-admins and expires (365 days by default)."
  }
  assert {
    condition     = azuread_directory_role_eligibility_schedule_request.global_admin.role_definition_id == "62e90394-69f5-4237-9190-012177145e10" && azuread_directory_role_eligibility_schedule_request.global_admin.directory_scope_id == "/"
    error_message = "Global Administrator is eligible, tenant-wide."
  }
  assert {
    condition     = azuread_group.this["platform-admins"].assignable_to_role
    error_message = "Only a role-assignable group can hold Entra role eligibility."
  }
}

# --- Review Focus 4 -------------------------------------------------------------------------

run "enforcing_without_break_glass_rejected" {
  command = plan
  variables {
    ca_state = "enabled"
  }
  expect_failures = [var.ca_state]
}

run "misspelt_state_rejected" {
  command = plan
  variables {
    ca_state = "reportOnly"
  }
  expect_failures = [var.ca_state]
}

run "enforcing_with_break_glass_allowed" {
  command = plan
  variables {
    ca_state             = "enabled"
    break_glass_group_id = "22222222-2222-2222-2222-222222222222"
  }
}
