#!/bin/bash
# Tests for build.sh: rejection of malformed hex, comment stripping, exact output bytes, -d and multiple names.
# Each case writes a fixture into a fresh temp dir, runs build.sh there, and checks
# the exit code, the error message, and the produced bytes (via xxd).
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
build="$root/build.sh"
fail=0
ok()  { echo "PASS build: $1"; }
bad() { echo "FAIL build: $1"; fail=1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# run_build <case-name> <ClassName>: fixture is $work/<case>/<ClassName>.hex.
# Sets: rc, out (stdout), err (stderr).
run_build() {
  ( cd "$work/$1" && sh "$build" "$2" >"$work/$1.out" 2>"$work/$1.err" )
  rc=$?
  out=$(cat "$work/$1.out")
  err=$(cat "$work/$1.err")
}
fixture() { mkdir -p "$work/$1"; cat > "$work/$1/$2.hex"; }
bytes() { xxd -p "$1" | tr -d '\n'; }

# expect_reject <case> <ClassName> <stderr-substring> <description>
expect_reject() {
  run_build "$1" "$2"
  if [ "$rc" -ne 0 ] && [ ! -e "$work/$1/$2.class" ] && [ -z "${err##*"$3"*}" ]; then
    ok "$4 (exit $rc, no .class written)"
  else
    bad "$4: exit $rc, class exists: $([ -e "$work/$1/$2.class" ] && echo yes || echo no), stderr: $err"
  fi
}

# --- negative cases ---------------------------------------------------------
fixture nonhex Bad <<'EOF'
CA FE BA BE   # magic
00 00 00 G1   # 'G' is not a hex digit
EOF
expect_reject nonhex Bad 'non-hex characters outside comments in Bad.hex' "non-hex char outside comments is rejected"
[ -z "${err##*2:00 00 00 G1*}" ] && ok "non-hex error names the offending line number and content" || bad "non-hex error does not show '2:00 00 00 G1': $err"

fixture prefix Pfx <<'EOF'
0xCA 0xFE     # C-style 0x prefixes are not allowed
EOF
expect_reject prefix Pfx 'non-hex characters outside comments' "0x prefix outside comments is rejected"

fixture utf Utf <<'EOF'
CA FE é       # non-ASCII outside comments
EOF
expect_reject utf Utf 'non-hex characters outside comments' "non-ASCII char outside comments is rejected"

fixture odd Odd <<'EOF'
CA FE BA B    # 7 digits
EOF
expect_reject odd Odd 'odd number of hex digits (7) in Odd.hex' "odd digit count is rejected with the digit count"

fixture missing Present <<'EOF'
CA FE
EOF
expect_reject missing Absent 'Absent.hex' "missing hex file is an error"

mkdir -p "$work/noarg"
( cd "$work/noarg" && sh "$build" >/dev/null 2>"$work/noarg.err" ); rc=$?
[ "$rc" -ne 0 ] && grep -q usage "$work/noarg.err" && ok "no argument prints usage and fails" || bad "no argument: exit $rc, stderr $(cat "$work/noarg.err")"

fixture empty Empty <<'EOF'
# nothing but comments
#   CA FE BA BE (inside a comment, ignored)

   # indented comment
EOF
expect_reject empty Empty 'Empty.hex contains no bytes' "comment-only file is rejected"

fixture magic Magic <<'EOF'
CA FE BA BF 00 00 00 31   # wrong magic
EOF
expect_reject magic Magic 'does not start with CA FE BA BE (got CAFEBABF)' "wrong magic number is rejected"

# --- a failed rebuild removes the stale .class from an earlier good build ------
fixture stale Stale <<'EOF'
CA FE BA BE
EOF
run_build stale Stale
[ "$rc" -eq 0 ] && [ -f "$work/stale/Stale.class" ] || bad "stale: initial build failed: $err"
printf 'CA FE BA BE ZZ\n' > "$work/stale/Stale.hex"
expect_reject stale Stale 'non-hex characters' "failed rebuild removes the stale .class"

# --- -d <out-dir> and several classes in one call ----------------------------
fixture multi A <<'EOF'
CA FE BA BE 01
EOF
fixture multi B <<'EOF'
CA FE BA BE 02
EOF
( cd "$work/multi" && sh "$build" -d out A B.hex >"$work/multi.out" 2>"$work/multi.err" ); rc=$?
if [ "$rc" -eq 0 ] && [ "$(bytes "$work/multi/out/A.class")" = cafebabe01 ] && [ "$(bytes "$work/multi/out/B.class")" = cafebabe02 ] \
   && [ ! -e "$work/multi/A.class" ] && [ "$(cat "$work/multi.out")" = "$(printf 'out/A.class: 5 bytes\nout/B.class: 5 bytes')" ]; then
  ok "-d writes several classes (with or without .hex suffix) into the out dir only"
else
  bad "-d / multiple names: exit $rc, out [$(cat "$work/multi.out")], err [$(cat "$work/multi.err")]"
fi

mkdir -p "$work/pkg/com/ex"
printf 'CA FE BA BE 03\n' > "$work/pkg/com/ex/Foo.hex"
( cd "$work/pkg" && sh "$build" -d classes com/ex/Foo >/dev/null 2>"$work/pkg.err" ); rc=$?
[ "$rc" -eq 0 ] && [ "$(bytes "$work/pkg/classes/com/ex/Foo.class")" = cafebabe03 ] && ok "-d keeps the package path of the class" || bad "-d with package path: exit $rc, err [$(cat "$work/pkg.err")]"

fixture first One <<'EOF'
CA FE BA BE 01
EOF
( cd "$work/first" && sh "$build" One Missing >/dev/null 2>&1 ); rc=$?
[ "$rc" -ne 0 ] && [ -f "$work/first/One.class" ] && ok "with several names, earlier good classes are kept and the bad one fails the run" || bad "multi with a missing name: exit $rc"

# --- positive: comments with hex-looking text and odd characters are ignored --
fixture comments Cmt <<'EOF'
# Header comment: CA FE BA BE 00 11 22 zz !@$%^&*() "quotes" 'single' é ü 日本
CA FE BA BE              # magic   <- trailing comment with hex: DE AD BE EF and an odd digit: F
00 00 00 31              ## double hash, 0x31 = 49, G H I J
	01 02 03         # leading tab, odd chars: \ / | ; : ` ~ [ ] { }
04050607                 # digits run together
  0 8 0 9                # digits split by spaces still pair up in order
0a 0b 0c 0d              # lowercase hex
0E 0F #no space before comment#and another hash
#
FF
EOF
run_build comments Cmt
want="cafebabe00000031010203040506070809"
want="${want}0a0b0c0d0e0fff"
got=$( [ -f "$work/comments/Cmt.class" ] && bytes "$work/comments/Cmt.class")
if [ "$rc" -eq 0 ] && [ "$got" = "$want" ] && [ "$out" = "Cmt.class: 24 bytes" ]; then
  ok "comments (with hex-looking text and odd chars) are ignored; 24 bytes exactly as expected"
else
  bad "comment stripping: exit $rc, out [$out], err [$err]"
  echo "  want $want"
  echo "  got  $got"
fi

# --- positive: CRLF line endings are tolerated ----------------------------------
mkdir -p "$work/crlf"
printf 'CA FE\r\nBA BE\r\n' > "$work/crlf/Crlf.hex"
run_build crlf Crlf
[ "$rc" -eq 0 ] && [ "$(bytes "$work/crlf/Crlf.class")" = cafebabe ] && ok "CRLF line endings are treated as whitespace" || bad "CRLF: exit $rc, err [$err]"

exit $fail
