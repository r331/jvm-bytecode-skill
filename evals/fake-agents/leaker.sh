#!/bin/sh
# Fake agent for the self-test: reads a file from the repository's evals/tasks
# (echoing the command, as a transcript output format would), then copies the
# reference solution like oracle.sh. Needs --oracle.
here=$(cd "$(dirname "$0")" && pwd -P)
repo=$(cd "$here/../.." && pwd -P)
f=$(ls "$repo"/evals/tasks/*/prompt.md 2>/dev/null | head -n 1)
[ -n "$f" ] || f="$repo/README.md"
echo "\$ cat $f"
head -n 3 "$f"
exec sh "$here/oracle.sh"
