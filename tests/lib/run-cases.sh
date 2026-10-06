#!/bin/bash
# Usage: run-cases.sh <class-dir> <ClassName> <cases-file>
#
# Runs `java -cp <class-dir> <ClassName> <args>` for every case and compares
# exit code, stdout, and stderr exactly. Exits non-zero if any case fails.
#
# cases-file format: one case per line, 4 TAB-separated fields:
#   args <TAB> exit <TAB> stdout <TAB> stderr
# - args: space-separated arguments (no quoting; use \s for a literal space
#   inside one argument, and the single token \e for an empty-string argument)
# - exit: expected exit code
# - stdout / stderr: expected output with the trailing newline removed;
#   \n stands for a newline, spaces are literal, empty field means no output
# Lines starting with '#' and blank lines are ignored.
# Optional env STDIN_DIR: if <STDIN_DIR>/<line-number>.in exists, it is fed as stdin.

set -u
set -f  # no glob expansion of case args like *

# Pin UTF-8 so non-ASCII args and output behave the same on every machine:
# the JVM decodes argv and encodes stdout/stderr according to the locale.
for loc in C.UTF-8 en_US.UTF-8; do
  if locale -a 2>/dev/null | grep -qix "$loc\|${loc/UTF-8/utf8}"; then export LC_ALL="$loc"; break; fi
done
java_opts="-Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8"

dir="${1:?usage: run-cases.sh <class-dir> <ClassName> <cases-file>}"
cls="${2:?missing ClassName}"
cases="${3:?missing cases-file}"

pass=0
fail=0
lineno=0

unescape() { printf '%b' "$(printf '%s' "$1" | sed 's/\\s/ /g')"; }

while IFS= read -r line || [ -n "$line" ]; do
  lineno=$((lineno + 1))
  case "$line" in ''|'#'*) continue ;; esac

  # cut keeps empty fields; `read` with IFS=TAB would collapse them.
  args=$(printf '%s\n' "$line" | cut -f1)
  want_exit=$(printf '%s\n' "$line" | cut -f2)
  want_out=$(printf '%b' "$(printf '%s\n' "$line" | cut -f3)")
  want_err=$(printf '%b' "$(printf '%s\n' "$line" | cut -f4)")

  argv=()
  for a in $args; do
    if [ "$a" = '\e' ]; then argv+=(""); else argv+=("$(unescape "$a")"); fi
  done

  stdin=/dev/null
  if [ -n "${STDIN_DIR:-}" ] && [ -f "$STDIN_DIR/$lineno.in" ]; then
    stdin="$STDIN_DIR/$lineno.in"
  fi

  out_file=$(mktemp) err_file=$(mktemp)
  java $java_opts -cp "$dir" "$cls" ${argv[@]+"${argv[@]}"} <"$stdin" >"$out_file" 2>"$err_file"
  got_exit=$?
  got_out=$(cat "$out_file")
  got_err=$(cat "$err_file")
  rm -f "$out_file" "$err_file"

  if [ "$got_exit" = "$want_exit" ] && [ "$got_out" = "$want_out" ] && [ "$got_err" = "$want_err" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL $cases:$lineno args=[$args]"
    [ "$got_exit" = "$want_exit" ] || echo "  exit:   want $want_exit, got $got_exit"
    [ "$got_out" = "$want_out" ] || printf '  stdout: want [%s]\n          got  [%s]\n' "$want_out" "$got_out"
    [ "$got_err" = "$want_err" ] || printf '  stderr: want [%s]\n          got  [%s]\n' "$want_err" "$got_err"
  fi
done <"$cases"

echo "$cls: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
