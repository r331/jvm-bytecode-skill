#!/bin/bash
# Usage: selftest.sh
# Self-test of the eval harness that needs no AI model. Runs run-evals.sh with
# fake agents and asserts the grading outcome of every trial:
#   - the oracle (reference solution) passes every task in evals/tasks and a
#     throwaway task built from tests/programs/factorial-v65, in both modes
#   - cheaters, a no-op agent, and broken solutions fail with the right reason
#   - agent errors are classified, retried, and cut short by the watchdog
#   - leaks are flagged, task inputs are exempt unless modified, --isolate works
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
# fast retries for the agent error scenarios
export EVAL_RETRY_BACKOFF="1 1"

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

# ---- throwaway task with inputs/: a prebuilt Helper.class and a .java file ----
ITASKS="$tmp/tasks-inputs"
IT="$ITASKS/91-selftest-inputs"
mkdir -p "$IT/solution" "$IT/inputs"
cp "$SOL/Factorial.hex" "$IT/solution/"
cp "$T/cases.txt" "$IT/cases.txt"
(cd "$tmp" && cp "$SOL/Helper.hex" . && sh "$REPO_DIR/build.sh" Helper >/dev/null && mv Helper.class "$IT/inputs/" && rm Helper.hex)
printf 'public final class Helper {}\n' >"$IT/inputs/Helper.java"
printf 'class: Factorial\nmajor: 65\n' >"$IT/expect"
cat >"$IT/prompt.md" <<'EOF'
Write class `Factorial` (major version 65) whose `main` prints n! for one integer argument 0..20.
`Helper.class` is given; do not change it.
EOF
cat >"$IT/check.sh" <<'EOF'
#!/bin/bash
# Asserts the input class is on the grader's class path next to the deliverable.
javap -p -cp "$1" Helper | grep -q 'public final class Helper' || { echo "input Helper.class missing"; exit 1; }
EOF
chmod +x "$IT/check.sh"

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

# expect_json <label> <results.jsonl> <"key":value>...: every line contains each fragment.
expect_json() {
  local label=$1 f=$2 frag bad=0
  shift 2
  for frag in "$@"; do
    if [ ! -s "$f" ] || grep -v -F -q "$frag" "$f"; then
      bad=1; echo "    missing $frag in:"; sed 's/^/      /' "$f"
    fi
  done
  if [ "$bad" = 0 ]; then echo "PASS  $label ($*)"; else echo "FAIL  $label"; failures=$((failures + 1)); fi
}

# check <label> <command...>: passes if the command succeeds.
check() {
  local label=$1
  shift
  if "$@"; then echo "PASS  $label"; else echo "FAIL  $label"; failures=$((failures + 1)); fi
}

# scenario <label> <want-pass> <reason-prefix> <run-evals args...>
# Leaves the results directory in $last_out.
scenario() {
  local label=$1 want=$2 prefix=$3 o
  shift 3
  o="$tmp/out-$(printf '%s' "$label" | tr -c 'A-Za-z0-9' '_')"
  last_out=$o
  if ! bash "$RUN" --trials 1 --out "$o" "$@" >"$o.log" 2>&1; then
    echo "FAIL  $label (harness exited non-zero, see below)"; sed 's/^/    /' "$o.log"
    failures=$((failures + 1)); return
  fi
  local errs='syntax error|unbound variable|command not found|No such file|integer expression'
  if find "$o" -name grade.log | xargs cat "$o.log" | grep -E "$errs" >/dev/null; then
    echo "FAIL  $label (shell errors in the harness or grader output)"
    find "$o" -name grade.log | xargs cat "$o.log" | grep -E "$errs" | sed 's/^/    /'
    failures=$((failures + 1))
  fi
  expect_results "$label" "$o/results.jsonl" "$want" "$prefix"
}

copy_sol='cp "'"$SOL"'"/*.hex .'

echo "== oracle =="
scenario "oracle, throwaway task, both modes" true ok \
  --tasks-dir "$TASKS" --mode both --oracle --agent-cmd "$FAKE/oracle.sh"
expect_json "oracle has no agent error and no leak" "$last_out/results.jsonl" \
  '"agent_error":false' '"leak_suspect":false' '"attempts":1'
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
scenario "agent timeout" false "timeout" $common --timeout 3 --agent-cmd 'echo draft > notes.txt; sleep 600'
scenario "wrong major" false "wrong major: Factorial.class is 49, want 65" $common \
  --oracle --agent-cmd "$FAKE/oracle.sh"' && rm -f *.class && sed "s/^00 41  /00 31  /" Factorial.hex > F.tmp && mv F.tmp Factorial.hex'
