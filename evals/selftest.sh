#!/bin/bash
# Usage: selftest.sh
# Self-test of the eval harness that needs no AI model. Runs run-evals.sh with
# fake agents and asserts the grading outcome of every trial:
#   - the oracle (reference solution) passes every task in evals/tasks and a
#     throwaway task built from tests/programs/factorial-v65, in both modes
#   - cheaters, a no-op agent, and broken solutions fail with the right reason
# Exits non-zero if any assertion fails.

set -u
EVALS_DIR=$(cd "$(dirname "$0")" && pwd -P)
REPO_DIR=$(cd "$EVALS_DIR/.." && pwd -P)
FAKE="$EVALS_DIR/fake-agents"
RUN="$EVALS_DIR/run-evals.sh"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/jvm-selftest.XXXXXX")
tmp=$(cd "$tmp" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
failures=0

# ---- throwaway task: Factorial (main) + Helper (second required class) ----
TASKS="$tmp/tasks"
T="$TASKS/90-selftest-factorial"
mkdir -p "$T/solution"
cp "$REPO_DIR/tests/programs/factorial-v65/Factorial.hex" "$T/solution/"
cp "$REPO_DIR/tests/programs/factorial-v65/cases.txt" "$T/cases.txt"
cat >"$T/solution/Helper.hex" <<'EOF'
# Helper.class - empty public final class, major 65
CA FE BA BE        # magic
00 00 00 41        # minor 0, major 65
00 05              # constant_pool_count 5
01 00 06 48 65 6C 70 65 72                                  # 1 Utf8 "Helper"
07 00 01                                                    # 2 Class Helper
01 00 10 6A 61 76 61 2F 6C 61 6E 67 2F 4F 62 6A 65 63 74    # 3 Utf8 "java/lang/Object"
07 00 03                                                    # 4 Class java/lang/Object
00 31              # access_flags ACC_PUBLIC | ACC_FINAL | ACC_SUPER
00 02              # this_class
00 04              # super_class
00 00 00 00 00 00 00 00   # interfaces, fields, methods, attributes: none
EOF
printf 'class: Factorial\nmajor: 65\nfiles: Factorial Helper\n' >"$T/expect"
cat >"$T/prompt.md" <<'EOF'
Write class `Factorial` (major version 65) whose `main` prints n! for one integer argument 0..20.
Also write an empty `public final class Helper` (major version 65).
EOF
cat >"$T/check.sh" <<'EOF'
#!/bin/bash
# Asserts Helper is public final and Factorial multiplies longs.
d="$1"
javap -p -cp "$d" Helper | grep -q 'public final class Helper' || { echo "Helper is not public final"; exit 1; }
javap -c -p -cp "$d" Factorial | grep -q 'lmul' || { echo "Factorial does not use lmul"; exit 1; }
EOF
chmod +x "$T/check.sh"
SOL="$T/solution"

# expect_results <label> <results.jsonl> <want-pass> <reason-prefix>
expect_results() {
  local label=$1 f=$2 want=$3 prefix=$4 n=0 bad=0 line pass reason
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    n=$((n + 1))
    pass=$(printf '%s' "$line" | sed -n 's/.*"pass":\([a-z]*\).*/\1/p')
    reason=$(printf '%s' "$line" | sed -n 's/.*"reason":"\(.*\)","cases_passed".*/\1/p')
    case "$reason" in "$prefix"*) ok=1 ;; *) ok=0 ;; esac
    if [ "$pass" != "$want" ] || [ "$ok" != 1 ]; then
      bad=$((bad + 1))
      echo "    unexpected: $line"
    fi
  done <"$f"
  if [ "$n" -eq 0 ]; then bad=1; echo "    no results in $f"; fi
  if [ "$bad" -eq 0 ]; then
    echo "PASS  $label ($n trials: pass=$want, reason '$prefix')"
  else
    echo "FAIL  $label"
    failures=$((failures + 1))
  fi
}

# scenario <label> <want-pass> <reason-prefix> <run-evals args...>
scenario() {
  local label=$1 want=$2 prefix=$3 o
  shift 3
  o="$tmp/out-$(printf '%s' "$label" | tr -c 'A-Za-z0-9' '_')"
  if ! bash "$RUN" --trials 1 --out "$o" "$@" >"$o.log" 2>&1; then
    echo "FAIL  $label (harness exited non-zero, see below)"; sed 's/^/    /' "$o.log"
    failures=$((failures + 1)); return
  fi
  expect_results "$label" "$o/results.jsonl" "$want" "$prefix"
}

