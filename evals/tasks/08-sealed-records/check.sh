#!/bin/bash
# Usage: check.sh <class-dir>
# Structural checks via javap for the 08-sealed-records task:
# - all five classes are major version 61
# - Expr is a public interface with a PermittedSubclasses attribute listing exactly Num, Add, Mul in that order
# - Num, Add, Mul are real records: public final, super java/lang/Record, implement Expr,
#   private final component fields, canonical constructor, accessors, a Record attribute with the
#   right components, and public final toString/hashCode/equals that each use invokedynamic,
#   with every bootstrap method being ObjectMethods.bootstrap with (record class, names, getters)
# - Calc8 has main and static long eval(Expr) that uses instanceof + checkcast,
#   calls the reflection methods for --introspect, and does not hardcode record toString text
# Exits non-zero (listing every failed check) otherwise.

set -u
dir="${1:?usage: check.sh <class-dir>}"
fail=0

err() { echo "check: $*" >&2; fail=1; }

# has <text> <description> <fixed-string>: assert text contains the string
has() {
  if ! printf '%s\n' "$1" | grep -qF -- "$3"; then err "$2: missing '$3'"; fi
}
# has_re <text> <description> <extended-regex>
has_re() {
  if ! printf '%s\n' "$1" | grep -qE -- "$3"; then err "$2: no line matching /$3/"; fi
}
# section <javap -v text> <header>: print the lines of a top-level attribute section
# (from the line equal to <header> up to the next line that does not start with a space)
section() {
  printf '%s\n' "$1" | awk -v h="$2" '$0==h{f=1; next} f&&/^[^ ]/{exit} f{print}'
}
# method_code <javap -c -p text> <declaration>: the disassembly of one method (fixed-string match)
method_code() {
  printf '%s\n' "$1" | awk -v d="$2" 'index($0, d){f=1} f{print} f&&/^$/{exit}'
}

all="Expr Num Add Mul Calc8"
for c in $all; do
  if [ ! -f "$dir/$c.class" ]; then err "$dir/$c.class not found"; fi
done
[ "$fail" -eq 0 ] || exit 1

for c in $all; do
  v=$(javap -v -p -cp "$dir" "$c" 2>&1) || { err "javap failed on $c"; continue; }
  has "$v" "$c" "major version: 61"
done

# ---- Expr ----
expr=$(javap -v -p -cp "$dir" Expr 2>&1)
has_re "$expr" "Expr" "^public interface Expr\$"
has_re "$expr" "Expr" "flags: \(0x0601\) ACC_PUBLIC, ACC_INTERFACE, ACC_ABSTRACT\$"
permitted=$(section "$expr" "PermittedSubclasses:" | sed 's/^ *//' | tr '\n' ' ')
[ "$permitted" = "Num Add Mul " ] || err "Expr: PermittedSubclasses must be exactly [Num Add Mul], got [${permitted% }]"

