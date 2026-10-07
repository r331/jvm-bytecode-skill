#!/bin/bash
# Deterministic test suite for the jvm-bytecode skill. No AI model involved.
#
# Usage: tests/run.sh            (from any directory)
# Env:   TEST_TIMEOUT=<seconds>  per java invocation (default 20)
#
# 1. Programs: every tests/programs/*/ and every evals/tasks/*/solution/ directory.
#    All *.hex files of a program are built with build.sh into one temp dir, then:
#    - javap -v must parse every built class;
#    - if an `expect` file exists: `major: N` is asserted on every class listed in
#      `files: A B C` (or on every built class when `files:` is absent), and
#      `class: <Name>` names the main class (default: the only .hex file);
#    - cases.txt is run with tests/lib/run-cases.sh (stdin files from a `stdin/` dir, if any);
#    - an executable check.sh is run as `check.sh <class-dir>` (evals tasks).
#    For tests/programs/<p>/ the expect, cases.txt, stdin/ and check.sh live next to the hex;
#    for evals/tasks/<t>/solution/ they live in evals/tasks/<t>/.
# 2. tests/build/test-build.sh, tests/docs/test-docs.sh, tests/opcodes/test-opcodes.sh.
#
# Prints PASS/FAIL per item and a summary; exits non-zero if anything failed.
# Never writes .class files into the repository (everything is built in mktemp dirs).
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
build="$root/build.sh"

npass=0 nfail=0 failed=""
pass() { echo "PASS $1"; npass=$((npass + 1)); }
fail() { echo "FAIL $1"; nfail=$((nfail + 1)); failed="$failed  $1\n"; }
indent() { sed 's/^/    /'; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
touch "$work/start-marker"

# java shim enforcing a per-invocation timeout (macOS has no `timeout`), put first on PATH
# so tests/lib/run-cases.sh and check.sh scripts pick it up.
real_java=$(command -v java) || { echo "FAIL java not found on PATH"; exit 1; }
mkdir -p "$work/bin"
cat > "$work/bin/java" <<EOF
#!/bin/bash
"$real_java" "\$@" <&0 &
pid=\$!
( i=0
  while [ \$i -lt ${TEST_TIMEOUT:-20} ]; do sleep 1; kill -0 \$pid 2>/dev/null || exit 0; i=\$((i + 1)); done
  echo "TIMEOUT: java killed after ${TEST_TIMEOUT:-20}s" >&2; kill -9 \$pid 2>/dev/null ) >/dev/null &
wait \$pid
EOF
chmod +x "$work/bin/java"
PATH="$work/bin:$PATH"
export PATH

# expect_get <expect-file> <key>: value of "key: value" (empty if absent)
expect_get() {
  [ -f "$1" ] || return 0
  sed -n "s/^[[:space:]]*$2:[[:space:]]*//p" "$1" | head -1 | sed 's/[[:space:]]*$//'
}

# test_program <label> <hex-dir> <meta-dir>
test_program() {
  local label="$1" hexdir="$2" meta="$3" out="$work/p$npass-$nfail-$RANDOM"
  local classes="$out/classes" expect="$3/expect" hexes="" n=0 h name broken=""
  mkdir -p "$classes"

  for h in "$hexdir"/*.hex; do
    [ -f "$h" ] || continue
    name=$(basename "$h" .hex)
    hexes="$hexes $name"; n=$((n + 1))
    cp "$h" "$classes/"
  done
  if [ "$n" -eq 0 ]; then fail "$label: no .hex file in ${hexdir#$root/}"; return; fi

  # build every class
  for name in $hexes; do
    if ! (cd "$classes" && sh "$build" "$name") >"$out.build" 2>&1; then
      broken="$broken $name"; fail "$label: build $name.hex"; indent < "$out.build"
    fi
  done
  [ -n "$broken" ] && return
  rm -f "$classes"/*.hex
  pass "$label: build ($n class$([ "$n" -gt 1 ] && echo es):$hexes)"

  # javap -v parses every class
  broken=""
  for name in $hexes; do
    if ! javap -v -p -c "$classes/$name.class" >"$out.javap.$name" 2>&1 || grep -q '^Error:' "$out.javap.$name"; then
      broken="$broken $name"
    fi
  done
  if [ -z "$broken" ]; then pass "$label: javap -v parses"; else
    fail "$label: javap -v fails on:$broken"
    for name in $broken; do indent < "$out.javap.$name" | head -10; done
    return
  fi

  # major version
  local major files got bad=""
  major=$(expect_get "$expect" major)
  if [ -n "$major" ]; then
    files=$(expect_get "$expect" files)
    [ -n "$files" ] || files="$hexes"
    for name in $files; do
      name="${name%.class}"; name="${name%.hex}"
      if [ ! -f "$out.javap.$name" ]; then bad="$bad $name(not built)"; continue; fi
      got=$(sed -n 's/^ *major version: *//p' "$out.javap.$name")
      [ "$got" = "$major" ] || bad="$bad $name(major $got)"
    done
    if [ -z "$bad" ]; then pass "$label: major version $major"; else fail "$label: major version $major expected, got:$bad"; fi
  fi

  # main class
  local cls
  cls=$(expect_get "$expect" class)
  if [ -z "$cls" ]; then
    if [ "$n" -eq 1 ]; then cls="${hexes# }"; else fail "$label: $n hex files but no 'class: <Name>' in expect"; return; fi
  fi

  local ran=0
  if [ -f "$meta/cases.txt" ]; then
    ran=1
    local stdin_dir=""
    [ -d "$meta/stdin" ] && stdin_dir="$meta/stdin"
    if STDIN_DIR="$stdin_dir" bash "$root/tests/lib/run-cases.sh" "$classes" "$cls" "$meta/cases.txt" >"$out.cases" 2>&1; then
      pass "$label: cases ($(tail -1 "$out.cases"))"
    else
      fail "$label: cases ($(tail -1 "$out.cases"))"
      sed '$d' "$out.cases" | indent | head -40
      [ "$(sed '$d' "$out.cases" | wc -l)" -le 40 ] || echo "    ... (truncated; rerun tests/lib/run-cases.sh for full output)"
    fi
  fi
  if [ -f "$meta/check.sh" ]; then
    ran=1
    local runner=""
    [ -x "$meta/check.sh" ] || runner=bash
    if (cd "$meta" && $runner "$meta/check.sh" "$classes") >"$out.check" 2>&1; then
      pass "$label: check.sh"
    else
      fail "$label: check.sh (exit $?)"; indent < "$out.check" | tail -20
    fi
  fi
  [ "$ran" -eq 1 ] || fail "$label: neither cases.txt nor check.sh in ${meta#$root/}"
}

echo "== programs"
for d in "$root"/tests/programs/*/; do
  [ -d "$d" ] || continue
  d="${d%/}"
  test_program "${d#$root/}" "$d" "$d"
done
for d in "$root"/evals/tasks/*/solution/; do
  [ -d "$d" ] || continue
  d="${d%/}"; task="${d%/solution}"
  test_program "${task#$root/}" "$d" "$task"
done

# run_suite <script>: forwards its PASS/FAIL lines into the totals
run_suite() {
  local log="$work/suite.log" line rc
  bash "$1" >"$log" 2>&1; rc=$?
  while IFS= read -r line; do
    case "$line" in
      PASS\ *) pass "${line#PASS }" ;;
      FAIL\ *) fail "${line#FAIL }" ;;
      *) echo "$line" ;;
    esac
  done <"$log"
  if [ "$rc" -ne 0 ] && ! grep -q '^FAIL ' "$log"; then fail "${1#$root/} exited $rc"; fi
}

