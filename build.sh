#!/bin/sh
# Usage: build.sh [-d <out-dir>] <ClassName>...
#
# Turns each <ClassName>.hex into <ClassName>.class.
# Strips '#' comments, rejects anything that is not hex digits or whitespace,
# then converts the remaining hex digits to raw bytes.
# ClassName may include a path (e.g. com/example/Foo -> com/example/Foo.hex).
# The .class is written next to the .hex, or under <out-dir> keeping the same
# relative path when -d is given (put classes that reference each other in one dir).
# On any error the stale .class from an earlier build is removed, so a failed
# build can never leave an old class behind to be run by mistake.
set -e

usage() { echo "usage: build.sh [-d <out-dir>] <ClassName>..." >&2; exit 2; }

out_dir=
if [ "${1:-}" = "-d" ]; then
  [ -n "${2:-}" ] || usage
  out_dir=$2
  shift 2
fi
[ $# -gt 0 ] || usage

fail() { rm -f "$class"; echo "error: $*" >&2; exit 1; }

for name in "$@"; do
  name=${name%.hex}
  if [ -n "$out_dir" ]; then class="$out_dir/$name.class"; else class="$name.class"; fi

  [ -f "$name.hex" ] || fail "$name.hex: no such file"
  hex=$(sed 's/#.*//' "$name.hex" | tr -d '\r')

  bad=$(printf '%s\n' "$hex" | grep -n '[^0-9A-Fa-f[:space:]]' || true)
  [ -z "$bad" ] || fail "non-hex characters outside comments in $name.hex (line: content):
$bad"

  digits=$(printf '%s' "$hex" | tr -d '[:space:]' | wc -c | tr -d ' ')
  [ "$digits" -gt 0 ] || fail "$name.hex contains no bytes"
  [ $((digits % 2)) -eq 0 ] || fail "odd number of hex digits ($digits) in $name.hex"

  magic=$(printf '%s' "$hex" | tr -d '[:space:]' | cut -c1-8 | tr 'a-f' 'A-F')
  [ "$magic" = "CAFEBABE" ] || fail "$name.hex does not start with CA FE BA BE (got $magic)"

  mkdir -p "$(dirname "$class")"
  tmp="$class.tmp.$$"
  printf '%s' "$hex" | xxd -r -p > "$tmp" || { rm -f "$tmp"; fail "xxd failed on $name.hex"; }
  mv "$tmp" "$class"
  echo "$class: $((digits / 2)) bytes"
done
