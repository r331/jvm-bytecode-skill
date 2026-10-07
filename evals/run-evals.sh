#!/bin/bash
# Model eval harness for the jvm-bytecode skill. See evals/README.md.
#
# Usage: run-evals.sh --agent-cmd '<shell command>' [options]
#   --agent-cmd CMD   command that runs the agent (or env AGENT_CMD). Run with
#                     bash -c, cwd = trial workdir, stdin = PROMPT.md, and env
#                     PROMPT_FILE, WORKDIR, EVAL_TASK, EVAL_MODE, EVAL_TRIAL.
#   --tasks LIST      task names or globs, comma or space separated (default: all)
#   --tasks-dir DIR   tasks directory (default: evals/tasks)
#   --trials N        trials per task and mode (default: 3)
#   --mode M          skill | baseline | both (default: both)
#   --timeout S       per-trial wall-clock limit in seconds (default: 1200)
#   --out DIR         results directory (default: evals/results/<timestamp>)
#   --keep            keep trial workdirs (path recorded in the trial dir)
#   --agent-error-patterns FILE
#                     extended regexes (one per line) that mark an agent error in
#                     agent.log (default: evals/agent-error-patterns.txt)
#   --agent-error-grace S
#                     kill the agent after S seconds if agent.log matches an agent
#                     error pattern, has been idle for S/2 seconds, and the agent
#                     has produced no files (default: 120; 0 disables)
#   --retry-agent-errors N
#                     rerun a trial that ended as an agent error up to N times,
#                     after a backoff of 30s, then 90s (env EVAL_RETRY_BACKOFF
#                     overrides, e.g. "1 1"); only the last attempt counts (default: 2)
#   --fail-on-leak    fail trials whose agent.log suggests the agent read the
#                     repository (default: only record leak_suspect)
#   --isolate         copy the harness, skill, and the tasks' prompt.md, expect,
#                     cases.txt, check.sh, stdin/, and inputs/ (no solution/)
#                     into a temp dir and run from there; solutions stay
#                     readable only by the grader
#   --oracle          expose the task's reference solution to the agent via
#                     env ORACLE_SOLUTION_DIR (self-test only, never for real agents)
#   -h, --help        show this help

set -u
EVALS_DIR=$(cd "$(dirname "$0")" && pwd -P)
REPO_DIR=$(cd "$EVALS_DIR/.." && pwd -P)
. "$EVALS_DIR/lib/common.sh"

agent_cmd="${AGENT_CMD:-}"
tasks_sel=""
tasks_dir="$EVALS_DIR/tasks"
trials=3
mode=both
limit=1200
out=""
keep=0
oracle=0
patterns_file="$EVALS_DIR/agent-error-patterns.txt"
grace=120
retries=2
fail_on_leak=0
isolate=0
backoff="${EVAL_RETRY_BACKOFF:-30 90}"
orig_args=("$@")

usage() { sed -n '2,/^$/s/^# \{0,1\}//p' "$0"; }
die() { echo "run-evals.sh: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --agent-cmd) agent_cmd="${2:?}"; shift 2 ;;
    --tasks) tasks_sel="${2:?}"; shift 2 ;;
    --tasks-dir) tasks_dir="${2:?}"; shift 2 ;;
    --trials) trials="${2:?}"; shift 2 ;;
    --mode) mode="${2:?}"; shift 2 ;;
    --timeout) limit="${2:?}"; shift 2 ;;
    --out) out="${2:?}"; shift 2 ;;
    --keep) keep=1; shift ;;
    --oracle) oracle=1; shift ;;
    --agent-error-patterns) patterns_file="${2:?}"; shift 2 ;;
    --agent-error-grace) grace="${2:?}"; shift 2 ;;
    --retry-agent-errors) retries="${2:?}"; shift 2 ;;
    --fail-on-leak) fail_on_leak=1; shift ;;
    --isolate) isolate=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

