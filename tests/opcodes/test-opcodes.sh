#!/bin/bash
# Mechanical spot checks of references/instructions.md against the JDK's javap.
#
# 1. Parses every opcode row of references/instructions.md into a hex -> mnemonic map
#    and checks the table is complete (00-C9, CA, FE, FF each exactly once, nothing else).
# 2. Builds Opcodes.hex (one instruction per line between BEGIN CODE and END CODE,
#    comment "<offset> <mnemonic> [note]"), checks the comment offsets add up,
#    and checks each opcode byte maps to the commented mnemonic in the doc.
# 3. Runs javap -c and checks it decodes the same mnemonic at the same offset
#    (wide <op> is printed by javap as <op>_w), so operand lengths, switch padding,
#    and the wide formats are all exercised.
# 4. Checks branch/switch targets are relative to the opcode address, and the
#    newarray atype table.
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
doc="$root/references/instructions.md"
hexfile="$here/Opcodes.hex"
fail=0
ok()  { echo "PASS opcodes: $1"; }
bad() { echo "FAIL opcodes: $1"; fail=1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# --- 1. doc table -> map ---------------------------------------------------
awk -F'|' '
function trim(s) { gsub(/^[ \t`]+|[ \t`]+$/, "", s); return s }
function hexv(h) { return index("0123456789ABCDEF", substr(h,1,1)) * 16 - 16 + index("0123456789ABCDEF", substr(h,2,1)) - 1 }
function emit(v, m) { printf "%02X %s\n", v, m }
function pair(h, m,    a, b, n, i, lo, hi, left, right, pre, st, en) {
  h = trim(h); m = trim(m)
  if (h !~ /^[0-9A-F][0-9A-F]/) return
  if (index(h, "/")) {
    n = split(h, a, / \/ /); split(m, b, / \/ /)
    for (i = 1; i <= n; i++) emit(hexv(a[i]), b[i])
  } else if (h ~ /^[0-9A-F][0-9A-F]-[0-9A-F][0-9A-F]$/) {
    lo = hexv(substr(h, 1, 2)); hi = hexv(substr(h, 4, 2))
    if (index(m, ",")) {
      n = split(m, b, /, */)
      for (i = 1; i <= n; i++) emit(lo + i - 1, b[i])
    } else {
      left = substr(m, 1, index(m, "..") - 1); right = substr(m, index(m, "..") + 2)
      pre = left; sub(/[0-9]+$/, "", pre); st = substr(left, length(pre) + 1)
      en = right; sub(/^[^0-9]*/, "", en)
      for (i = st; i <= en; i++) emit(lo + i - st, pre i)
    }
  } else emit(hexv(h), m)
}
/^\| *Op *\| *i *\| *l *\| *f *\| *d *\|/ { matrix = 1; next }
matrix && /^\|/ {
  op = trim($2); sub(/ .*/, "", op)
  if (op ~ /^-+$/) next
  emit(hexv(trim($3)), "i" op); emit(hexv(trim($4)), "l" op)
  emit(hexv(trim($5)), "f" op); emit(hexv(trim($6)), "d" op)
  next
}
matrix && !/^\|/ { matrix = 0 }
/^\| *[0-9A-F][0-9A-F]/ {
  pair($2, $3)
  if (NF >= 6 && trim($5) ~ /^[0-9A-F][0-9A-F]$/) pair($5, $6)
}
' "$doc" | sort > "$work/map.txt"

dups=$(cut -d' ' -f1 "$work/map.txt" | uniq -d | tr '\n' ' ')
[ -z "$dups" ] && ok "instructions.md lists each opcode once" || bad "instructions.md lists opcodes more than once: $dups"

want=$( { i=0; while [ $i -le 202 ]; do printf '%02X\n' $i; i=$((i + 1)); done; echo FE; echo FF; } )
got=$(cut -d' ' -f1 "$work/map.txt" | uniq)
if [ "$want" = "$got" ]; then
  ok "instructions.md covers 00-CA, FE, FF ($(printf '%s\n' "$got" | wc -l | tr -d ' ') opcodes)"
else
  bad "instructions.md opcode coverage differs from 00-CA, FE, FF:"
  diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") | sed 's/^/  /'
fi
mn() { awk -v h="$1" '$1 == h { print $2; exit }' "$work/map.txt"; }

# --- 2. hex file self-consistency and doc agreement -------------------------
sed -n '/^# BEGIN CODE/,/^# END CODE/p' "$hexfile" | awk '
BEGIN { off = 0 }
/^# (BEGIN|END) CODE/ { next }
{
  line = $0; c = ""
  if (index(line, "#")) { c = substr(line, index(line, "#") + 1); line = substr(line, 1, index(line, "#") - 1) }
  n = split(line, b, /[ \t]+/); k = 0
  for (i = 1; i <= n; i++) if (b[i] != "") { if (b[i] !~ /^[0-9A-Fa-f][0-9A-Fa-f]$/) { print "BADTOKEN", NR, b[i]; next } t[++k] = toupper(b[i]) }
  if (match(c, /^ *[0-9]+ [a-z]/)) {
    split(c, w, " ")
    print "INS", w[1], off, w[2], t[1], (k > 1 ? t[2] : "-"), (k > 1 ? t[k] : "-")
  }
  off += k
}
END { print "LEN", off }' > "$work/ins.txt"

if grep -q '^BADTOKEN' "$work/ins.txt"; then bad "Opcodes.hex has malformed byte tokens: $(grep '^BADTOKEN' "$work/ins.txt" | head -3 | tr '\n' ' ')"; fi
n_ins=$(grep -c '^INS' "$work/ins.txt")
miscount=$(awk '$1 == "INS" && $2 != $3 { print "  comment says " $2 ", actual offset " $3 " (" $4 ")" }' "$work/ins.txt")
[ -z "$miscount" ] && ok "Opcodes.hex: $n_ins instruction offsets in comments match byte counts" || { bad "Opcodes.hex comment offsets wrong:"; echo "$miscount" | head -5; }

docbad=""
while read -r _ _ o m op b2 _; do
  d=$(mn "$op")
  [ "$d" = "$m" ] || docbad="$docbad  @$o byte $op: hex comment says $m, instructions.md says ${d:-nothing}\n"
done < <(grep '^INS' "$work/ins.txt")
[ -z "$docbad" ] && ok "every opcode byte in Opcodes.hex has the commented mnemonic in instructions.md" || { bad "opcode bytes disagree with instructions.md:"; printf "$docbad" | head -10; }
distinct=$(grep '^INS' "$work/ins.txt" | awk '{print $5}' | sort -u | wc -l | tr -d ' ')

# --- 3. javap decoding --------------------------------------------------------
cp "$hexfile" "$work/"
if ! (cd "$work" && sh "$root/build.sh" Opcodes >/dev/null); then bad "build.sh failed on Opcodes.hex"; exit 1; fi
if ! javap -c -p "$work/Opcodes.class" > "$work/javap.txt" 2>&1; then bad "javap -c failed"; sed 's/^/  /' "$work/javap.txt" | head; exit 1; fi
awk '/^ +[0-9]+: [a-z]/ { o = $1; sub(/:/, "", o); print o, $2, $3, $4 }' "$work/javap.txt" > "$work/jv.txt"

n_jv=$(wc -l < "$work/jv.txt" | tr -d ' ')
[ "$n_jv" = "$n_ins" ] && ok "javap decodes $n_jv instructions, same as Opcodes.hex" || bad "javap decodes $n_jv instructions, Opcodes.hex has $n_ins"

jvbad=""
while read -r _ _ o m op b2 last; do
  exp="$m"
  if [ "$op" = C4 ]; then exp="$(mn "$b2")_w"; fi
  got=$(awk -v o="$o" '$1 == o { print $2; exit }' "$work/jv.txt")
  [ "$got" = "$exp" ] || jvbad="$jvbad  @$o byte $op: expected $exp, javap printed ${got:-nothing}\n"
done < <(grep '^INS' "$work/ins.txt")
[ -z "$jvbad" ] && ok "javap prints the instructions.md mnemonic at every offset ($distinct distinct opcodes, wide forms as <op>_w)" || { bad "javap disagrees:"; printf "$jvbad" | head -10; }

# --- 4. targets relative to opcode, switch padding, newarray atypes ------------
relbad=""
while read -r _ _ o m op _ _; do
  case "$m" in
    if*|goto|jsr) want=$((o + 3)) ;;
    goto_w|jsr_w) want=$((o + 5)) ;;
    *) continue ;;
  esac
  got=$(awk -v o="$o" '$1 == o { print $3; exit }' "$work/jv.txt")
  [ "$got" = "$want" ] || relbad="$relbad  @$o $m: target $got, want $want\n"
