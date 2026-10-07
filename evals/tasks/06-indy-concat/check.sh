#!/bin/bash
# Usage: check.sh <class-dir>
# Structural checks via javap for the 06-indy-concat task:
# - Report is major version 65 and has a BootstrapMethods attribute
# - every bootstrap method is REF_invokeStatic
#   java/lang/invoke/StringConcatFactory.makeConcatWithConstants with a recipe
#   String argument containing at least one \u0001 placeholder
# - at least 2 invokedynamic call sites using at least 2 distinct recipes
# - every Methodref/InterfaceMethodref is on the allowlist below, so no
#   StringBuilder, StringBuffer, String.concat, String.format, valueOf,
#   toString, print(int), ... can be used to build or emit text
# - no Utf8 entry names a string-building class or method
# Exits non-zero (listing every failed check) otherwise.

set -u
dir="${1:?usage: check.sh <class-dir>}"
fail=0

err() { echo "check: $*" >&2; fail=1; }

[ -f "$dir/Report.class" ] || { err "$dir/Report.class not found"; exit 1; }
v=$(javap -v -p -c -cp "$dir" Report 2>&1) || { err "javap failed on Report"; printf '%s\n' "$v" >&2; exit 1; }

printf '%s\n' "$v" | grep -qF "major version: 65" || err "Report: not major version 65"

bsm_desc='java/lang/invoke/StringConcatFactory.makeConcatWithConstants:(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;Ljava/lang/String;[Ljava/lang/Object;)Ljava/lang/invoke/CallSite;'

# BootstrapMethods section: from its header to the end of the javap output.
bsms=$(printf '%s\n' "$v" | awk '/^BootstrapMethods:/{f=1; next} f{print}')
if ! printf '%s\n' "$v" | grep -q '^BootstrapMethods:'; then
  err "Report: no BootstrapMethods attribute"
else
  # Each bootstrap method line: "  N: #h REF_kind owner.name:desc"
  heads=$(printf '%s\n' "$bsms" | grep -E '^  [0-9]+: #[0-9]+ ')
  [ -n "$heads" ] || err "BootstrapMethods: no entries"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
      *" REF_invokeStatic $bsm_desc") ;;
      *) err "bootstrap method is not REF_invokeStatic StringConcatFactory.makeConcatWithConstants: $line" ;;
    esac
  done <<EOF
$heads
EOF
fi

# Recipe of each bootstrap method: first line after "Method arguments:".
recipes=$(printf '%s\n' "$bsms" | awk '
  /^  [0-9]+: #/ { idx = $1; sub(":", "", idx); want = 0; next }
  /^    Method arguments:/ { want = 1; next }
  want && /^      #[0-9]+ / { line = $0; sub(/^      #[0-9]+ /, "", line); print idx "\t" line; want = 0 }')

# invokedynamic call sites in the code: "N: invokedynamic #cp,  0  // InvokeDynamic #bsm:name:desc"
sites=$(printf '%s\n' "$v" | grep -E '^ +[0-9]+: invokedynamic ')
nsites=$(printf '%s\n' "$sites" | grep -c 'invokedynamic' || true)
[ "$nsites" -ge 2 ] || err "expected at least 2 invokedynamic call sites, found $nsites"

used=$(printf '%s\n' "$sites" | sed -n 's/.*InvokeDynamic #\([0-9][0-9]*\):.*/\1/p' | sort -u)
used_recipes=""
for i in $used; do
  r=$(printf '%s\n' "$recipes" | awk -F '\t' -v i="$i" '$1 == i { print $2; exit }')
  if [ -z "$r" ]; then
    err "bootstrap method $i has no recipe argument"
    continue
  fi
  case "$r" in
    *'\u0001'*) ;;
    *) err "recipe of bootstrap method $i has no \\u0001 placeholder: $r" ;;
  esac
  used_recipes="$used_recipes$r
"
done
ndistinct=$(printf '%s' "$used_recipes" | grep -v '^$' | sort -u | wc -l | tr -d ' ')
[ "$ndistinct" -ge 2 ] || err "expected at least 2 distinct recipes used by invokedynamic, found $ndistinct"

# Method references allowlist (constant pool comments: "// owner.name:desc").
allowed='java/lang/Integer.parseInt:(Ljava/lang/String;)I
java/io/PrintStream.println:(Ljava/lang/String;)V
java/lang/System.exit:(I)V
java/lang/Object."<init>":()V
java/lang/String.length:()I
java/lang/String.charAt:(I)C
java/lang/Math.min:(II)I
java/lang/Math.max:(II)I
'"$bsm_desc"
refs=$(printf '%s\n' "$v" | grep -E '^ +#[0-9]+ = (Methodref|InterfaceMethodref) ' | sed 's/.*\/\/ //')
while IFS= read -r r; do
  [ -z "$r" ] && continue
  printf '%s\n' "$allowed" | grep -qxF -- "$r" || err "method reference not allowed: $r"
done <<EOF
$refs
EOF

# No Utf8 entry may name a string-building class or method.
utf8=$(printf '%s\n' "$v" | grep -E '^ +#[0-9]+ = Utf8 ' | sed -E 's/^ +#[0-9]+ = Utf8 +//')
bad=$(printf '%s\n' "$utf8" | grep -E 'StringBuilder|StringBuffer|StringJoiner|java/util/Formatter|MessageFormat|^(concat|format|formatted|join|valueOf|toString|append|print|printf|repeat)$' || true)
[ -z "$bad" ] || err "constant pool names forbidden string building: $(printf '%s' "$bad" | tr '\n' ' ')"

[ "$fail" -eq 0 ] && echo "check: ok"
exit "$fail"