[ -n "$agent_cmd" ] || die "no agent command: pass --agent-cmd or set AGENT_CMD"
# The agent runs in the trial workdir, so a relative script path would not resolve there.
case "$agent_cmd" in /*) ;; *) [ -f "$agent_cmd" ] && agent_cmd="'$(abs_path "$agent_cmd")'" ;; esac
case "$mode" in skill) modes=skill ;; baseline) modes=baseline ;; both) modes="skill baseline" ;;
  *) die "--mode must be skill, baseline, or both" ;; esac
case "$trials" in ''|*[!0-9]*|0) die "--trials must be a positive integer" ;; esac
case "$limit" in ''|*[!0-9]*|0) die "--timeout must be a positive integer" ;; esac
case "$grace" in ''|*[!0-9]*) die "--agent-error-grace must be a non-negative integer" ;; esac
case "$retries" in ''|*[!0-9]*) die "--retry-agent-errors must be a non-negative integer" ;; esac
for b in $backoff; do
  case "$b" in *[!0-9]*) die "EVAL_RETRY_BACKOFF must be whole seconds separated by spaces" ;; esac
done
[ -f "$patterns_file" ] || die "agent error pattern file not found: $patterns_file"
patterns_file=$(abs_path "$patterns_file")
[ -d "$tasks_dir" ] || die "tasks directory not found: $tasks_dir"
tasks_dir=$(abs_path "$tasks_dir")

real_java=$(command -v java) || die "java not found on PATH"
command -v javap >/dev/null || die "javap not found on PATH"

# ---- select tasks ----
selected=""
for d in "$tasks_dir"/*/; do
  [ -f "$d/prompt.md" ] && [ -f "$d/expect" ] || continue
  name=$(basename "$d")
  if [ -z "$tasks_sel" ]; then
    selected="$selected $name"
  else
    for pat in $(printf '%s' "$tasks_sel" | tr ',' ' '); do
      # shellcheck disable=SC2254
      case "$name" in $pat) selected="$selected $name"; break ;; esac
    done
  fi
done
[ -n "$selected" ] || die "no tasks matched in $tasks_dir"

if [ -z "$out" ]; then out="$EVALS_DIR/results/$(date +%Y%m%d-%H%M%S)"; fi
mkdir -p "$out" || die "cannot create $out"
out=$(abs_path "$out")

# Solutions live here; differs from tasks_dir only inside an --isolate run.
sol_root="${EVAL_SOLUTIONS_DIR:-$tasks_dir}"

# ---- --isolate: rerun this script from a copy that has no solutions ----
if [ "$isolate" = 1 ] && [ -z "${EVAL_ISOLATED:-}" ]; then
  iso=$(mktemp -d "${TMPDIR:-/tmp}/jvm-eval-harness.XXXXXX") || die "cannot create temp dir"
  iso=$(abs_path "$iso")
  mkdir -p "$iso/evals/lib" "$iso/evals/tasks" "$iso/tests/lib"
  cp "$REPO_DIR/SKILL.md" "$REPO_DIR/build.sh" "$iso/" &&
    cp -R "$REPO_DIR/references" "$iso/references" &&
    cp "$REPO_DIR/tests/lib/run-cases.sh" "$iso/tests/lib/" &&
    cp "$EVALS_DIR/run-evals.sh" "$EVALS_DIR/grade.sh" "$EVALS_DIR/summarize.sh" "$iso/evals/" &&
    cp "$EVALS_DIR/lib/common.sh" "$iso/evals/lib/" &&
    cp "$patterns_file" "$iso/evals/agent-error-patterns.txt" || { rm -rf "$iso"; die "cannot copy the harness to $iso"; }
  # Only what the harness and grader read; solution/ and maintainer files stay behind.
  for task in $selected; do
    mkdir -p "$iso/evals/tasks/$task"
    for f in prompt.md expect cases.txt check.sh stdin inputs; do
      [ -e "$tasks_dir/$task/$f" ] || continue
      cp -R "$tasks_dir/$task/$f" "$iso/evals/tasks/$task/" || { rm -rf "$iso"; die "cannot copy task $task to $iso"; }
    done
  done
  echo "isolated harness: $iso"
  leak_paths=$(printf '%s\n%s\n%s' "$REPO_DIR" "$(cd "$REPO_DIR" && pwd)" "$iso" | sort -u)
  EVAL_ISOLATED=1 EVAL_SOLUTIONS_DIR="$sol_root" EVAL_LEAK_PATHS="$leak_paths" \
    bash "$iso/evals/run-evals.sh" "${orig_args[@]}" --agent-cmd "$agent_cmd" \
    --tasks-dir "$iso/evals/tasks" --out "$out" --agent-error-patterns "$iso/evals/agent-error-patterns.txt"
  rc=$?
  rm -rf "$iso"
  exit "$rc"
