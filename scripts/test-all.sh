#!/usr/bin/env bash
# Runs what CI's terraform jobs run, locally: fmt, then init/validate/test in every root and module.
set -euo pipefail
dirs=(bootstrap modules/governance modules/network modules/firewall modules/logging modules/identity landing-zone)
terraform fmt -check -recursive
for d in "${dirs[@]}"; do
  terraform -chdir="$d" init -backend=false -input=false -no-color >/dev/null
  terraform -chdir="$d" validate -no-color >/dev/null
  printf '%-20s %s\n' "$d" "$(terraform -chdir="$d" test -no-color | tail -n 1)"
done
bash scripts/check-standing-access.sh