copy_sol='cp "'"$SOL"'"/*.hex .'

echo "== oracle =="
scenario "oracle, throwaway task, both modes" true ok \
  --tasks-dir "$TASKS" --mode both --oracle --agent-cmd "$FAKE/oracle.sh"
real=""
for d in "$EVALS_DIR"/tasks/*/; do
  [ -f "$d/prompt.md" ] && [ -f "$d/expect" ] && [ -d "$d/solution" ] && real="$real $(basename "$d")"
done
if [ -n "$real" ]; then
  scenario "oracle, evals/tasks ($(echo $real | wc -w | tr -d ' ') tasks), both modes" true ok \
    --mode both --oracle --agent-cmd "$FAKE/oracle.sh"
  tail -n +1 "$tmp"/out-oracle__evals_tasks*/summary.md 2>/dev/null | sed 's/^/    /'
else
  echo "SKIP  oracle on evals/tasks (no tasks with a solution yet)"
fi

echo "== cheaters and failures (throwaway task) =="
common="--tasks-dir $TASKS --mode skill"
scenario "cheater-javac" false "shim violation: javac" $common --agent-cmd "$FAKE/cheater-javac.sh"
scenario "cheater-source" false "forbidden source file: Foo.java" $common --agent-cmd "$FAKE/cheater-source.sh"
scenario "noop" false "missing hex" $common --agent-cmd "$FAKE/noop.sh"
scenario "java source launcher" false "shim violation: java" $common \
  --agent-cmd 'echo "class A{}" > /tmp/jvm-selftest-A.java; java /tmp/jvm-selftest-A.java; rm -f /tmp/jvm-selftest-A.java'
scenario "class without hex" false "class without hex: Foo.class" $common \
  --agent-cmd "$copy_sol"'; printf "\312\376\272\276" > Foo.class'
scenario "tampered class" false "class differs from build.sh output: Factorial.class" $common \
  --oracle --agent-cmd "$FAKE/oracle.sh"' && printf "\000" >> Factorial.class'
scenario "copied reference without --oracle" false "hex identical to reference solution" $common \
  --agent-cmd "$copy_sol"
scenario "agent timeout" false "timeout" $common --timeout 3 --agent-cmd 'sleep 600'
scenario "wrong major" false "wrong major: Factorial.class is 49, want 65" $common \
  --oracle --agent-cmd "$FAKE/oracle.sh"' && rm -f *.class && sed "s/^00 41  /00 31  /" Factorial.hex > F.tmp && mv F.tmp Factorial.hex'
scenario "bad hex" false "build.sh failed" $common \
  --oracle --agent-cmd "$FAKE/oracle.sh"' && rm -f *.class && echo "ZZ" >> Factorial.hex'
scenario "check.sh fails" false "check.sh failed" $common \
  --oracle --agent-cmd "$FAKE/oracle.sh"' && rm -f *.class && sed "s/^00 31  /00 21  /" Helper.hex > H.tmp && mv H.tmp Helper.hex'
scenario "wrong behavior" false "cases failed" $common \
  --oracle --agent-cmd "$FAKE/oracle.sh"' && rm -f *.class && sed "s/^10 14  /10 13  /" Factorial.hex > F.tmp && mv F.tmp Factorial.hex'

echo "== summary format =="
s="$tmp/out-oracle__throwaway_task__both_modes/summary.md"
if grep -q '^| 90-selftest-factorial | skill | 1 | 100% (1/1) | 100% |' "$s" &&
   grep -q '^## Skill vs baseline' "$s" && grep -q '^| 90-selftest-factorial | 0 pp | 0 pp |' "$s"; then
  echo "PASS  summary.md has per task x mode rows and the delta table"
else
  echo "FAIL  summary.md format"; sed 's/^/    /' "$s"; failures=$((failures + 1))
fi

echo
if [ "$failures" -eq 0 ]; then echo "selftest: all passed"; else echo "selftest: $failures failed"; fi
[ "$failures" -eq 0 ]
