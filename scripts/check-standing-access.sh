#!/usr/bin/env bash
# Fails if Terraform code grants standing (non-PIM) privileged access.
set -euo pipefail
if [ "$#" -eq 0 ]; then mapfile -t files < <(git ls-files '*.tf'); else files=("$@"); fi
pattern='resource "(azurerm_pim_active_role_assignment|azuread_directory_role_assignment|azuread_directory_role_member)"|role_definition_name *= *"(Owner|User Access Administrator)"'
if grep -nE "$pattern" "${files[@]}"; then
  echo "Standing privileged access found: use PIM eligible assignments (modules/identity)." >&2
  exit 1
fi
echo "OK: no standing privileged access in ${#files[@]} files."
