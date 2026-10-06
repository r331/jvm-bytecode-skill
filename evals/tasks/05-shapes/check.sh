#!/bin/bash
# Usage: check.sh <class-dir>
# Structural checks via javap for the 05-shapes task:
# - all four classes are major version 55
# - Shape is an interface with abstract area()D and name()Ljava/lang/String;
# - Circle and Square implement Shape and have a (D)V constructor
# - Shapes.main calls Shape.area and Shape.name via invokeinterface
# Exits non-zero (listing every failed check) otherwise.

set -u
dir="${1:?usage: check.sh <class-dir>}"
fail=0

err() { echo "check: $*" >&2; fail=1; }

# has <text> <description> <fixed-string>: assert text contains the string
has() {
  if ! printf '%s\n' "$1" | grep -qF -- "$3"; then err "$2: missing '$3'"; fi
}

for c in Shape Circle Square Shapes; do
  if [ ! -f "$dir/$c.class" ]; then err "$dir/$c.class not found"; fi
done
[ "$fail" -eq 0 ] || exit 1

for c in Shape Circle Square Shapes; do
  v=$(javap -v -p -cp "$dir" "$c" 2>&1) || { err "javap failed on $c"; continue; }
  has "$v" "$c" "major version: 55"
done

shape=$(javap -v -p -cp "$dir" Shape 2>&1)
has "$shape" "Shape" "public interface Shape"
has "$shape" "Shape" "ACC_INTERFACE"
has "$shape" "Shape" "ACC_ABSTRACT"
has "$shape" "Shape" "public abstract double area();"
has "$shape" "Shape" "public abstract java.lang.String name();"

for c in Circle Square; do
  out=$(javap -p -cp "$dir" "$c" 2>&1)
  if ! printf '%s\n' "$out" | grep -qE "^public( final)? class $c implements Shape \{"; then
    err "$c: not a public class implementing Shape"
  fi
  has "$out" "$c" "public $c(double);"
  has "$out" "$c" "public double area();"
  has "$out" "$c" "public java.lang.String name();"
done

# Disassembly of main only: from its declaration to the next blank line.
main=$(javap -c -p -cp "$dir" Shapes 2>&1 | awk '/public static void main\(java.lang.String\[\]\)/{f=1} f{print} f&&/^$/{exit}')
[ -n "$main" ] || err "Shapes: no public static void main(java.lang.String[])"
if ! printf '%s\n' "$main" | grep -E 'invokeinterface' | grep -qF 'InterfaceMethod Shape.area:()D'; then
  err "Shapes.main: no invokeinterface Shape.area:()D"
fi
if ! printf '%s\n' "$main" | grep -E 'invokeinterface' | grep -qF 'InterfaceMethod Shape.name:()Ljava/lang/String;'; then
  err "Shapes.main: no invokeinterface Shape.name:()Ljava/lang/String;"
fi

[ "$fail" -eq 0 ] && echo "check: ok"
exit "$fail"
