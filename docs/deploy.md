# Deploying the landing zone

> This lab is a **reference design**: it has never been applied to Azure. This page is the procedure to
> follow if you deploy it. Expect small fixes at apply time: the offline tests can't catch everything Azure
> checks (see the write-up's "What was verified and what wasn't").

## Prerequisites

- An Azure subscription you control (a new account's credit covers a short deployment; see
  [teardown-and-cost.md](teardown-and-cost.md) for estimates).
- Entra ID **P1** for Conditional Access and **P2** for PIM (a 30-day P2 trial works). Without them, set
  `ca_state = "disabled"` and remove the `identity` module, and document the design instead.
- The deployer needs **Owner** on the subscription, rights to create management groups at the tenant root,
  **Privileged Role Administrator** (PIM) and **Conditional Access Administrator** in Entra.
- Terraform ≥ 1.9 and the Azure CLI (`az login`).
- A **break-glass group** with one or two emergency-access accounts, created by hand outside Terraform (strong
  unique passwords/FIDO2 keys, monitored sign-ins). You need its object ID before enforcing Conditional Access.

## 1. Bootstrap the state backend (once, local state)

```bash
cd bootstrap
terraform init
terraform apply \
  -var subscription_id=<subscription-guid> \
  -var storage_account_name=<globally-unique-name> \
  -var deployer_ip=$(curl -s https://api.ipify.org) \
  -var 'tags={owner="platform-team",env="prod",cost-center="cc-001"}'
```

The account only accepts traffic from `deployer_ip`, uses Entra auth (no shared keys) and gets a
CanNotDelete lock. Your user needs **Storage Blob Data Contributor** on it to read and write state.

## 2. Configure the landing zone

```bash
cd ../landing-zone
cp backend.hcl.example backend.hcl                  # storage_account_name from the bootstrap output
cp terraform.tfvars.example terraform.tfvars       # your IDs, globally unique names, contacts
terraform init -backend-config=backend.hcl
terraform plan -out=lz.tfplan
```

Read the plan. It creates management groups, policy assignments, a budget, three resource groups, three
VNets, NSGs, a storage account and Key Vault behind private endpoints, a Log Analytics workspace with
Sentinel and five analytics rules, three Entra groups, three Conditional Access policies in report-only
mode and PIM eligibility.

## 3. Apply

```bash
terraform apply lz.tfplan
```

Management groups and policy assignments can take several minutes to propagate. If an assignment fails
because a management group isn't visible yet, run `terraform apply` again.

## 4. CI with OIDC (no stored secrets)

To plan from GitHub Actions instead of a laptop:

1. Create an app registration and a **federated credential** with issuer
   `https://token.actions.githubusercontent.com`, audience `api://AzureADTokenExchange` and subject
   `repo:santorest/lab-05-azure-landing-zone:ref:refs/heads/main` (and one for `pull_request` if PRs should plan).
2. Give it **Reader** on the subscription for plans (and a separate, approval-gated identity for applies).
3. In the workflow: `permissions: id-token: write`, then `azure/login` with `client-id`, `tenant-id` and
   `subscription-id` only (no client secret), and set `ARM_USE_OIDC=true` for Terraform.

This repository's CI never logs in to Azure: all its checks are offline.

## 5. After applying: checks worth recording

| Check | How | Expected |
|---|---|---|
| Deny public IP | `az network public-ip create -g rg-corp-workload -n test-pip` | Fails with `RequestDisallowedByPolicy` |
| Allowed locations | Create any resource in a region not in `allowed_locations` | Denied by policy |
| Required tags | Create a resource group without `owner` | Denied by policy |
| Policy compliance | `az policy state summarize --management-group corp` | Non-compliant resources listed, if any |
| Private endpoints | From a VM in a spoke: `nslookup <account>.blob.core.windows.net` | Resolves to 10.2.1.x |
| NSG default deny | Effective security rules on any NIC | Only the rules you added, then deny-all |
| Conditional Access | Entra sign-in logs → *Report-only* tab, for at least a week | See who would be blocked or prompted |
| PIM | Activate Owner as a platform-admins member | Activation needs justification; expires |
| Sentinel | Assign Owner to a test user outside PIM | "Privileged Azure role assigned" incident |
| State logging | Add the state account's blob service to `diagnostic_targets` | Reads/writes of state are logged |

Record each result (date, command, output) before you describe the deployment as tested.

## 6. Enforcing Conditional Access

Only after the report-only review: set `break_glass_group_id`, then `ca_state = "enabled"`, then apply. The
`identity` module refuses `enabled` without a break-glass group.