fi
leak_paths="${EVAL_LEAK_PATHS:-$(printf '%s\n%s' "$REPO_DIR" "$(cd "$REPO_DIR" && pwd)" | sort -u)}"

results="$out/results.jsonl"
: >>"$results"

# ---- prompt preamble ----
write_prompt() { # <workdir> <taskdir> <mode>
  local wd=$1 td=$2 m=$3 cls major files
  cls=$(expect_field "$td/expect" class)
  major=$(expect_field "$td/expect" major)
  files=$(required_classes "$td/expect")
  {
    echo "# Instructions"
    echo
    echo "You are being evaluated on writing a JVM program directly as hand-authored class file bytes."
    if [ "$m" = skill ]; then
      echo "Read skill/SKILL.md and follow it."
      echo "Its reference files are in skill/references/ and its build script is skill/build.sh."
    else
      echo "No skill or build script is provided; if the task text mentions one, convert your .hex to a .class yourself for testing (for example with sed and xxd -r -p)."
    fi
    echo
    echo "Work only in this directory: $wd"
    echo "Write all your files in this directory, and put each <ClassName>.hex directly in it, not in a subdirectory."
    echo
    echo "Rules:"
    echo "- Do not write source code in Java, Kotlin, Scala, Groovy, Clojure, or any other language that compiles to JVM bytecode, and do not write Jasmin, Krakatau, or other assembler input."
    echo "- Do not use any compiler, assembler, bytecode library, or script that generates the class file bytes; every byte must come from your hand-written .hex file."
    echo "- The .hex format: pairs of hex digits separated by whitespace; '#' starts a comment that runs to the end of the line; nothing else is allowed outside comments."
    echo "- Any .class file left in this directory must be exactly the bytes of the .hex file with the same name."
    echo "- You may use java and javap to inspect and test your classes."
    echo "- Work non-interactively: do not ask questions, and stop when you are done."
    if [ -d "$td/inputs" ]; then
      echo "- Input files provided by the task are in this directory; do not modify, move, or delete them (the .class rule above does not apply to them): $(cd "$td/inputs" && find . ! -type d | sed 's|^\./||' | sort | tr '\n' ' ' | sed 's/ $//')"
    fi
    echo
    echo "Required files: $(for c in $files; do printf '%s.hex ' "$(printf '%s' "$c" | tr . /)"; done | sed 's/ $//')"
    echo "Main class: $cls"
    [ -z "$major" ] || echo "Class file major version: $major"
    echo
    echo "Grading: each .hex is turned into bytes by stripping comments and decoding the hex digits, parsed with javap, and run with java against hidden test cases that compare stdout, stderr, and the exit code exactly."
    echo
    echo "# Task"
    echo
    cat "$td/prompt.md"
  } >"$wd/PROMPT.md"
}

# ---- tool shims ----
write_shims() { # <workdir>
  local sd="$1/.shims" t
  mkdir -p "$sd"
  : >"$sd/violations.log"
  for t in javac kotlinc kotlin scalac scala groovyc groovy jshell jasmin krakatau jar; do
    cat >"$sd/$t" <<EOF
#!/bin/sh
printf '%s %s\n' "$t" "\$*" >>"$sd/violations.log"
echo "$t is not allowed in this evaluation" >&2
exit 1
EOF
    chmod +x "$sd/$t"
  done
  # java stays usable, but its source-file launcher (java Foo.java) is a compiler.
  cat >"$sd/java" <<EOF
#!/bin/sh
for a in "\$@"; do
  case "\$a" in
    *.java|--source|--source=*)
      printf 'java %s\n' "\$*" >>"$sd/violations.log"
      echo "java source-file mode is not allowed in this evaluation" >&2
      exit 1 ;;
  esac
