# Model evals

This directory measures whether an AI agent, given the jvm-bytecode skill, can hand-write JVM class files that work.
It is agent and model agnostic: any command line agent that can read a prompt, edit files, and run shell commands can be plugged in.
Each task is run in a skill mode and in a baseline mode, so the results show what the skill adds over the model's own knowledge.

## Cost

Each trial is a full, unattended agent run, and a run makes tasks x modes x trials of them.
The defaults (all tasks, both modes, 3 trials) mean 6 agent runs per task, each allowed up to 20 minutes.
Agent error retries (see [Agent errors](#agent-errors)) add runs, but a run that fails on credentials or rate limits usually ends within seconds or is cut short by the watchdog.
Start with `--tasks 01-greet --trials 1 --mode skill` to check your agent command before paying for a full run.

## Running

```sh
evals/run-evals.sh --agent-cmd '<shell command>' [--tasks 01-greet,02-*] [--trials 3] [--mode both] [--timeout 1200] [--out DIR] [--keep] [--isolate]
```

| Option | Meaning |
|---|---|
| `--agent-cmd CMD` | Command that runs the agent (or env `AGENT_CMD`). |
| `--tasks LIST` | Task directory names or globs, comma or space separated; default all. |
| `--tasks-dir DIR` | Alternate tasks directory; default `evals/tasks`. |
| `--trials N` | Trials per task and mode; default 3. |
| `--mode M` | `skill`, `baseline`, or `both`; default `both`. |
| `--timeout S` | Per-trial wall-clock limit in seconds; default 1200. |
| `--out DIR` | Results directory; default `evals/results/<timestamp>`. |
| `--keep` | Keep each trial workdir; its path is written to `workdir.txt` in the trial results. |
| `--agent-error-patterns FILE` | Extended regexes, one per line, that mark an agent error in `agent.log`; default `evals/agent-error-patterns.txt`. |
| `--agent-error-grace S` | Watchdog delay in seconds for killing an agent that is stuck on an agent error; default 120, `0` disables it. |
| `--retry-agent-errors N` | Rerun a trial that ended as an agent error up to N times; default 2. |
| `--fail-on-leak` | Fail trials whose `agent.log` suggests the agent read the repository; by default they are only flagged. |
| `--isolate` | Run from a temporary copy of the harness that has no reference solutions; see [Isolation](#isolation). |
| `--oracle` | Self-test only: exposes the reference solution to the agent. |

### The agent contract

For every trial the harness creates a fresh temporary workdir and runs `bash -c "$AGENT_CMD"` in it.
The prompt is on stdin and in the file `PROMPT.md`.
These environment variables are set: `PROMPT_FILE` and `WORKDIR` (absolute paths), `EVAL_TASK`, `EVAL_MODE`, `EVAL_TRIAL`, and `EVAL_ATTEMPT`.
The agent must run non-interactively, write `<ClassName>.hex` files into the workdir, and exit.
It is killed, together with its whole process group, when the timeout expires.
Its stdout and stderr go to `agent.log`.

In skill mode the workdir contains `skill/SKILL.md`, `skill/references/`, and `skill/build.sh`, and the prompt starts with "Read skill/SKILL.md and follow it".
In baseline mode the workdir contains no skill files and no build script; the prompt explains the `.hex` format and tells the agent to convert hex to bytes itself if it wants to test.
Both modes get the same rules, the required class names and major version, and the task text from `prompt.md`.
If the task has an `inputs/` directory, its contents are copied into the workdir root before the agent starts, and the prompt lists them as read-only input files.

### Example agent commands

These are generic shapes; check your agent's documentation for the exact non-interactive and auto-approve flags.

```sh
# agent that takes the prompt as an argument
AGENT_CMD='some-agent -p "$(cat PROMPT.md)" --yes'

# agent that reads the prompt from stdin
AGENT_CMD='some-agent exec --full-auto -'

# agent that takes a prompt file
AGENT_CMD='some-agent run --non-interactive --prompt-file "$PROMPT_FILE"'

# pick a model through the agent's own flag
AGENT_CMD='some-agent -p "$(cat PROMPT.md)" --model some-model --yes'
```

Make sure the agent is allowed to run shell commands and edit files in its working directory without asking for approval, or it will stall until the timeout.

Prefer an output format that writes the full transcript, including every tool call, to stdout.
With plain text output `agent.log` holds only the agent's final message, so you cannot audit what it ran, the leak check below sees almost nothing, and the agent error watchdog cannot tell a silently working agent from a stuck one.
For Claude Code, for example:

```sh
AGENT_CMD='claude -p --output-format stream-json --verbose --disable-slash-commands --no-session-persistence --permission-mode acceptEdits --allowedTools "Bash Read Write Edit Glob Grep"'
```

The harness feeds `PROMPT.md` on stdin, which `claude -p` reads when no prompt argument is given.
`--output-format stream-json` requires `--verbose` in print mode; each line of `agent.log` is then one JSON event (messages, tool calls, and tool results).

### Isolation

The reference solutions live in `evals/tasks/*/solution/`, so run real agents where they cannot read this repository.
The strongest setup is a container or a separate user that has no access to the repository.
At a minimum pass `--isolate`: the harness copies `SKILL.md`, `references/`, `build.sh`, `tests/lib/run-cases.sh`, the eval scripts, and only the `prompt.md`, `expect`, `cases.txt`, `check.sh`, `stdin/`, and `inputs/` of the selected tasks into a temp dir, and runs from there; `solution/` and any other maintainer files stay behind.
Trial workdirs are separate temp dirs either way, and the harness sets no variable that points into the repository (it unsets `OLDPWD`, and sets `ORACLE_SOLUTION_DIR` only with `--oracle`); an agent command or `PATH` of your own that points into the repository is not changed.
Only the grader reads the real solutions, for the "identical to reference" check.
`--isolate` does not stop an agent that runs as your user from finding the repository on disk; it only removes the harness's pointers to it, and the leak check flags an agent that goes there anyway.
The grader flags a `.hex` that is identical to the reference, but it cannot detect a solution that was read and then rewritten.

### Agent errors

A trial is an agent error, an infrastructure failure rather than a model result, when the agent produced no files in the workdir and at least one of these holds:

- the agent exited non-zero;
- the agent timed out;
- `agent.log` matches a pattern in the agent error pattern file (credential, authentication, rate limit, quota, network, and `command not found` errors).

"Produced no files" means no file in the workdir is new or changed compared to just before the agent started, so the prompt, the shims, the skill files, and unchanged inputs do not count, while a shim violation does.
An agent error gets `"agent_error":true` and the reason `agent error: <first matching log line>`, `agent error: timeout with no files`, or `agent error: exit N with no files`; nothing else is graded.
It is rerun up to `--retry-agent-errors` times, after waiting 30s and then 90s (later retries reuse the last value; env `EVAL_RETRY_BACKOFF="30 90"` overrides the list).
Earlier attempts are kept in `attempt-1/`, `attempt-2/`, and so on inside the trial directory; only the last attempt is written to `results.jsonl`.

The watchdog kills an agent that is stuck on an agent error instead of waiting for the full timeout.
Once, `--agent-error-grace` seconds after the start, it checks that the agent has produced no files, that `agent.log` matches an agent error pattern, and that `agent.log` has not changed for half the grace period.
If all three hold, the agent is killed, and the trial gets `"early_abort":true` and `agent_exit` 125.
With a transcript output format a working agent keeps writing to `agent.log`, so it is not killed even if it logged a transient credential warning first.
With plain text output an agent that logged such a warning and then works silently for the whole grace period before writing its first file is killed and retried; raise the grace period or set it to 0 if that happens.

Keep the patterns specific: with a transcript output format, the output of the agent's own commands lands in `agent.log` too.
The patterns only matter when the agent produced no files, so a false match on a trial with output has no effect.

### Leak check

The grader records `"leak_suspect":true` when `agent.log` contains the absolute path of the repository (or of the `--isolate` copy), `evals/tasks`, `solution/`, or `.claude/skills`.
This is a heuristic for an agent that went looking for the reference solutions or for an installed copy of the skill; it is only useful with a transcript output format, and a model that writes "solution/" in prose also trips it.
By default a leak suspect still passes or fails on its merits, and the summary counts leak suspects so you can read their transcripts.
With `--fail-on-leak` it fails with the reason `possible leak: <matched text>`.

## Anti-cheating

The workdir has a `.shims` directory at the front of `PATH` with stub `javac`, `kotlinc`, `kotlin`, `scalac`, `scala`, `groovyc`, `groovy`, `jshell`, `jasmin`, `krakatau`, and `jar` commands that log the attempt and fail.
`java` is a wrapper that refuses the source file launcher (`java Foo.java`, `--source`) and otherwise runs the real `java`; `javap` is untouched.
A trial fails if any of these hold:

- the shim log is not empty;
- a task input file was modified in the workdir (reason `modified input file: ...`);
- any `*.java`, `*.kt`, `*.kts`, `*.scala`, `*.groovy`, `*.clj`, `*.j`, or `*.jasm` file exists in the workdir;
- a `.class` file has no `.hex` with the same name, or its bytes differ from what `build.sh` produces from that `.hex`;
- a required `.hex` is identical to the reference solution (ignoring whitespace);
- with `--fail-on-leak`, `agent.log` looks like a leak (see [Leak check](#leak-check)).

Files that came from the task's `inputs/` and are byte-identical at the end are exempt from the source file and `.class` checks, so an input `.class` without a `.hex` is fine.
Deleting an input is not a failure; the grader always uses the original inputs.

The shims only catch tools found through `PATH`; an agent that calls a compiler by absolute path, or whose shell resets `PATH`, is caught only by the file checks.

## Grading

`evals/grade.sh <workdir> <taskdir>` grades one trial and prints one JSON line.
It never uses the agent's copy of `build.sh`; it copies each required `.hex` into a clean temp dir and builds it with the repository's `build.sh`.
The task's original `inputs/` files are copied next to the rebuilt classes, so deliverables can use input classes at run time.
Then it checks that `javap -v` parses every class, that every class has the expected major version, that the task's `check.sh` (if any) passes, and that every case in `cases.txt` passes under `tests/lib/run-cases.sh`.
A trial passes only if all of these pass, the agent did not time out, and it is not an agent error.
`check.sh` and the case run each have a wall-clock limit of `GRADE_TIMEOUT` seconds (default 300), so an infinite loop in a submitted class cannot hang the run.

## Reading results

Each run writes to its `--out` directory (`evals/results/` is gitignored):

| Path | Content |
|---|---|
| `results.jsonl` | One JSON line per trial. |
| `summary.md` | The summary table, also printed at the end of the run. |
| `trials/<task>/<mode>-<trial>/` | `PROMPT.md`, `agent.log`, `grade.log` (build, javap, check.sh, and case output), `result.json`, `files/` (the `.hex` files the agent wrote), `violations.log` if any, and `attempt-N/` for each earlier attempt that ended as an agent error. |

A result line looks like this:

```json
{"task":"01-greet","mode":"skill","trial":1,"pass":false,"reason":"cases failed: 7/9 passed","cases_passed":7,"cases_total":9,"duration_s":312,"timed_out":false,"agent_exit":0,"agent_error":false,"early_abort":false,"leak_suspect":false,"attempts":1}
```

`attempts` is the number of times the trial was run; it is above 1 only after agent error retries.
Lines written before `agent_error`, `early_abort`, `leak_suspect`, and `attempts` existed are still accepted by `summarize.sh`, which treats the missing flags as false.

`reason` is `ok` on success, otherwise the first failed check, for example `agent error: ...`, `shim violation: ...`, `modified input file: ...`, `forbidden source file: ...`, `class without hex: ...`, `class differs from build.sh output: ...`, `hex identical to reference solution: ...`, `possible leak: ...`, `timeout`, `missing hex: ...`, `build.sh failed: ...`, `javap failed: ...`, `wrong major: ...`, `check.sh failed`, or `cases failed: P/T passed`.
Cheating trials get `cases_passed` 0; a timed out trial still has its cases run for partial credit.

The summary has one row per task and mode with the number of trials, agent errors, and leak suspects, the pass rate, the mean fraction of cases passed, the mean duration, and the distinct failure reasons, plus overall rows per mode.
Agent errors are excluded from the pass rate, the case pass fraction, the duration, the failure reasons, and the deltas, so an infrastructure outage does not count against the model; a row with only agent errors shows `n/a`.
The "Skill vs baseline" table shows, per task and overall, the skill pass rate minus the baseline pass rate and the same for the case pass fraction, in percentage points.
With only a few trials per task the numbers are noisy; look at the failure reasons and the agent's `.hex` files before drawing conclusions.
`evals/summarize.sh <results.jsonl>` regenerates the summary, which also lets you concatenate results of several runs first.

## Adding a task

Create `evals/tasks/<NN-name>/` with:

| File | Content |
|---|---|
| `prompt.md` | The task text for the agent: class name(s), major version, exact behavior including output text and exit codes. |
| `cases.txt` | Test cases in the format documented at the top of `tests/lib/run-cases.sh`. |
| `expect` | `class: <MainClass>`, `major: <N>`, and optionally `files: A B C` listing every class that must be produced. |
| `solution/` | A reference hand-written `<Class>.hex` for every required class. It is never copied into the agent's workdir. |
| `check.sh` | Optional. Run as `check.sh <class-dir>` on the rebuilt classes; a non-zero exit fails the trial, for example to assert that required members exist or that a `tableswitch` is used. |
| `stdin/` | Optional. `<line-number>.in` files fed as stdin to the case on that line of `cases.txt`. |
| `inputs/` | Optional. Files copied into the workdir root before the agent starts, for example a prebuilt `.class` the program must call, or a data file. The agent must not modify them, and the grader puts the original files next to the rebuilt classes. Deliverables are always new `.hex` files, so do not give an input the name of a required class. |

Keep the prompt independent of the mode: in baseline mode there is no skill and no `build.sh`.
`tests/run.sh` does not put the task's `inputs/` on the class path when it runs the reference solution, so a solution that loads an input class at run time fails there.
Then run `evals/selftest.sh`; it checks that the oracle agent passes the new task with its reference solution in both modes.

## Self-test

`evals/selftest.sh` exercises the harness without any AI model, using the fake agents in `evals/fake-agents/`:

- `oracle.sh` copies the reference solution (exposed only with `--oracle`) and must pass every task in both modes;
- `cheater-javac.sh`, `cheater-source.sh`, and `noop.sh` must fail with the matching reason;
- inline fake agents cover a class without a hex, a tampered class, a copied reference, the timeout, a wrong major version, invalid hex, a failing `check.sh`, and wrong behavior;
- `agent-error.sh` (credential error, exit 1, no files) must be an agent error and be retried, with fast backoff through `EVAL_RETRY_BACKOFF`;
- `hang-error.sh` (credential error, then a hang) must be killed early by the watchdog, while an agent that logs the same error and keeps working, or that writes files, is graded normally;
- `leaker.sh` (reads a file from the repository's `evals/tasks`, then copies the reference solution) must be a leak suspect that passes by default and fails with `--fail-on-leak`;
- an inputs task must pass when the oracle leaves its input `.class` and `.java` files untouched, and fail when an agent modifies one;
- `--isolate` runs must pass with the oracle, still detect a copied reference, and leave no pointer to the repository in the agent's workdir or environment;
- `summarize.sh` must exclude agent errors, count leak suspects, and read old result lines without the new fields.

It builds throwaway tasks in a temp dir from `tests/programs/factorial-v65`, so it does not depend on `evals/tasks/` and it writes nothing into the repository.
