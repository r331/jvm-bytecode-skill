#!/bin/sh
# Fake agent for the self-test: copies the task's reference solution into the
# workdir and builds it. Needs ORACLE_SOLUTION_DIR, which run-evals.sh sets
# only when --oracle is passed.
set -e
: "${ORACLE_SOLUTION_DIR:?ORACLE_SOLUTION_DIR not set (run the harness with --oracle)}"
cd "${WORKDIR:?}"
(cd "$ORACLE_SOLUTION_DIR" && find . -name '*.hex' ! -type d) | while IFS= read -r f; do
  mkdir -p "$(dirname "$f")"
  cp "$ORACLE_SOLUTION_DIR/$f" "$f"
  # build like a well-behaved agent would, to exercise the .class consistency check
  if [ -f skill/build.sh ]; then sh skill/build.sh "${f%.hex}"; fi
done
