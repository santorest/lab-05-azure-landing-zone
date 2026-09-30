#!/usr/bin/env bash
# Fails if Terraform code grants standing (non-PIM) privileged access:
#   - any active-assignment resource type (PIM active, Entra directory role assignment/member), or
#   - an azurerm_role_assignment block naming Owner, User Access Administrator or Role Based Access Control
#     Administrator, by name (any case) or by role-definition GUID.
# PIM *eligible* assignments are the intended pattern and are not flagged.
# Limitation: a privileged role passed in only through a variable or local can't be seen by a text check;
# modules/identity's tests cover the eligible-only design itself.
set -euo pipefail
if [ "$#" -eq 0 ]; then mapfile -t files < <(git ls-files '*.tf'); else files=("$@"); fi

found=$(awk '
  BEGIN { IGNORECASE = 1 }
  /^[[:space:]]*resource[[:space:]]+"/ {
    split($0, parts, "\"")
    type = parts[2]; depth = 0; inblock = 1
    if (type ~ /^(azurerm_pim_active_role_assignment|azuread_directory_role_assignment|azuread_directory_role_member)$/)
      print FILENAME ":" FNR ": active assignment resource " type
  }
  inblock {
    if (type == "azurerm_role_assignment" &&
        ($0 ~ /"(owner|user access administrator|role based access control administrator)"/ ||
         $0 ~ /(8e3af657-a8ff-443c-a75c-2fe8c4bcb635|18d7d88d-d35e-4fb5-a5c3-7773c20a72d9|f58310d9-a9f6-439a-9e8d-f62e7b41a168)/))
      print FILENAME ":" FNR ": " $0
    depth += gsub(/{/, "{"); depth -= gsub(/}/, "}")
    if (depth <= 0 && $0 ~ /}/) inblock = 0
  }
' "${files[@]}")

if [ -n "$found" ]; then
  echo "$found"
  echo "Standing privileged access found: use PIM eligible assignments (modules/identity)." >&2
  exit 1
fi
echo "OK: no standing privileged access in ${#files[@]} files."