for s in build docs opcodes; do
  echo "== $s"
  run_suite "$root/tests/$s/test-$s.sh"
done

echo "== task inputs"
# Every committed input .class must be exactly what its maintainer hex in original/ builds to,
# and every input .class must have such a source.
for cf in "$root"/evals/tasks/*/inputs/*/*.class "$root"/evals/tasks/*/inputs/*.class; do
  [ -f "$cf" ] || continue
  task=${cf%%/inputs/*}; name=$(basename "$cf" .class); rel=${cf#$root/}
  src="$task/original/$name.hex"
  if [ ! -f "$src" ]; then fail "$rel has no maintainer source ${src#$root/}"; continue; fi
  tdir=$(mktemp -d "$work/input.XXXX")
  cp "$src" "$tdir/" && (cd "$tdir" && sh "$build" "$name" >/dev/null 2>&1)
  if cmp -s "$tdir/$name.class" "$cf"; then pass "$rel is byte-identical to a build of ${src#$root/}"; else fail "$rel differs from a build of ${src#$root/}"; fi
done

echo "== repository hygiene"
stray=$(find "$root" -name '*.class' -newer "$work/start-marker" -not -path '*/.git/*' 2>/dev/null)
if [ -z "$stray" ]; then pass "no .class files written into the repository"; else fail "stray .class files written: $stray"; fi

echo
echo "== summary: $npass passed, $nfail failed"
if [ "$nfail" -ne 0 ]; then
  printf "failed:\n$failed"
  exit 1
fi