scenario "bad hex" false "build.sh failed" $common \
  --oracle --agent-cmd "$FAKE/oracle.sh"' && rm -f *.class && echo "ZZ" >> Factorial.hex'
scenario "check.sh fails" false "check.sh failed" $common \
  --oracle --agent-cmd "$FAKE/oracle.sh"' && rm -f *.class && sed "s/^00 31  /00 21  /" Helper.hex > H.tmp && mv H.tmp Helper.hex'
scenario "wrong behavior" false "cases failed" $common \
  --oracle --agent-cmd "$FAKE/oracle.sh"' && rm -f *.class && sed "s/^10 14  /10 13  /" Factorial.hex > F.tmp && mv F.tmp Factorial.hex'

echo "== agent errors (throwaway task) =="
scenario "agent error, retried twice" false "agent error: Error getting AWS credentials" $common \
  --retry-agent-errors 2 --agent-cmd "$FAKE/agent-error.sh"
ae_out=$last_out
expect_json "agent error fields" "$ae_out/results.jsonl" '"agent_error":true' '"attempts":3' '"agent_exit":1'
td="$ae_out/trials/90-selftest-factorial/skill-1"
check "agent error attempts kept in the trial dir" \
  test -f "$td/attempt-1/agent.log" -a -f "$td/attempt-2/result.json" -a -f "$td/agent.log" -a ! -e "$td/attempt-3"
check "agent error results.jsonl has only the final attempt" test "$(grep -c . "$ae_out/results.jsonl")" = 1
scenario "agent error, no retries" false "agent error" $common \
  --retry-agent-errors 0 --agent-cmd "$FAKE/agent-error.sh"
expect_json "agent error without retry" "$last_out/results.jsonl" '"attempts":1'
scenario "non-zero exit, no files, no pattern" false "agent error: exit 3 with no files" $common \
  --retry-agent-errors 0 --agent-cmd 'exit 3'
scenario "timeout with no files" false "agent error: timeout with no files" $common \
  --retry-agent-errors 0 --timeout 3 --agent-cmd 'sleep 600'
start=$(date +%s)
scenario "hang after error, killed by the watchdog" false "agent error: Error getting AWS credentials" $common \
  --retry-agent-errors 0 --timeout 120 --agent-error-grace 2 --agent-cmd "$FAKE/hang-error.sh"
elapsed=$(( $(date +%s) - start ))
expect_json "watchdog fields" "$last_out/results.jsonl" '"agent_error":true' '"early_abort":true' '"timed_out":false'
check "watchdog killed the agent early (${elapsed}s, timeout 120s)" test "$elapsed" -lt 60
scenario "error logged but files written: graded normally" true ok $common --oracle \
  --agent-cmd 'echo "Error getting AWS credentials from awsCredentialExport" >&2; '"$FAKE/oracle.sh"
expect_json "error with files is no agent error" "$last_out/results.jsonl" '"agent_error":false'
scenario "error then busy log: not killed by the watchdog" true ok $common --oracle --agent-error-grace 2 \
  --agent-cmd 'echo "Error getting AWS credentials" >&2; for i in 1 2 3 4 5 6; do echo working; sleep 1; done; '"$FAKE/oracle.sh"
expect_json "busy agent not aborted" "$last_out/results.jsonl" '"early_abort":false' '"agent_error":false'
scenario "custom pattern file" false "agent error: QUOTA-XYZ" $common --retry-agent-errors 0 \
  --agent-error-patterns "$(printf 'quota-xyz\n' >"$tmp/pat.txt"; echo "$tmp/pat.txt")" --agent-cmd 'echo QUOTA-XYZ hit'
scenario "summary excludes agent errors" false "agent error" $common --retry-agent-errors 0 \
  --agent-cmd "$FAKE/agent-error.sh"
check "summary row counts the agent error and has no pass rate" \
  grep -q '^| 90-selftest-factorial | skill | 1 | 1 | 0 | n/a (0/0) | n/a | n/a |  |' "$last_out/summary.md"