done
exec "$real_java" "\$@"
EOF
  chmod +x "$sd/java"
}

# ---- agent error watchdog (runs inside run_with_timeout's watcher) ----
# Globals: wd, manifest, alog, clean_patterns, abort_file, grace.
early_abort_check() {
  local line idle
  [ -z "$(changed_files "$wd" "$manifest" | head -n 1)" ] || return 1
  line=$(first_match_line "$alog" "$clean_patterns") || return 1
  idle=$(( $(date +%s) - $(file_mtime "$alog") ))
  [ "$idle" -ge $(( (grace + 1) / 2 )) ] || return 1
  printf '%s\n' "$line" >"$abort_file"
}

# backoff_for <retry-number>: seconds to wait before that retry.
backoff_for() {
  local i=0 b last=0
  for b in $backoff; do
    i=$((i + 1)); last=$b
    [ "$i" -lt "$1" ] || { echo "$b"; return; }
  done
  echo "$last"
}

# run_attempt <task> <taskdir> <mode> <trial> <attempt> <trial-results-dir>
# Runs the agent once in a fresh workdir and grades it; leaves the result line
# in <trial-results-dir>/result.json.
run_attempt() {
  local task=$1 td=$2 m=$3 t=$4 a=$5 tdir=$6 start dur rc to ea line f
  mkdir -p "$tdir"
  wd=$(mktemp -d "${TMPDIR:-/tmp}/jvm-eval.XXXXXX")
  wd=$(abs_path "$wd")
  manifest="$hdir/manifest"
  abort_file="$hdir/abort"
  alog="$tdir/agent.log"
  rm -f "$abort_file"
  [ -d "$td/inputs" ] && cp -R "$td/inputs/." "$wd/"
  if [ "$m" = skill ]; then
    mkdir -p "$wd/skill"
    cp "$REPO_DIR/SKILL.md" "$REPO_DIR/build.sh" "$wd/skill/"
    cp -R "$REPO_DIR/references" "$wd/skill/references"
  fi
  write_prompt "$wd" "$td" "$m"
  write_shims "$wd"
  cp "$wd/PROMPT.md" "$tdir/PROMPT.md"
  workdir_manifest "$wd" >"$manifest"

  start=$(date +%s)
  (
    cd "$wd" || exit 1
    unset OLDPWD ORACLE_SOLUTION_DIR EVAL_SOLUTIONS_DIR EVAL_LEAK_PATHS EVAL_ISOLATED
    export PROMPT_FILE="$wd/PROMPT.md" WORKDIR="$wd" EVAL_TASK="$task" EVAL_MODE="$m" EVAL_TRIAL="$t" EVAL_ATTEMPT="$a"
    export PATH="$wd/.shims:$PATH"
    [ "$oracle" = 1 ] && [ -d "$sol_root/$task/solution" ] && export ORACLE_SOLUTION_DIR="$sol_root/$task/solution"
    RWT_GRACE=$grace
    RWT_ABORT_CHECK=""
    [ "$grace" -gt 0 ] && RWT_ABORT_CHECK=early_abort_check
    run_with_timeout "$limit" "$wd/PROMPT.md" "$alog" "$alog" bash -c "$agent_cmd"
  )
  rc=$?
  dur=$(( $(date +%s) - start ))
  to=0; ea=0
  [ "$rc" = 124 ] && to=1
  [ "$rc" = 125 ] && [ -f "$abort_file" ] && ea=1

  line=$(EVAL_MODE="$m" EVAL_TRIAL="$t" EVAL_DURATION_S="$dur" EVAL_TIMED_OUT="$to" \
    EVAL_AGENT_EXIT="$rc" EVAL_ALLOW_SOLUTION="$oracle" EVAL_ATTEMPTS="$a" EVAL_EARLY_ABORT="$ea" \
    EVAL_AGENT_LOG="$alog" EVAL_MANIFEST="$manifest" EVAL_AGENT_ERROR_PATTERNS="$patterns_file" \
    EVAL_SOLUTIONS_DIR="$sol_root" EVAL_LEAK_PATHS="$leak_paths" EVAL_FAIL_ON_LEAK="$fail_on_leak" \
    bash "$EVALS_DIR/grade.sh" "$wd" "$td" 2>"$tdir/grade.log")
  [ -n "$line" ] || line="{\"task\":$(json_str "$task"),\"mode\":\"$m\",\"trial\":$t,\"pass\":false,\"reason\":\"grader error\",\"cases_passed\":0,\"cases_total\":0,\"duration_s\":$dur,\"timed_out\":false,\"agent_exit\":$rc,\"agent_error\":false,\"early_abort\":false,\"leak_suspect\":false,\"attempts\":$a}"
  printf '%s\n' "$line" >"$tdir/result.json"
  f=""
  case "$line" in *'"leak_suspect":true'*) f=" [leak suspect]" ;; esac
  printf '%s%s\n' "$(printf '%s' "$line" | sed -n 's/.*"pass":\([a-z]*\),"reason":"\(.*\)","cases_passed":\([0-9]*\),"cases_total":\([0-9]*\).*/\1 (\3\/\4 cases) \2/p') ${dur}s" "$f"

  # keep the agent's .hex files (not unchanged inputs or skill files) and the violation log
  changed_files "$wd" "$manifest" | while IFS= read -r f; do
    case "$f" in *.hex) ;; *) continue ;; esac
    case "$f" in ./skill/*|./.shims/*) continue ;; esac
    mkdir -p "$tdir/files/$(dirname "$f")" && cp "$wd/$f" "$tdir/files/$f"
  done
  [ -s "$wd/.shims/violations.log" ] && cp "$wd/.shims/violations.log" "$tdir/violations.log"
  if [ "$keep" = 1 ]; then echo "$wd" >"$tdir/workdir.txt"; else rm -rf "$wd"; fi
  return 0
}

# ---- run ----
hdir=$(mktemp -d "${TMPDIR:-/tmp}/jvm-eval-state.XXXXXX") || die "cannot create temp dir"
trap 'rm -rf "$hdir"' EXIT
load_patterns "$patterns_file" "$hdir/patterns"
clean_patterns="$hdir/patterns"
echo "tasks:$selected"
echo "modes: $modes, trials: $trials, timeout: ${limit}s, agent error grace: ${grace}s, retries: $retries"
echo "results: $out"
for task in $selected; do
  td="$tasks_dir/$task"
  t=1
  while [ "$t" -le "$trials" ]; do
    for m in $modes; do
      tdir="$out/trials/$task/$m-$t"
      a=1
      while :; do
        printf '%-28s %-8s trial %s%s ... ' "$task" "$m" "$t" "$([ "$a" -gt 1 ] && echo " (attempt $a)")"
        run_attempt "$task" "$td" "$m" "$t" "$a" "$tdir"
        line=$(cat "$tdir/result.json")
        case "$line" in *'"agent_error":true'*) ;; *) break ;; esac
        [ "$a" -le "$retries" ] || break
        # keep this attempt, then retry after a backoff
        mkdir -p "$tdir/attempt-$a"
        for f in PROMPT.md agent.log grade.log result.json files violations.log workdir.txt; do
          [ -e "$tdir/$f" ] && mv "$tdir/$f" "$tdir/attempt-$a/"
        done
        b=$(backoff_for "$a")
        echo "    agent error; retrying in ${b}s"
        sleep "$b"
        a=$((a + 1))
      done
      printf '%s\n' "$line" >>"$results"
    done
    t=$((t + 1))
  done
done

bash "$EVALS_DIR/summarize.sh" "$results" | tee "$out/summary.md"
