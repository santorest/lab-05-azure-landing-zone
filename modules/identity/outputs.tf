output "group_object_ids" {
  description = "Object IDs of platform-admins, security-operations and workload-contributors."
  value       = { for k, g in azuread_group.this : k => g.object_id }
}

output "conditional_access_policy_ids" {
  description = "Conditional Access policy IDs."
  value = {
    mfa_admins        = azuread_conditional_access_policy.mfa_admins.id
    mfa_all_users     = azuread_conditional_access_policy.mfa_all_users.id
    block_legacy_auth = azuread_conditional_access_policy.block_legacy_auth.id
  }
}
