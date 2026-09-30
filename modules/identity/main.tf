# Identity: groups, Conditional Access (report-only by default) and PIM eligibility — no standing admin access.
locals {
  groups = {
    "platform-admins"       = { description = "Eligible for Owner/UAA and Global Administrator via PIM", role_assignable = true }
    "security-operations"   = { description = "Sentinel responders", role_assignable = false }
    "workload-contributors" = { description = "Deploy workloads in landing zones", role_assignable = false }
  }
  excluded_groups = var.break_glass_group_id == null ? [] : [var.break_glass_group_id]
  # Entra built-in role template IDs (verified on Microsoft Learn, 2026-09-29).
  admin_roles = [
    "62e90394-69f5-4237-9190-012177145e10", # Global Administrator
    "e8611ab8-c189-46e8-94e1-60213ab1f814", # Privileged Role Administrator
    "194ae4cb-b126-40b2-bd5b-6091b380977d", # Security Administrator
    "fe930be7-5e62-47db-91af-98c3a49a38b1", # User Administrator
  ]
  subscription_roles = {
    owner = "8e3af657-a8ff-443c-a75c-2fe8c4bcb635" # Owner
    uaa   = "18d7d88d-d35e-4fb5-a5c3-7773c20a72d9" # User Access Administrator
  }
}

resource "azuread_group" "this" {
  for_each           = local.groups
  display_name       = "grp-${var.prefix}-${each.key}"
  description        = each.value.description
  security_enabled   = true
  assignable_to_role = each.value.role_assignable
}

resource "azuread_conditional_access_policy" "mfa_admins" {
  display_name = "${upper(var.prefix)}-CA01 Require MFA for admin roles"
  state        = var.ca_state

  conditions {
    client_app_types = ["all"]
    applications {
      included_applications = ["All"]
    }
    users {
      included_roles  = local.admin_roles
      excluded_groups = local.excluded_groups
    }
  }

  grant_controls {
    operator          = "OR"
    built_in_controls = ["mfa"]
  }
}

resource "azuread_conditional_access_policy" "mfa_all_users" {
  display_name = "${upper(var.prefix)}-CA02 Require MFA for all users"
  state        = var.ca_state

  conditions {
    client_app_types = ["all"]
    applications {
      included_applications = ["All"]
    }
    users {
      included_users  = ["All"]
      excluded_groups = local.excluded_groups
    }
  }

  grant_controls {
    operator          = "OR"
    built_in_controls = ["mfa"]
  }
}

resource "azuread_conditional_access_policy" "block_legacy_auth" {
  display_name = "${upper(var.prefix)}-CA03 Block legacy authentication"
  state        = var.ca_state

  conditions {
    client_app_types = ["exchangeActiveSync", "other"]
    applications {
      included_applications = ["All"]
    }
    users {
      included_users  = ["All"]
      excluded_groups = local.excluded_groups
    }
  }

  grant_controls {
    operator          = "OR"
    built_in_controls = ["block"]
  }
}

resource "azurerm_pim_eligible_role_assignment" "subscription" {
  for_each           = local.subscription_roles
  scope              = "/subscriptions/${var.subscription_id}"
  role_definition_id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${each.value}"
  principal_id       = azuread_group.this["platform-admins"].object_id
  justification      = "Landing zone: privileged access is eligible-only (PIM)."

  schedule {
    expiration {
      duration_days = var.pim_eligibility_days
    }
  }
}

resource "azuread_directory_role_eligibility_schedule_request" "global_admin" {
  role_definition_id = "62e90394-69f5-4237-9190-012177145e10"
  principal_id       = azuread_group.this["platform-admins"].object_id
  directory_scope_id = "/"
  justification      = "Landing zone: Global Administrator is eligible-only (PIM)."
}
