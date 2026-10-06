#!/bin/bash
# Usage: check.sh <class-dir>
# Extra grader for task 03-counter: uses `javap -p -s` to assert that
# <class-dir>/Counter.class declares every required member with the exact
# access flags and descriptor. Extra members are allowed. Exits non-zero on
# any mismatch.

set -u
dir="${1:?usage: check.sh <class-dir>}"

out=$(javap -p -s -cp "$dir" Counter 2>&1) || {
  echo "FAIL javap could not read Counter in $dir:" >&2
  printf '%s\n' "$out" >&2
  exit 1
}

# Pair each member declaration with its descriptor line: "decl|descriptor".
pairs=$(printf '%s\n' "$out" | awk '
  /^  [^ ]/ { decl = substr($0, 3); next }
  /^    descriptor: / { sub(/^    descriptor: /, ""); print decl "|" $0; decl = "" }
')

fail=0

if ! printf '%s\n' "$out" | grep -qFx 'public class Counter {'; then
  echo "FAIL class header: want [public class Counter {] (public, extends Object, no interfaces)"
  fail=1
fi

while IFS= read -r want; do
  [ -n "$want" ] || continue
  if printf '%s\n' "$pairs" | grep -qFx "$want"; then
    echo "ok   $want"
  else
    echo "FAIL missing or wrong: $want"
    fail=1
  fi
done <<'WANT'
private int count;|I
private final java.lang.String name;|Ljava/lang/String;
public Counter(java.lang.String);|(Ljava/lang/String;)V
public void increment();|()V
public int get();|()I
public java.lang.String toString();|()Ljava/lang/String;
public static void main(java.lang.String[]);|([Ljava/lang/String;)V
WANT

if [ "$fail" -ne 0 ]; then
  echo "members found by javap -p -s:"
  printf '%s\n' "$pairs" | sed 's/^/  /'
  exit 1
fi
echo "Counter: all required members present"
