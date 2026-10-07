#!/bin/bash
# Usage: check.sh <class-dir>
# Structural checks on Rpn in <class-dir>:
#   - at least 3 static methods besides main
#   - at least 20 StackMapTable entries summed over all methods
#   - the operand stack is a double[] (newarray double) and ^ uses Math.pow
#   - no library parsing or tokenizing: the constant pool must not reference
#     parse* / valueOf(String) / decode, Double or Float string constructors,
#     split / matches / regex, Scanner or any java/util class, StringTokenizer,
#     StreamTokenizer, java/text, BigDecimal / BigInteger, or javax/script
set -u
dir="${1:?usage: check.sh <class-dir>}"
fail=0
v=$(javap -v -p -cp "$dir" Rpn 2>&1) || { echo "FAIL: javap could not read Rpn in $dir" >&2; printf '%s\n' "$v" >&2; exit 1; }
sig=$(javap -p -cp "$dir" Rpn 2>&1) || { echo "FAIL: javap -p failed" >&2; exit 1; }
code=$(javap -c -p -cp "$dir" Rpn 2>&1) || { echo "FAIL: javap -c failed" >&2; exit 1; }

statics=$(printf '%s\n' "$sig" | grep -E '^  .*\bstatic\b.*\(.*\)' | grep -vE '[ ]main\(java\.lang\.String\[\]\)' | wc -l | tr -d ' ')
if [ "$statics" -ge 3 ]; then echo "PASS: $statics static methods besides main"
else echo "FAIL: need at least 3 static methods besides main, found $statics" >&2; fail=1; fi

frames=$(printf '%s\n' "$v" | sed -n 's/.*StackMapTable: number_of_entries = \([0-9][0-9]*\).*/\1/p' | awk '{ s += $1 } END { print s + 0 }')
if [ "$frames" -ge 20 ]; then echo "PASS: $frames StackMapTable entries"
else echo "FAIL: need at least 20 StackMapTable entries in total, found $frames" >&2; fail=1; fi

if printf '%s\n' "$code" | grep -Eq 'newarray[[:space:]]+double'; then echo "PASS: allocates a double[]"
else echo "FAIL: no 'newarray double' instruction (the stack must be a double[])" >&2; fail=1; fi

if printf '%s\n' "$v" | grep -q 'java/lang/Math\.pow:(DD)D'; then echo "PASS: references Math.pow"
else echo "FAIL: no reference to java/lang/Math.pow:(DD)D" >&2; fail=1; fi

pool=$(printf '%s\n' "$v" | awk '/^Constant pool:/ { p = 1; next } p && /^\{/ { exit } p { print }')
bad=$(printf '%s\n' "$pool" | grep -E \
  -e '= Utf8 +(parse[A-Za-z]*|decode|split|matches|replaceAll|replaceFirst)$' \
  -e 'valueOf:\(Ljava/lang/String;' \
  -e 'java/lang/(Double|Float)\."<init>":\(Ljava/lang/String;\)' \
  -e 'java/util/' -e 'StringTokenizer' -e 'StreamTokenizer' -e 'java/text/' \
  -e 'java/math/' -e 'javax/script' -e 'java/lang/reflect' -e 'java/lang/invoke/MethodHandles\$Lookup\.find')
if [ -z "$bad" ]; then echo "PASS: no forbidden parsing/tokenizing references in the constant pool"
else echo "FAIL: forbidden constant pool references:" >&2; printf '%s\n' "$bad" >&2; fail=1; fi

exit $fail
