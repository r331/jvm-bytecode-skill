#!/bin/bash
# Drift checks between the docs and the tested programs.
# 1. Every byte block (fenced code block that is pure hex once '#' comments are stripped)
#    under "Worked example N" in references/verification.md must appear contiguously
#    in the built class of the program that example documents.
# 2. Every relative markdown link in SKILL.md and references/*.md must point to an existing file.
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
doc="$root/references/verification.md"
fail=0
ok()  { echo "PASS docs: $1"; }
bad() { echo "FAIL docs: $1"; fail=1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# build_bytes <program-dir> <ClassName>: prints the class bytes as " ca fe ba be ... "
build_bytes() {
  local d="$work/$(basename "$1")"
  mkdir -p "$d" && cp "$1/$2.hex" "$d/" || return 1
  (cd "$d" && sh "$root/build.sh" "$2" >/dev/null) || return 1
  printf ' %s ' "$(xxd -p -c 1 "$d/$2.class" | tr '\n' ' ' | sed 's/ $//')"
}

# blocks <heading-text>: prints each hex byte block of that section on one line,
# lowercase, single-space separated. Non-hex blocks (pseudocode) are skipped.
blocks() {
  awk -v want="$1" '
    !infence && /^#+ / { insec = (index($0, want) > 0); next }
    !insec { next }
    /^```/ {
      if (infence) {
        b = buf; gsub(/[ \t\r\n]+/, " ", b); gsub(/^ | $/, "", b)
        if (b != "" && b ~ /^[0-9A-Fa-f ]+$/) print tolower(b)
        infence = 0; buf = ""
      } else infence = 1
      next
    }
    infence { l = $0; sub(/#.*/, "", l); buf = buf " " l }
  ' "$doc"
}

check_example() {  # <heading> <program-dir> <ClassName>
  local heading="$1" prog="$root/tests/programs/$2" cls="$3" class n=0 b
  if ! class=$(build_bytes "$prog" "$cls"); then bad "$heading: could not build $2/$cls.hex"; return; fi
  while IFS= read -r b; do
    n=$((n + 1))
    case "$class" in
      *" $b "*) ok "$heading: byte block $n ($(echo $b | wc -w | tr -d ' ') bytes) appears in $2/$cls.class" ;;
      *) bad "$heading: byte block $n not found contiguously in $2/$cls.class: $b" ;;
    esac
  done < <(blocks "$heading")
  [ "$n" -gt 0 ] || bad "$heading: no hex byte block found in verification.md"
}

check_example "Worked example 1" hypotenuse-v52 Hypotenuse
check_example "Worked example 2" factorial-v65 Factorial

# --- relative links -------------------------------------------------------------
nlinks=0 broken=""
for md in "$root/SKILL.md" "$root"/references/*.md; do
  dir=$(dirname "$md")
  while IFS= read -r target; do
    case "$target" in
      http://*|https://*|mailto:*|'#'*|'') continue ;;
    esac
    path="${target%%#*}"
    nlinks=$((nlinks + 1))
    [ -e "$dir/$path" ] || broken="$broken  ${md#$root/}: $target\n"
  done < <(grep -o '\]([^)]*)' "$md" | sed 's/^](//; s/)$//; s/ .*//')
done
if [ -z "$broken" ]; then
  ok "all $nlinks relative markdown links in SKILL.md and references/*.md resolve"
else
  bad "broken relative links:"; printf "$broken"
fi

exit $fail
