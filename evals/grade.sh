#!/bin/bash
# Usage: grade.sh <workdir> <taskdir>
#
# Grades one trial. Prints human-readable details to stderr and exactly one
# JSON line to stdout:
#   {"task":..,"mode":..,"trial":..,"pass":true|false,"reason":..,
#    "cases_passed":N,"cases_total":N,"duration_s":N,"timed_out":bool,"agent_exit":N,
#    "agent_error":bool,"early_abort":bool,"leak_suspect":bool,"attempts":N}
# Exits 0 on pass, 1 on fail.
#
# Optional env (set by run-evals.sh):
#   EVAL_MODE, EVAL_TRIAL, EVAL_DURATION_S, EVAL_TIMED_OUT (1/0), EVAL_AGENT_EXIT
#   EVAL_ATTEMPTS          attempt number of this run of the trial (default 1)
#   EVAL_EARLY_ABORT=1     the agent was killed by the agent error watchdog
#   EVAL_ALLOW_SOLUTION=1  do not flag hex files identical to the reference (oracle runs)
#   EVAL_SOLUTIONS_DIR     tasks directory that holds <task>/solution/ (default:
#                          the task dir itself; set by --isolate)
#   EVAL_AGENT_LOG         agent.log of the trial (agent error and leak checks)
#   EVAL_MANIFEST          workdir manifest taken before the agent ran (see
#                          workdir_manifest in lib/common.sh); without it, every
#                          file except PROMPT.md, .shims/, skill/ and unchanged
#                          inputs counts as produced by the agent
#   EVAL_AGENT_ERROR_PATTERNS  pattern file (default evals/agent-error-patterns.txt)
#   EVAL_LEAK_PATHS        extra newline-separated strings that indicate a leak
#   EVAL_FAIL_ON_LEAK=1    fail a trial whose agent.log looks like a leak
#   GRADE_TIMEOUT          wall-clock limit in seconds for check.sh and for the
#                          whole case run (default 300)
#
# Checks, in order (the first failing one becomes the reason):
#   0. agent error: the agent produced no files and exited non-zero, timed
#      out, or agent.log matches an agent error pattern; nothing else is graded
#   1. anti-cheating: shim violations, modified input files, forbidden source
#      files, .class without a matching .hex, .class that differs from what
#      build.sh makes of its .hex, required .hex identical to the reference
#      solution, possible leak (only with EVAL_FAIL_ON_LEAK=1)
#   2. agent timeout (cases are still run for partial credit)
#   3. every required class: .hex exists, builds with the repo build.sh in a
#      clean dir, javap -v parses it, major version matches
#   4. task check.sh (if present) passes
#   5. all cases in cases.txt pass

set -u
EVALS_DIR=$(cd "$(dirname "$0")" && pwd -P)
REPO_DIR=$(cd "$EVALS_DIR/.." && pwd -P)
BUILD_SH="$REPO_DIR/build.sh"
RUN_CASES="$REPO_DIR/tests/lib/run-cases.sh"
. "$EVALS_DIR/lib/common.sh"

wd="${1:?usage: grade.sh <workdir> <taskdir>}"
td="${2:?usage: grade.sh <workdir> <taskdir>}"
wd=$(abs_path "$wd")
td=$(abs_path "$td")
task=$(basename "$td")
mode="${EVAL_MODE:-unknown}"
trial="${EVAL_TRIAL:-0}"
duration="${EVAL_DURATION_S:-0}"
timed_out="${EVAL_TIMED_OUT:-0}"
agent_exit="${EVAL_AGENT_EXIT:-0}"
grade_timeout="${GRADE_TIMEOUT:-300}"
attempts="${EVAL_ATTEMPTS:-1}"
early_abort="${EVAL_EARLY_ABORT:-0}"
agent_log="${EVAL_AGENT_LOG:-}"
patterns="${EVAL_AGENT_ERROR_PATTERNS:-$EVALS_DIR/agent-error-patterns.txt}"
inputs="$td/inputs"
[ -d "$inputs" ] || inputs=""
soldir="$td/solution"
[ -z "${EVAL_SOLUTIONS_DIR:-}" ] || soldir="$EVAL_SOLUTIONS_DIR/$task/solution"

main_class=$(expect_field "$td/expect" class)
want_major=$(expect_field "$td/expect" major)
required=$(required_classes "$td/expect")

cases_total=0
if [ -f "$td/cases.txt" ]; then
  cases_total=$(grep -v -e '^#' -e '^[[:space:]]*$' "$td/cases.txt" | wc -l | tr -d ' ')