cat "$ae_out/results.jsonl" "$tmp/out-oracle__throwaway_task__both_modes/results.jsonl" >"$tmp/mixed.jsonl"
bash "$EVALS_DIR/summarize.sh" "$tmp/mixed.jsonl" >"$tmp/mixed.md"
check "mixed summary: 2 trials, 1 agent error, 100% of graded" \
  grep -q '^| 90-selftest-factorial | skill | 2 | 1 | 0 | 100% (1/1) | 100% |' "$tmp/mixed.md"
printf '%s\n' '{"task":"old","mode":"skill","trial":1,"pass":true,"reason":"ok","cases_passed":2,"cases_total":2,"duration_s":5,"timed_out":false,"agent_exit":0}' >"$tmp/old.jsonl"
bash "$EVALS_DIR/summarize.sh" "$tmp/old.jsonl" >"$tmp/old.md"
check "summary reads old results without the new fields" grep -q '^| old | skill | 1 | 0 | 0 | 100% (1/1) | 100% | 5s |' "$tmp/old.md"

echo "== leaks =="
scenario "leaker is flagged but passes by default" true ok $common --oracle --agent-cmd "$FAKE/leaker.sh"
expect_json "leak_suspect recorded" "$last_out/results.jsonl" '"leak_suspect":true'
check "summary counts the leak suspect" grep -q '^| 90-selftest-factorial | skill | 1 | 0 | 1 | 100% (1/1)' "$last_out/summary.md"
scenario "leaker fails with --fail-on-leak" false "possible leak: $REPO_DIR" $common --oracle --fail-on-leak --agent-cmd "$FAKE/leaker.sh"

echo "== task inputs =="
icommon="--tasks-dir $ITASKS"
scenario "oracle leaves the inputs untouched, both modes" true ok $icommon --mode both --oracle --agent-cmd "$FAKE/oracle.sh"
check "prompt lists the input files" grep -q 'Input files provided by the task.*Helper.class Helper.java' \
  "$last_out/trials/91-selftest-inputs/skill-1/PROMPT.md"
check "unchanged inputs are not archived as agent files" test ! -e "$last_out/trials/91-selftest-inputs/skill-1/files/Helper.class"
scenario "agent modifies an input class" false "modified input file: Helper.class" $icommon --mode skill --oracle \
  --agent-cmd "$FAKE/oracle.sh"' && printf "\000" >> Helper.class'
scenario "agent modifies an input source file" false "modified input file: Helper.java" $icommon --mode skill --oracle \
  --agent-cmd "$FAKE/oracle.sh"' && echo "// x" >> Helper.java'
scenario "agent deletes an input class" true ok $icommon --mode skill --oracle \
  --agent-cmd "$FAKE/oracle.sh"' && rm Helper.class'

echo "== isolate =="
scenario "isolated oracle" true ok $common --isolate --oracle --agent-cmd "$FAKE/oracle.sh"
scenario "isolated: copied reference still detected" false "hex identical to reference solution" $common --isolate \
  --agent-cmd "$copy_sol"
scenario "isolated: workdir and env do not reference the repo" true ok $common --isolate --oracle --fail-on-leak \
  --agent-cmd 'pwd; env | grep -v "^ORACLE_SOLUTION_DIR=" | grep -v "^AGENT_CMD=" | grep -v "^_="; cat PROMPT.md; '"$FAKE/oracle.sh"
scenario "isolated: leaker still flagged" false "possible leak: $REPO_DIR" $common --isolate --oracle --fail-on-leak \
  --agent-cmd "$FAKE/leaker.sh"
iso=$(sed -n 's/^isolated harness: //p' "$last_out.log")
check "isolated harness dir removed after the run" test -n "$iso" -a ! -e "$iso"

echo "== summary format =="
s="$tmp/out-oracle__throwaway_task__both_modes/summary.md"
if grep -q '^| 90-selftest-factorial | skill | 1 | 0 | 0 | 100% (1/1) | 100% |' "$s" &&
   grep -q '^## Skill vs baseline' "$s" && grep -q '^| 90-selftest-factorial | 0 pp | 0 pp |' "$s"; then
  echo "PASS  summary.md has per task x mode rows and the delta table"
else
  echo "FAIL  summary.md format"; sed 's/^/    /' "$s"; failures=$((failures + 1))
fi

echo
if [ "$failures" -eq 0 ]; then echo "selftest: all passed"; else echo "selftest: $failures failed"; fi
[ "$failures" -eq 0 ]
