# Detections are data: detections/rules.yaml + one *.kql per rule. Drift between them fails the plan.
locals {
  detection_rules       = yamldecode(file(var.rules_file)).rules
  rules                 = { for r in local.detection_rules : r.id => r }
  kql_files             = fileset(var.queries_dir, "*.kql")
  referenced_queries    = toset([for r in local.detection_rules : r.query_file])
  unreferenced_queries  = sort(tolist(setsubtract(local.kql_files, local.referenced_queries)))
  missing_query_files   = sort(tolist(setsubtract(local.referenced_queries, local.kql_files)))
  rules_without_tactics = sort([for r in local.detection_rules : r.id if length(try(r.tactics, [])) == 0])
}

resource "terraform_data" "detection_checks" {
  lifecycle {
    precondition {
      condition     = length(local.unreferenced_queries) == 0 && length(local.missing_query_files) == 0 && length(local.rules_without_tactics) == 0
      error_message = "Detection drift: unreferenced=${jsonencode(local.unreferenced_queries)} missing=${jsonencode(local.missing_query_files)} no_tactics=${jsonencode(local.rules_without_tactics)}"
    }
  }
}

resource "azurerm_sentinel_alert_rule_scheduled" "this" {
  # Skipped: rules whose query file is missing (so file() can't fail before the precondition reports them), and
  # rules that read Entra tables when Entra logs aren't exported (Sentinel rejects queries on missing tables).
  for_each = {
    for k, r in local.rules : k => r
    if contains(local.kql_files, r.query_file) && (var.enable_entra_diagnostics || !try(r.requires_entra, false))
  }
  name                       = each.key
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.this.workspace_id
  display_name               = each.value.name
  description                = each.value.description
  severity                   = each.value.severity
  query                      = file("${var.queries_dir}/${each.value.query_file}")
  query_frequency            = each.value.frequency
  query_period               = each.value.period
  tactics                    = each.value.tactics
  techniques                 = each.value.techniques
  trigger_operator           = "GreaterThan"
  trigger_threshold          = 0
  # The tables a rule queries appear once logs flow; create rules after the settings that feed them. On a
  # brand-new workspace a second apply may still be needed (docs/deploy.md).
  depends_on = [
    terraform_data.detection_checks,
    azurerm_monitor_diagnostic_setting.activity_log,
    azurerm_monitor_aad_diagnostic_setting.entra,
  ]
}
