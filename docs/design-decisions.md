# Design decisions

Each decision states the choice, what it costs and when to revisit it.

## 1. NSGs are the enforced design; Azure Firewall is optional

- **Choice:** every subnet that can take an NSG gets one ending in an explicit deny-all inbound rule
  (priority 4096). The network module's input validation refuses any rule that opens 22, 3389, 5985 or 5986
  to the Internet or any source. Azure Firewall Basic is a module behind `enable_firewall` (default `false`).
- **Why:** NSGs cost nothing and cover inbound exposure, which is the main risk in a small landing zone. A
  firewall adds central egress control and logging for ~$10/day (Basic).
- **Trade-off:** no central egress filtering or FQDN rules without the firewall; spokes reach the Internet
  through Azure's default outbound path.
- **Revisit when:** workloads need egress allow-lists, or a compliance framework requires central inspection.

## 2. Conditional Access starts report-only, with a break-glass exclusion

- **Choice:** three policies (MFA for admin roles, MFA for all users, block legacy authentication), all
  `enabledForReportingButNotEnforced`. Enforcing (`ca_state = "enabled"`) is refused unless
  `break_glass_group_id` is set, and that group is excluded from every policy.
- **Why:** enforcing an untested policy can lock every administrator out of the tenant. Report-only shows in
  the sign-in logs who would be affected.
- **Trade-off:** until enforced, the policies protect nothing. The deploy guide asks for at least a week of
  report-only review.
- **Break-glass group is an input, not a resource:** emergency accounts are managed by hand, outside any
  automation that could break them.

## 3. PIM eligibility, never standing admin access

- **Choice:** Owner and User Access Administrator (subscription) and Global Administrator (tenant) are
  *eligible* assignments for the `platform-admins` group. The two Azure role eligibilities expire after 365
  days; the Global Administrator eligibility can't carry an expiry in the azuread provider, so the tenant's PIM
  role settings decide its duration (set a maximum there). No active privileged assignment exists in the code;
  `scripts/check-standing-access.sh` fails CI if one appears (by role name in any case, or by role ID).
- **Why:** standing admin rights are the most valuable thing an attacker can steal. Eligibility needs an
  activation with justification, which is logged.
- **Trade-off:** needs Entra ID P2 and adds a step for admins. The DeployIfNotExists policy's managed identity
  holds two narrow roles (Log Analytics Contributor, Monitoring Contributor) permanently, because policy
  remediation can't activate PIM.

## 4. Custom deny-public-IP policy with a resource-group exemption

- **Choice:** a custom policy denies every `Microsoft.Network/publicIPAddresses`, assigned at the root
  management group. When the firewall is enabled, the connectivity **resource group** gets a waiver.
- **Why the resource group, not the `connectivity` management group:** this landing zone uses one
  subscription, and a subscription sits under exactly one management group (`online` by default). An
  exemption on `connectivity` would never apply to it.
- **Trade-off:** anything else in the connectivity resource group could also get a public IP while the
  firewall is on. With several subscriptions, move the exemption to the connectivity management group.

## 5. Partial backend configuration

- **Choice:** `backend "azurerm" {}` with values in a git-ignored `backend.hcl`, Entra authentication
  (`use_azuread_auth = true`), and a state account that only the deployer's IP can reach.
- **Why:** no storage account names or keys in the repository, and no shared keys at all.
- **Trade-off:** bootstrap is a separate, manual first step with local state.

## 6. Detections as data

- **Choice:** `detections/rules.yaml` holds each rule's metadata and ATT&CK mapping; each query is a `.kql`
  file. The logging module fails the plan if a query file is orphaned or missing, or a rule has no tactic.
- **Why:** detections are reviewed like code, and drift between metadata and queries can't slip in.
- **Trade-off:** the KQL is only checked for existence offline. Whether it parses and fires needs a
  workspace with data (see the deploy guide's checks).

## 7. Offline validation only

- **Choice:** CI runs `terraform fmt`, `validate`, `test` with **mock providers**, tflint, Checkov, Trivy and
  gitleaks. There are no Azure credentials anywhere.
- **Why:** the lab costs nothing, and CI can't break because a subscription lapsed.
- **Trade-off:** mocks don't know Azure's API rules. What only a real `plan`/`apply` would prove is listed in
  the write-up.
- **Test mechanics:** positive tests use `command = apply` against the mocks (no API calls) because generated
  values such as IDs are unknown in plan mode. Mock providers still run the real providers' argument
  validation, so mocked IDs must look like real resource IDs.

## Address plan

| VNet | Address space | Subnet | Prefix | NSG |
|---|---|---|---|---|
| hub | 10.0.0.0/22 | snet-shared | 10.0.0.0/24 | yes |
| | | GatewaySubnet | 10.0.1.0/27 | no (Azure requirement) |
| | | AzureFirewallSubnet (firewall only) | 10.0.2.0/26 | no (Azure requirement) |
| | | AzureFirewallManagementSubnet (firewall only) | 10.0.2.64/26 | no (Azure requirement) |
| online | 10.1.0.0/22 | snet-app | 10.1.0.0/24 | yes |
| internal | 10.2.0.0/22 | snet-app | 10.2.0.0/24 | yes |
| | | snet-private-endpoints | 10.2.1.0/24 | yes |

The /22 blocks don't overlap and leave room for more subnets per VNet. Nothing checks for overlap in code:
Terraform has no CIDR-overlap function, and Azure rejects overlapping peered address spaces at apply time.