# ---- records ----
# check_record <Name> <fields...> where each field is name:javap-type:descriptor
check_record() {
  local r=$1; shift
  local v p c f name jtype desc ctor_types="" ctor_desc="" names="" getters=""
  v=$(javap -v -p -cp "$dir" "$r" 2>&1)
  p=$(javap -p -cp "$dir" "$r" 2>&1)
  c=$(javap -c -p -cp "$dir" "$r" 2>&1)

  has_re "$v" "$r" "^public final class $r extends java\.lang\.Record implements Expr\$"
  has_re "$v" "$r" "flags: \(0x0031\) ACC_PUBLIC, ACC_FINAL, ACC_SUPER\$"
  has_re "$v" "$r" "super_class: #[0-9]+ +// java/lang/Record\$"

  local rec expect_rec=""
  rec=$(section "$v" "Record:" | sed '/^ *$/d; s/^ *//' | tr '\n' '|')
  for f in "$@"; do
    name=${f%%:*}; jtype=${f#*:}; jtype=${jtype%%:*}; desc=${f##*:}
    has "$p" "$r" "private final $jtype $name;"
    has "$p" "$r" "public $jtype $name();"
    expect_rec="$expect_rec$jtype $name;|descriptor: $desc|"
    ctor_types="$ctor_types${ctor_types:+, }$jtype"
    ctor_desc="$ctor_desc$desc"
    names="$names${names:+;}$name"
    getters="$getters|REF_getField $r.$name:$desc"
  done
  [ "$rec" = "$expect_rec" ] || err "$r: Record attribute must be [$expect_rec], got [$rec]"
  has "$p" "$r" "public $r($ctor_types);"
  has "$v" "$r" "descriptor: ($ctor_desc)V"

  local m
  m=$(method_code "$c" "public final java.lang.String toString();")
  has_re "$m" "$r.toString" "invokedynamic .*InvokeDynamic #[0-9]+:toString:\\(L$r;\\)Ljava/lang/String;"
  m=$(method_code "$c" "public final int hashCode();")
  has_re "$m" "$r.hashCode" "invokedynamic .*InvokeDynamic #[0-9]+:hashCode:\\(L$r;\\)I"
  m=$(method_code "$c" "public final boolean equals(java.lang.Object);")
  has_re "$m" "$r.equals" "invokedynamic .*InvokeDynamic #[0-9]+:equals:\\(L$r;Ljava/lang/Object;\\)Z"

  # Every bootstrap method: ObjectMethods.bootstrap with args (Class r, "names", getters...)
  local bsm want got
  bsm=$(section "$v" "BootstrapMethods:")
  want="REF_invokeStatic java/lang/runtime/ObjectMethods.bootstrap:(Ljava/lang/invoke/MethodHandles\$Lookup;Ljava/lang/String;Ljava/lang/invoke/TypeDescriptor;Ljava/lang/Class;Ljava/lang/String;[Ljava/lang/invoke/MethodHandle;)Ljava/lang/Object;|$r|$names$getters"
  got=$(printf '%s\n' "$bsm" | awk '
    /^  [0-9]+: / { if (s != "") print s; sub(/^  [0-9]+: #[0-9]+ /, ""); s = $0; next }
    /^ *Method arguments:/ { next }
    /^      #[0-9]+ / { sub(/^      #[0-9]+ /, ""); s = s "|" $0 }
    END { if (s != "") print s }')
  if [ -z "$got" ]; then
    err "$r: no BootstrapMethods attribute"
  else
    while IFS= read -r line; do
      [ "$line" = "$want" ] || err "$r: bootstrap method must be [$want], got [$line]"
    done <<EOF
$got
EOF
  fi
}

check_record Num "value:long:J"
check_record Add "left:Expr:LExpr;" "right:Expr:LExpr;"
check_record Mul "left:Expr:LExpr;" "right:Expr:LExpr;"

# ---- Calc8 ----
calc_p=$(javap -p -cp "$dir" Calc8 2>&1)
calc_c=$(javap -c -p -cp "$dir" Calc8 2>&1)
calc_v=$(javap -v -p -cp "$dir" Calc8 2>&1)
has "$calc_p" "Calc8" "public static void main(java.lang.String[]);"
has_re "$calc_p" "Calc8" "^  (public |private |protected )?static long eval\\(Expr\\);\$"

ev=$(method_code "$calc_c" "static long eval(Expr);")
has_re "$ev" "Calc8.eval" "instanceof .*// class Num\$"
has_re "$ev" "Calc8.eval" "instanceof .*// class Add\$"
has_re "$ev" "Calc8.eval" "checkcast .*// class Num\$"
has_re "$ev" "Calc8.eval" "checkcast .*// class Add\$"
has_re "$ev" "Calc8.eval" "checkcast .*// class Mul\$"

for m in "java/lang/Class.isRecord:()Z" "java/lang/Class.isSealed:()Z" \
         "java/lang/Class.getPermittedSubclasses:()[Ljava/lang/Class;" \
         "java/lang/Class.getRecordComponents:()[Ljava/lang/reflect/RecordComponent;" \
         "java/lang/reflect/RecordComponent.getName:()Ljava/lang/String;" \
         "java/lang/reflect/RecordComponent.getType:()Ljava/lang/Class;"; do
  has "$calc_c" "Calc8" "// Method $m"
done

# The record text must come from the records' own toString, not from Calc8's constants.
if printf '%s\n' "$calc_v" | sed -n 's/^ *#[0-9]* = Utf8 *//p' | grep -vE '^[[(]' | grep -qE '\[|value=|left=|right=|=true|components=value'; then
  err "Calc8: constant pool contains record toString or introspection text; it must be computed"
fi

[ "$fail" -eq 0 ] && echo "check: ok"
exit "$fail"