done < <(grep '^INS' "$work/ins.txt")
[ -z "$relbad" ] && ok "branch targets are relative to the branch opcode address" || { bad "branch targets:"; printf "$relbad"; }

# Switch defaults in Opcodes.hex are +28 (tableswitch) and +40 (lookupswitch).
swbad="" pads=""
while read -r _ _ o m _ _ _; do
  case "$m" in tableswitch) d=28 ;; lookupswitch) d=40 ;; *) continue ;; esac
  pads="$pads $(( (4 - ((o + 1) % 4)) % 4 ))"
  got=$(awk -v o="$o" '
    $1 == o":" { on = 1; next }
    on && $1 == "default:" { print $2; exit }' "$work/javap.txt")
  [ "$got" = "$((o + d))" ] || swbad="$swbad  @$o $m: default $got, want $((o + d))\n"
done < <(grep '^INS' "$work/ins.txt")
padset=$(echo $pads | tr ' ' '\n' | sort -u | tr '\n' ' ')
if [ -z "$swbad" ] && [ "$padset" = "0 1 2 3 " ]; then
  ok "tableswitch/lookupswitch padding formula and relative offsets (paddings used: $padset)"
else
  bad "switch padding/offsets (paddings used: $padset)"; printf "$swbad"
fi

atline=$(grep -i 'newarray.*atype:' "$doc" | head -1)
atbad="" atn=0
while read -r o _ word _; do
  [ "$word" = "" ] && continue
  b=$(awk -v o="$o" '$1 == "INS" && $3 == o { print $6; exit }' "$work/ins.txt")
  v=$((16#$b))
  docw=$(printf '%s\n' "$atline" | tr ',:' '\n\n' | awk -v v="$v" '$1 == v { print $2; exit }' | tr -d '.')
  atn=$((atn + 1))
  [ "$docw" = "$word" ] || atbad="$atbad  atype $v: instructions.md says ${docw:-nothing}, javap says $word\n"
done < <(awk '$2 == "newarray"' "$work/jv.txt")
[ -z "$atbad" ] && [ "$atn" -eq 8 ] && ok "newarray atype table (8 types)" || { bad "newarray atypes ($atn checked):"; printf "$atbad"; }

exit $fail
