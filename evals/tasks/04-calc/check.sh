#!/bin/bash
# Usage: check.sh <class-dir>
# Asserts that Calc.main in <class-dir> dispatches with a tableswitch or lookupswitch instruction.
set -u
dir="${1:?usage: check.sh <class-dir>}"
out=$(javap -c -p -cp "$dir" Calc 2>&1) || { echo "FAIL: javap could not read Calc in $dir" >&2; printf '%s\n' "$out" >&2; exit 1; }
main=$(printf '%s\n' "$out" | awk '
  /^  [^ ].*[ ]main\(java\.lang\.String\[\]\);$/ { inmain = 1; print; next }
  inmain && /^  [^ ]/ { inmain = 0 }
  inmain && /^}/ { inmain = 0 }
  inmain { print }')
if [ -z "$main" ]; then
  echo "FAIL: no main(java.lang.String[]) method found in Calc" >&2
  exit 1
fi
if printf '%s\n' "$main" | grep -Eq '^ +[0-9]+: (tableswitch|lookupswitch)'; then
  echo "PASS: Calc.main uses $(printf '%s\n' "$main" | grep -Eo '(tableswitch|lookupswitch)' | head -1)"
  exit 0
fi
echo "FAIL: Calc.main contains no tableswitch or lookupswitch instruction" >&2
exit 1
