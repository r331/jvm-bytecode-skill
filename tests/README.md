# Deterministic tests

These tests check the skill's reference material and example programs without any AI model.
They need only bash, the standard macOS/Linux command line tools, `xxd`, and a JDK (21 or newer) on `PATH`.

## Running

Run `tests/run.sh` from any directory.
It prints one `PASS` or `FAIL` line per check, a summary, and exits non-zero if anything failed.
Each `java` invocation is killed after 20 seconds; set `TEST_TIMEOUT=<seconds>` to change that.
Everything is built in temporary directories, so no `.class` files are left in the repository.

## What runs

- `tests/programs/*/`: each hand-written program is built with `build.sh`, parsed with `javap -v`, checked against its `expect` file, and run against its `cases.txt`.
- `evals/tasks/*/solution/`: the reference solution of every eval task is checked the same way, using `cases.txt`, `expect`, `stdin/`, and `check.sh` from the task directory.
- `tests/build/test-build.sh`: `build.sh` rejects non-hex characters and odd digit counts, ignores comments, and writes exactly the expected bytes.
- `tests/docs/test-docs.sh`: the StackMapTable bytes of "Worked example 1" and "Worked example 2" in `references/verification.md` appear in the built `hypotenuse-v52` and `factorial-v65` classes, and every relative markdown link resolves.
- `tests/opcodes/test-opcodes.sh`: the opcode tables in `references/instructions.md` are complete, and `javap -c` decodes `tests/opcodes/Opcodes.hex` (201 opcodes, both switches at all four paddings, every `wide` form) to the documented mnemonics.

Each suite can also be run on its own, for example `bash tests/opcodes/test-opcodes.sh`.

## Adding a program

1. Create `tests/programs/<name>/` containing the class files as `<ClassName>.hex`.
2. Add `cases.txt` in the format documented at the top of `tests/lib/run-cases.sh` (TAB-separated args, exit code, stdout, stderr).
3. Add an `expect` file with `major: <N>`, plus `class: <MainClass>` if there is more than one `.hex` file.
4. Optionally add `files: A B C` to `expect` to limit the major version check to those classes, and a `stdin/<line>.in` file for any case that reads stdin.
5. Run `tests/run.sh` and confirm the new program's lines are all `PASS`.

If a program's bytes are quoted in a reference file, add a matching `check_example` line to `tests/docs/test-docs.sh` so the two cannot drift apart.
