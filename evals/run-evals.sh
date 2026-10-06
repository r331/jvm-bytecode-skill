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

# ---- run ----
echo "tasks:$selected"
echo "modes: $modes, trials: $trials, timeout: ${limit}s"
echo "results: $out"
for task in $selected; do
  td="$tasks_dir/$task"
  t=1
  while [ "$t" -le "$trials" ]; do
    for m in $modes; do
      tdir="$out/trials/$task/$m-$t"
      mkdir -p "$tdir"
      wd=$(mktemp -d "${TMPDIR:-/tmp}/jvm-eval.XXXXXX")
      wd=$(abs_path "$wd")
      if [ "$m" = skill ]; then
        mkdir -p "$wd/skill"
        cp "$REPO_DIR/SKILL.md" "$REPO_DIR/build.sh" "$wd/skill/"
        cp -R "$REPO_DIR/references" "$wd/skill/references"
      fi
      write_prompt "$wd" "$td" "$m"
      write_shims "$wd"
      cp "$wd/PROMPT.md" "$tdir/PROMPT.md"

      printf '%-28s %-8s trial %s ... ' "$task" "$m" "$t"
      start=$(date +%s)
      (
        cd "$wd" || exit 1
        export PROMPT_FILE="$wd/PROMPT.md" WORKDIR="$wd" EVAL_TASK="$task" EVAL_MODE="$m" EVAL_TRIAL="$t"
        export PATH="$wd/.shims:$PATH"
        unset ORACLE_SOLUTION_DIR
        [ "$oracle" = 1 ] && [ -d "$td/solution" ] && export ORACLE_SOLUTION_DIR="$td/solution"
        run_with_timeout "$limit" "$wd/PROMPT.md" "$tdir/agent.log" "$tdir/agent.log" bash -c "$agent_cmd"
      )
      rc=$?
      dur=$(( $(date +%s) - start ))
      to=0
      [ "$rc" = 124 ] && to=1

      line=$(EVAL_MODE="$m" EVAL_TRIAL="$t" EVAL_DURATION_S="$dur" EVAL_TIMED_OUT="$to" \
        EVAL_AGENT_EXIT="$rc" EVAL_ALLOW_SOLUTION="$oracle" \
        bash "$EVALS_DIR/grade.sh" "$wd" "$td" 2>"$tdir/grade.log")
      [ -n "$line" ] || line="{\"task\":$(json_str "$task"),\"mode\":\"$m\",\"trial\":$t,\"pass\":false,\"reason\":\"grader error\",\"cases_passed\":0,\"cases_total\":0,\"duration_s\":$dur,\"timed_out\":false,\"agent_exit\":$rc}"
      printf '%s\n' "$line" >>"$results"
      printf '%s\n' "$line" >"$tdir/result.json"
      printf '%s\n' "$(printf '%s' "$line" | sed -n 's/.*"pass":\([a-z]*\),"reason":"\(.*\)","cases_passed":\([0-9]*\),"cases_total":\([0-9]*\).*/\1 (\3\/\4 cases) \2/p') ${dur}s"

      # keep the agent's .hex files and the violation log for inspection
      (cd "$wd" && find . -name '*.hex' ! -path './skill/*' ! -type d) | while IFS= read -r f; do
        mkdir -p "$tdir/files/$(dirname "$f")" && cp "$wd/$f" "$tdir/files/$f"
      done
      [ -s "$wd/.shims/violations.log" ] && cp "$wd/.shims/violations.log" "$tdir/violations.log"
      if [ "$keep" = 1 ]; then echo "$wd" >"$tdir/workdir.txt"; else rm -rf "$wd"; fi
    done
    t=$((t + 1))
  done
done

bash "$EVALS_DIR/summarize.sh" "$results" | tee "$out/summary.md"
