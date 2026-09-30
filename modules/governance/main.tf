# Management-group hierarchy (CAF-style): corp → platform/landing-zones/sandbox → level 2.
locals {
  level1 = ["platform", "landing-zones", "sandbox"]
  level2 = {
    connectivity = "platform"
    management   = "platform"
    identity     = "platform"
    online       = "landing-zones"
    internal     = "landing-zones"
  }
}

resource "azurerm_management_group" "root" {
  name         = var.prefix
  display_name = title(var.prefix)
}

resource "azurerm_management_group" "level1" {
  for_each                   = toset(local.level1)
  name                       = "${var.prefix}-${each.key}"
  display_name               = "${title(var.prefix)} ${title(replace(each.key, "-", " "))}"
  parent_management_group_id = azurerm_management_group.root.id
}

resource "azurerm_management_group" "level2" {
  for_each                   = local.level2
  name                       = "${var.prefix}-${each.key}"
  display_name               = "${title(var.prefix)} ${title(each.key)}"
  parent_management_group_id = azurerm_management_group.level1[each.value].id
}

locals {
  management_group_ids = merge(
    { corp = azurerm_management_group.root.id },
    { for k, mg in azurerm_management_group.level1 : k => mg.id },
    { for k, mg in azurerm_management_group.level2 : k => mg.id },
  )
}

resource "azurerm_management_group_subscription_association" "this" {
  count               = var.subscription_placement == null ? 0 : 1
  management_group_id = local.management_group_ids[var.subscription_placement]
  subscription_id     = "/subscriptions/${var.subscription_id}"
}