fi
cases_passed=0
reason=""
agent_error=0
leak=""
tmp=$(mktemp -d "${TMPDIR:-/tmp}/jvm-grade.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

log() { printf '%s\n' "$*" >&2; }
fail() { [ -n "$reason" ] || reason="$1"; log "FAIL: $1"; }

finish() {
  local pass=false
  [ -z "$reason" ] && { pass=true; reason=ok; }
  local to=false ae=false ea=false lk=false
  [ "$timed_out" = 1 ] && to=true
  [ "$agent_error" = 1 ] && ae=true
  [ "$early_abort" = 1 ] && ea=true
  [ -n "$leak" ] && lk=true
  printf '{"task":%s,"mode":%s,"trial":%s,"pass":%s,"reason":%s,"cases_passed":%s,"cases_total":%s,"duration_s":%s,"timed_out":%s,"agent_exit":%s,"agent_error":%s,"early_abort":%s,"leak_suspect":%s,"attempts":%s}\n' \
    "$(json_str "$task")" "$(json_str "$mode")" "$trial" "$pass" "$(json_str "$reason")" \
    "$cases_passed" "$cases_total" "$duration" "$to" "$agent_exit" "$ae" "$ea" "$lk" "$attempts"
  [ "$pass" = true ]
  exit $?
}

# class name (dots or slashes) -> relative path without extension
class_path() { printf '%s' "$1" | tr '.' '/'; }

# build_into <dir> <relpath-without-ext> <hex-file>: copies the hex into dir and
# runs the repo build.sh there. Returns build.sh's status.
build_into() {
  mkdir -p "$1/$(dirname "$2")"
  cp "$3" "$1/$2.hex"
  (cd "$1" && sh "$BUILD_SH" "$2") >"$1/.build.log" 2>&1
}

# unchanged_input <relpath>: true if relpath is a task input file that the
# agent left byte-identical in the workdir.
unchanged_input() {
  [ -n "$inputs" ] && [ -f "$inputs/$1" ] && cmp -s "$inputs/$1" "$wd/$1"
}

# ---- 0. agent error ----
# Files the agent produced: new or changed relative to the pre-run manifest.
if [ -n "${EVAL_MANIFEST:-}" ] && [ -f "$EVAL_MANIFEST" ]; then
  produced=$(changed_files "$wd" "$EVAL_MANIFEST" | head -n 1)
else
  produced=$(cd "$wd" && find . ! -type d ! -path ./PROMPT.md ! -path './.shims/*' ! -path './skill/*' \
    | while IFS= read -r f; do unchanged_input "${f#./}" || { echo "$f"; break; }; done)
fi
load_patterns "$patterns" "$tmp/patterns"
err_line=""
[ -n "$agent_log" ] && err_line=$(first_match_line "$agent_log" "$tmp/patterns")
if [ -z "$produced" ]; then
  if [ -n "$err_line" ]; then
    agent_error=1; fail "agent error: $err_line"
  elif [ "$timed_out" = 1 ]; then
    agent_error=1; fail "agent error: timeout with no files"
  elif [ "$agent_exit" != 0 ]; then
    agent_error=1; fail "agent error: exit $agent_exit with no files"
  fi
fi
if [ "$agent_error" = 1 ]; then
  log "agent error: not grading (the agent produced no files)"
fi

# ---- possible leak (recorded always, fails only with EVAL_FAIL_ON_LEAK=1) ----
if [ -n "$agent_log" ] && [ -f "$agent_log" ]; then
  {
    printf '%s\n' "$REPO_DIR" evals/tasks solution/ .claude/skills
    [ -z "${EVAL_LEAK_PATHS:-}" ] || printf '%s\n' "$EVAL_LEAK_PATHS"
  } | grep -v '^$' >"$tmp/leaks"
  leak=$(LC_ALL=C grep -a -o -F -f "$tmp/leaks" "$agent_log" | head -n 1)
  [ -z "$leak" ] || log "possible leak: agent.log contains '$leak'"
fi

[ "$agent_error" = 1 ] && finish

# ---- 1. anti-cheating ----
if [ -s "$wd/.shims/violations.log" ]; then
  fail "shim violation: $(head -n 1 "$wd/.shims/violations.log")"
fi

if [ -n "$inputs" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    f=${f#./}
    if [ -e "$wd/$f" ] && ! cmp -s "$inputs/$f" "$wd/$f"; then fail "modified input file: $f"; break; fi
  done <<EOF
$(cd "$inputs" && find . ! -type d | sort)
EOF
fi

src=$(cd "$wd" && find . ! -type d \( -name '*.java' -o -name '*.kt' -o -name '*.kts' \
  -o -name '*.scala' -o -name '*.groovy' -o -name '*.clj' -o -name '*.j' -o -name '*.jasm' \) \
  | sed 's|^\./||' | sort | while IFS= read -r f; do unchanged_input "$f" || echo "$f"; done \
  | tr '\n' ' ' | sed 's/ $//')
[ -z "$src" ] || fail "forbidden source file: $src"

if [ -z "$reason" ]; then
  n=0
  while IFS= read -r cf; do
    [ -n "$cf" ] || continue
    rel=${cf#./}
    unchanged_input "$rel" && continue
    rel=${rel%.class}
    if [ ! -f "$wd/$rel.hex" ]; then fail "class without hex: $rel.class"; break; fi
    n=$((n + 1))
    b="$tmp/cmp$n"
    if ! build_into "$b" "$rel" "$wd/$rel.hex" || ! cmp -s "$b/$rel.class" "$wd/$rel.class"; then
      fail "class differs from build.sh output: $rel.class"; break
    fi
  done <<EOF
$(cd "$wd" && find . -name '*.class' ! -type d | sort)
EOF
fi

if [ -z "$reason" ] && [ "${EVAL_ALLOW_SOLUTION:-0}" != 1 ] && [ -d "$soldir" ]; then
  for c in $required; do
    rel=$(class_path "$c")
    sol="$soldir/$rel.hex"
    [ -f "$sol" ] || sol="$soldir/$(basename "$rel").hex"
    if [ -f "$sol" ] && [ -f "$wd/$rel.hex" ] &&
       [ "$(tr -d '[:space:]' <"$sol")" = "$(tr -d '[:space:]' <"$wd/$rel.hex")" ]; then
      fail "hex identical to reference solution: $rel.hex"; break
    fi
  done
fi

if [ -n "$leak" ] && [ "${EVAL_FAIL_ON_LEAK:-0}" = 1 ]; then
  fail "possible leak: $leak"
fi

if [ -n "$reason" ]; then
  finish
fi

[ "$timed_out" = 1 ] && fail "timeout"

# ---- 3. build required classes in a clean dir with the repo build.sh ----
cdir="$tmp/classes"
mkdir -p "$cdir"
# Task inputs (the original bytes, not the agent's copy) sit next to the
# rebuilt classes, so deliverables can use input classes at run time.
[ -z "$inputs" ] || cp -R "$inputs/." "$cdir/"
built=1
for c in $required; do
  rel=$(class_path "$c")
  if [ ! -f "$wd/$rel.hex" ]; then fail "missing hex: $rel.hex"; built=0; continue; fi
  if ! build_into "$cdir" "$rel" "$wd/$rel.hex"; then
    fail "build.sh failed: $rel.hex: $(grep -v '^ *[0-9]*:' "$cdir/.build.log" | head -n 1)"
    built=0; continue
  fi
  rm -f "$cdir/$rel.hex"
  if ! javap -v -p -c "$cdir/$rel.class" >"$tmp/javap.log" 2>&1; then
    fail "javap failed: $rel.class: $(head -n 1 "$tmp/javap.log")"; built=0; continue
  fi
  got_major=$(od -An -tu1 -j6 -N2 "$cdir/$rel.class" | awk 'NF { print $1 * 256 + $2; exit }')
  if [ -n "$want_major" ] && [ "$got_major" != "$want_major" ]; then
    fail "wrong major: $rel.class is $got_major, want $want_major"; built=0
  fi
done
rm -f "$cdir/.build.log"

if [ "$built" = 1 ]; then
  # ---- 4. task check.sh ----
  if [ -f "$td/check.sh" ]; then
    run_with_timeout "$grade_timeout" /dev/null "$tmp/check.log" "$tmp/check.log" \
      bash "$td/check.sh" "$cdir"
    rc=$?
    sed 's/^/  check.sh: /' "$tmp/check.log" >&2
    [ "$rc" = 0 ] || fail "check.sh failed"
  fi

  # ---- 5. cases ----
  if [ -f "$td/cases.txt" ] && [ -n "$main_class" ]; then
    [ -d "$td/stdin" ] && export STDIN_DIR="$td/stdin"
    run_with_timeout "$grade_timeout" /dev/null "$tmp/cases.log" "$tmp/cases.log" \
      bash "$RUN_CASES" "$cdir" "$main_class" "$td/cases.txt"
    rc=$?
    cat "$tmp/cases.log" >&2
    p=$(sed -n 's/^.*: \([0-9][0-9]*\) passed, [0-9][0-9]* failed$/\1/p' "$tmp/cases.log" | tail -n 1)
    cases_passed=${p:-0}
    if [ "$rc" = 124 ]; then
      fail "cases timed out after ${grade_timeout}s"
    elif [ "$rc" != 0 ] || [ "$cases_passed" != "$cases_total" ]; then
      fail "cases failed: $cases_passed/$cases_total passed"
    fi
  elif [ -z "$main_class" ]; then
    fail "task expect file has no class: line"
  fi
fi

finish
