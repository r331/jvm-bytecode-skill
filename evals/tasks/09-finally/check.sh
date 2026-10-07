#!/bin/bash
# Usage: check.sh <class-dir>
# Structural checks via javap for the 09-finally task, over all methods of Steps:
# - the exception tables have at least 4 entries in total, at least 2 of them with type `any`
#   (finally), and typed entries for IllegalStateException and RuntimeException
# - an athrow instruction is present (the finally handler rethrows the saved exception)
# - no jsr, jsr_w, or ret instruction
# - no `new` of NullPointerException or ArithmeticException (they must be raised by the JVM)
# Exits non-zero (listing every failed check) otherwise.

set -u
dir="${1:?usage: check.sh <class-dir>}"
fail=0

err() { echo "check: $*" >&2; fail=1; }

[ -f "$dir/Steps.class" ] || { err "$dir/Steps.class not found"; exit 1; }
v=$(javap -v -p -cp "$dir" Steps 2>&1) || { err "javap failed on Steps"; printf '%s\n' "$v" >&2; exit 1; }

# Exception table rows look like: "     8   106   225   Class java/lang/IllegalStateException" or "... any".
rows=$(printf '%s\n' "$v" | grep -E '^ +[0-9]+ +[0-9]+ +[0-9]+ +(any|Class [^ ]+)$')
total=$(printf '%s\n' "$rows" | grep -c . )
any=$(printf '%s\n' "$rows" | grep -cE ' any$')
[ "$total" -ge 4 ] || err "exception tables have $total entries, want at least 4"
[ "$any" -ge 2 ] || err "exception tables have $any entries with type any, want at least 2"
printf '%s\n' "$rows" | grep -qE ' Class java/lang/IllegalStateException$' || err "no exception table entry for java/lang/IllegalStateException"
printf '%s\n' "$rows" | grep -qE ' Class java/lang/RuntimeException$' || err "no exception table entry for java/lang/RuntimeException"

ins=$(printf '%s\n' "$v" | grep -E '^ +[0-9]+: [a-z_0-9]+')
printf '%s\n' "$ins" | grep -qE '^ +[0-9]+: athrow$' || err "no athrow instruction"
if printf '%s\n' "$ins" | grep -qE '^ +[0-9]+: (jsr|jsr_w|ret)( |$)'; then err "jsr/jsr_w/ret instruction present"; fi
if printf '%s\n' "$ins" | grep -E '^ +[0-9]+: new ' | grep -qE 'class java/lang/(NullPointerException|ArithmeticException)$'; then
  err "NullPointerException or ArithmeticException created with new; they must be thrown by the JVM"
fi

[ "$fail" -eq 0 ] && echo "check: ok ($total exception table entries, $any of type any)"
exit "$fail"
