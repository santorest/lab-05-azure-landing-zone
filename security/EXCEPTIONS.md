# Scanner exceptions

Every skipped or ignored check is justified here and inline in the code, next to the resource it applies to.
Reviewed 2026-09-29. A new skip needs a row here in the same pull request.

## Checkov

| Check | Resource | Why it does not apply / accepted risk | Revisit when |
|---|---|---|---|
| CKV_AZURE_59 (storage disallows public access) | `bootstrap` `azurerm_storage_account.state` | Bootstrap runs from the deployer's machine before any network exists. `network_rules` deny everything except `deployer_ip`, and shared keys are disabled (Entra auth only). | A private runner or jump host exists: move the state account behind a private endpoint. |
| CKV2_AZURE_33 (storage has a private endpoint) | `bootstrap` `azurerm_storage_account.state` | Same chicken-and-egg as above: the VNets are created by the landing zone whose state this account holds. | As above. |
| CKV_AZURE_33 (queue service logging) | state account, `modules/network` workload account | The queue service is not used. Classic queue logging would also need shared-key access, which is disabled. | A workload starts using queues. |
| CKV_AZURE_206 (geo-replication) | state account, workload account | ZRS (zone-redundant) by design. Geo-replication would copy data to a paired region outside `allowed_locations`. | Disaster recovery requirements name a second allowed region. |
| CKV2_AZURE_1 (customer-managed keys) | state account, workload account | Platform-managed keys with infrastructure (double) encryption. CMK needs a Key Vault key, an identity and a rotation process, which no data in this lab requires. | The account holds regulated data. |
| CKV2_AZURE_21 (blob read logging) | `bootstrap` `azurerm_storage_container.tfstate` | The Log Analytics workspace doesn't exist when bootstrap runs. After the landing zone is applied, add the state account's blob service to `diagnostic_targets`. | Always, as a post-deploy step (docs/deploy.md). |

Fixed instead of skipped: CKV2_AZURE_32 (Key Vault private endpoint). The vault has public network access
disabled, so without a private endpoint nothing could reach it. `modules/logging` now creates the endpoint in
the private-endpoint subnet with the `privatelink.vaultcore.azure.net` zone.

## tflint

| Rule | Resource | Why | Revisit when |
|---|---|---|---|
| `azurerm_resources_missing_prevent_destroy` | state account and container, workload account, Key Vault | `prevent_destroy` can't be set per environment and would block both the documented teardown and `terraform test` (which destroys what it applies). The data is protected instead by a CanNotDelete lock (state account), versioning and soft delete (storage), and purge protection (Key Vault). | A long-lived production environment uses these modules: add locks there too. |

## Trivy

None so far. Ignores go in `.trivyignore.yaml` with a reason and a row here.
