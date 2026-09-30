# Demo pull requests

Deliberately unsafe changes, opened to show what CI does with them, then closed without merging. Only real CI
output is recorded here.

## #9 — [demo] allow RDP from the Internet

- **Change:** the root `nsg_rules` default gains an Inbound Allow rule for TCP 3389 from `Internet` on
  `online/snet-app` ("temporary vendor access").
- **PR:** https://github.com/santorest/lab-05-azure-landing-zone/pull/9 (closed, not merged)
- **CI run:** https://github.com/santorest/lab-05-azure-landing-zone/actions/runs/36667187884

| Job | Result |
|---|---|
| terraform (landing-zone) | **failed**: `default_landing_zone` → 0 passed, 1 failed, 3 skipped |
| all 12 other jobs (fmt, 6 modules + bootstrap, tflint, checkov, trivy-config, policy-checks, secrets) | passed |

The failure is the network module's input validation, reached through the root module:

```
Error: Invalid value for variable

  on main.tf line 46, in module "network":
  46:   nsg_rules                    = var.nsg_rules
    ├────────────────
    │ var.nsg_rules is map of list of object with 1 element

Management ports (22, 3389, 5985, 5986) must never be allowed inbound from
the Internet/any source; use Bastion, a VPN or a jump host.
```

**What it shows:**
- The refusal is in the code itself, not only in CI: `terraform plan` or `apply` with this value fails the same
  way on anyone's machine.
- **Checkov and Trivy did not flag the rule.** It is built from a variable through a `for_each` inside a module,
  and neither scanner evaluated that path, so both jobs passed. The static scanners are a second line here;
  the input validation and its tests are the control that caught it.
