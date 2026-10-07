#!/bin/bash
# Usage: check.sh <class-dir>
# Asserts that the patched Inventory in <class-dir> keeps the legacy class's shape:
# the same class declaration, field and method signatures (javap -p -s, ignoring the
# "Compiled from" line), and the same major and minor version as inputs/legacy/Inventory.class.
set -u
dir="${1:?usage: check.sh <class-dir>}"
here=$(cd "$(dirname "$0")" && pwd)
legacy="$here/inputs/legacy"

members() { javap -p -s -cp "$1" Inventory 2>&1 | grep -v '^Compiled from '; }
version() { javap -v -cp "$1" Inventory 2>/dev/null | grep -E '^ *(minor|major) version:' | sed 's/^ *//'; }

want=$(members "$legacy") || { echo "FAIL: javap could not read the legacy Inventory in $legacy" >&2; exit 1; }
got=$(members "$dir") || { echo "FAIL: javap could not read Inventory in $dir" >&2; printf '%s\n' "$got" >&2; exit 1; }
if [ "$want" != "$got" ]; then
  echo "FAIL: fields or methods differ from the legacy class (javap -p -s):" >&2
  diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") >&2
  exit 1
fi

want_v=$(version "$legacy")
got_v=$(version "$dir")
if [ -z "$got_v" ] || [ "$want_v" != "$got_v" ]; then
  echo "FAIL: class file version differs: legacy [$(echo $want_v)], patched [$(echo $got_v)]" >&2
  exit 1
fi

echo "PASS: Inventory has the legacy class's members and version ($(echo $got_v))"
exit 0
