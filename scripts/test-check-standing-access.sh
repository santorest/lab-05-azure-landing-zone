#!/usr/bin/env bash
# Self-test for check-standing-access.sh: every bad-* fixture must fail, every good-* fixture must pass.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
rc=0
for f in "$here"/testdata/bad-*.tf.fixture; do
  if bash "$here/check-standing-access.sh" "$f" >/dev/null 2>&1; then echo "MISSED: $(basename "$f")"; rc=1; else echo "caught: $(basename "$f")"; fi
done
for f in "$here"/testdata/good-*.tf.fixture; do
  if bash "$here/check-standing-access.sh" "$f" >/dev/null 2>&1; then echo "passed: $(basename "$f")"; else echo "FALSE POSITIVE: $(basename "$f")"; rc=1; fi
done
exit $rc
