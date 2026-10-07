# Shared helpers for the eval harness. Source from bash (3.2 compatible).

# json_str <text>: prints a JSON string literal (with quotes).
json_str() {
  printf '"%s"' "$(printf '%s' "$1" | tr '\n\t\r' '   ' | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g')"
}

# abs_path <path>: physical absolute path of an existing file or directory.
abs_path() {
  if [ -d "$1" ]; then (cd "$1" && pwd -P); else
    printf '%s/%s\n' "$(cd "$(dirname "$1")" && pwd -P)" "$(basename "$1")"
  fi
}

# expect_field <expect-file> <key>: value of the `key: value` line, or empty.
expect_field() {
  sed -n "s/^$2:[[:space:]]*//p" "$1" | head -n 1 | sed 's/[[:space:]]*$//'
}

# required_classes <expect-file>: the `files:` list, or the `class:` value.
required_classes() {
  local f
  f=$(expect_field "$1" files)
  [ -n "$f" ] || f=$(expect_field "$1" class)
  printf '%s\n' "$f"
}

# run_with_timeout <seconds> <stdin> <out-file> <err-file> <cmd> [args...]
# Runs cmd in its own process group with a wall-clock limit and no `timeout`
# binary. Kills the whole group on expiry. Returns cmd's exit code, or 124 on
# timeout. Pass the same path for out and err to merge them.
# Optional early abort: if RWT_GRACE (seconds) and RWT_ABORT_CHECK (a command,
# run once with eval when RWT_GRACE seconds have elapsed) are set and the check
# succeeds, the group is killed and 125 is returned.
run_with_timeout() {
  local limit=$1 in=$2 out=$3 err=$4 pid wd rc flag
  shift 4
  flag=$(mktemp "${TMPDIR:-/tmp}/rwt.XXXXXX")
  rm -f "$flag"
  set -m
  if [ "$out" = "$err" ]; then
    "$@" <"$in" >"$out" 2>&1 &
  else
    "$@" <"$in" >"$out" 2>"$err" &
  fi
  pid=$!
  (
    start=$(date +%s)
    deadline=$(( start + limit ))
    checked=0
    [ -n "${RWT_ABORT_CHECK:-}" ] && [ "${RWT_GRACE:-0}" -gt 0 ] 2>/dev/null || checked=1
    while kill -0 "$pid" 2>/dev/null; do
      now=$(date +%s)
      why=""
      if [ "$now" -ge "$deadline" ]; then
        why=timeout
      elif [ "$checked" = 0 ] && [ $(( now - start )) -ge "$RWT_GRACE" ]; then
        checked=1
        eval "$RWT_ABORT_CHECK" && why=abort
      fi
      if [ -n "$why" ]; then
        echo "$why" >"$flag"
        kill -TERM -- "-$pid" 2>/dev/null
        sleep 5
        kill -KILL -- "-$pid" 2>/dev/null
        exit 0
      fi
      sleep 1
    done
  ) >/dev/null 2>&1 &
  wd=$!
  set +m
  wait "$pid" 2>/dev/null
  rc=$?
  kill "$wd" 2>/dev/null
  wait "$wd" 2>/dev/null
  # Reap anything the command left running in its process group.
  kill -TERM -- "-$pid" 2>/dev/null
  if [ -e "$flag" ]; then
    rc=124
    [ "$(cat "$flag")" = abort ] && rc=125
    rm -f "$flag"
  fi
  return "$rc"
}

# workdir_manifest <dir>: one "<cksum>-<size> <./path>" line per file under dir.
workdir_manifest() {
  (cd "$1" && find . ! -type d | LC_ALL=C sort | while IFS= read -r f; do
    printf '%s %s\n' "$(cksum <"$f" 2>/dev/null | awk '{ print $1 "-" $2 }')" "$f"
  done)
}

# changed_files <dir> <manifest>: ./paths of files under dir that are new or
# differ from the manifest written by workdir_manifest before the agent ran.
changed_files() {
  workdir_manifest "$1" | awk 'NR == FNR { seen[$0] = 1; next }
    !($0 in seen) { sub(/^[^ ]* /, ""); print }' "$2" -
}

# load_patterns <pattern-file> <out-file>: the pattern file without comment
# and blank lines (an empty line in a grep -f file would match everything).
load_patterns() {
  : >"$2"
  [ -f "$1" ] && grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$1" >"$2"
  return 0
}

# first_match_line <log> <clean-pattern-file>: first log line matching any
# pattern (extended regex, case-insensitive), at most 200 characters.
first_match_line() {
  [ -s "$2" ] && [ -f "$1" ] || return 1
  LC_ALL=C grep -a -i -E -m 1 -f "$2" "$1" | head -n 1 | cut -c 1-200 | grep .
}

# file_mtime <file>: modification time in epoch seconds (GNU or BSD stat).
file_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}
