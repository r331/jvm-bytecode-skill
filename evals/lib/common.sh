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
    deadline=$(( $(date +%s) + limit ))
    while kill -0 "$pid" 2>/dev/null; do
      if [ "$(date +%s)" -ge "$deadline" ]; then
        : >"$flag"
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
  if [ -e "$flag" ]; then rm -f "$flag"; return 124; fi
  return "$rc"
}
