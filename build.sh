#!/bin/sh
# Usage: build.sh <ClassName>  - turns <ClassName>.hex into <ClassName>.class
# Strips '#' comments, rejects anything that is not hex digits or whitespace,
# then converts the hex digits to raw bytes.
set -e
name="${1:?usage: build.sh <ClassName>}"
hex=$(sed 's/#.*//' "$name.hex")

bad=$(printf '%s\n' "$hex" | grep -n '[^0-9A-Fa-f[:space:]]' || true)
if [ -n "$bad" ]; then
  echo "error: non-hex characters outside comments in $name.hex (line: content):" >&2
  printf '%s\n' "$bad" >&2
  exit 1
fi

digits=$(printf '%s' "$hex" | tr -d '[:space:]' | wc -c | tr -d ' ')
if [ $((digits % 2)) -ne 0 ]; then
  echo "error: odd number of hex digits ($digits) in $name.hex" >&2
  exit 1
fi

printf '%s' "$hex" | xxd -r -p > "$name.class"
echo "$name.class: $((digits / 2)) bytes"
