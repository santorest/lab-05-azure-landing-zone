# Teardown and cost

## Cost (estimates)

> **Estimates from Azure list prices (USD), September 2026. Nothing here was measured: the lab was never
> deployed.** Prices vary by region and change; check the [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/)
> before deploying.

| Component | Estimated cost | Notes |
|---|---|---|
| Management groups, Azure Policy, NSGs, VNets, Entra groups | ~$0 | Peering data transfer is billed per GB but negligible at lab volume |
| Budget, Defender for Cloud foundational CSPM (secure score) | $0 | |
| State + workload storage accounts | < $1/month | Tiny amounts of data |
| Private endpoints (storage blob, Key Vault) | ~$0.25/day each | Plus a few cents of processed data |
| Key Vault | ~$0 | Billed per operation |
| Log Analytics + Sentinel | ~$0–5 for a few days | Sentinel has a 31-day free trial on new workspaces; ingestion is small |
| Azure Firewall Basic (`enable_firewall = true`) | **~$10/day** | Plus two public IPs; Standard would be ~$30+/day |
| Entra ID P1/P2 | Licence | A 30-day P2 trial covers Conditional Access and PIM |

**Total, NSG design, deployed 1–3 days:** roughly $5–15. Add ~$10/day with the firewall. The budget alert
(50/80/100 % of `budget_amount`) is the first thing to check after apply.

## Teardown order

1. **Landing zone:**
   ```bash
   cd landing-zone
   terraform destroy
   ```
   - Key Vault has purge protection: the deleted vault stays soft-deleted for 90 days and keeps its name
     reserved. Use a new `key_vault_name` if you redeploy within that time.
   - Deleting a storage account deletes its data, including soft-deleted blobs and old versions.
   - If a management group delete fails because it still contains the subscription, move the subscription
     back to the tenant root group and run `terraform destroy` again.
   - Conditional Access policies and PIM eligibilities are removed with the rest; confirm in Entra that no
     `CORP-CA0x` policy remains.
2. **Bootstrap (state backend), only when nothing else uses it:**
   ```bash
   cd ../bootstrap
   az lock delete --name lock-<storage_account_name> --resource-group rg-corp-tfstate
   terraform destroy
   ```
   The CanNotDelete lock exists to make this a deliberate step.
3. **Check the bill** a day later (Cost Management → Cost analysis, filtered by the `cost-center` tag) and
   record the real total next to the estimate above.
