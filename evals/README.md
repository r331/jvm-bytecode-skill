# Model evals

This directory measures whether an AI agent, given the jvm-bytecode skill, can hand-write JVM class files that work.
It is agent and model agnostic: any command line agent that can read a prompt, edit files, and run shell commands can be plugged in.
Each task is run in a skill mode and in a baseline mode, so the results show what the skill adds over the model's own knowledge.

## Cost

Each trial is a full, unattended agent run, and a run makes tasks x modes x trials of them.
The defaults (all tasks, both modes, 3 trials) mean 6 agent runs per task, each allowed up to 20 minutes.
Start with `--tasks 01-greet --trials 1 --mode skill` to check your agent command before paying for a full run.

## Running

```sh
evals/run-evals.sh --agent-cmd '<shell command>' [--tasks 01-greet,02-*] [--trials 3] [--mode both] [--timeout 1200] [--out DIR] [--keep]
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
| `--oracle` | Self-test only: exposes the reference solution to the agent. |

### The agent contract

For every trial the harness creates a fresh temporary workdir and runs `bash -c "$AGENT_CMD"` in it.
The prompt is on stdin and in the file `PROMPT.md`.
These environment variables are set: `PROMPT_FILE` and `WORKDIR` (absolute paths), `EVAL_TASK`, `EVAL_MODE`, and `EVAL_TRIAL`.
The agent must run non-interactively, write `<ClassName>.hex` files into the workdir, and exit.
It is killed, together with its whole process group, when the timeout expires.
Its stdout and stderr go to `agent.log`.

In skill mode the workdir contains `skill/SKILL.md`, `skill/references/`, and `skill/build.sh`, and the prompt starts with "Read skill/SKILL.md and follow it".
In baseline mode the workdir contains no skill files and no build script; the prompt explains the `.hex` format and tells the agent to convert hex to bytes itself if it wants to test.
Both modes get the same rules, the required class names and major version, and the task text from `prompt.md`.

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
Run real agents in a sandbox or container where they cannot read this repository, because the reference solutions live in `evals/tasks/*/solution/`.
The grader flags a `.hex` that is identical to the reference, but it cannot detect a solution that was read and then rewritten.

## Anti-cheating

The workdir has a `.shims` directory at the front of `PATH` with stub `javac`, `kotlinc`, `kotlin`, `scalac`, `scala`, `groovyc`, `groovy`, `jshell`, `jasmin`, `krakatau`, and `jar` commands that log the attempt and fail.
`java` is a wrapper that refuses the source file launcher (`java Foo.java`, `--source`) and otherwise runs the real `java`; `javap` is untouched.
A trial fails if any of these hold:

- the shim log is not empty;
- any `*.java`, `*.kt`, `*.kts`, `*.scala`, `*.groovy`, `*.clj`, `*.j`, or `*.jasm` file exists in the workdir;
- a `.class` file has no `.hex` with the same name, or its bytes differ from what `build.sh` produces from that `.hex`;
- a required `.hex` is identical to the reference solution (ignoring whitespace).

The shims only catch tools found through `PATH`; an agent that calls a compiler by absolute path, or whose shell resets `PATH`, is caught only by the file checks.

## Grading

`evals/grade.sh <workdir> <taskdir>` grades one trial and prints one JSON line.
It never uses the agent's copy of `build.sh`; it copies each required `.hex` into a clean temp dir and builds it with the repository's `build.sh`.
Then it checks that `javap -v` parses every class, that every class has the expected major version, that the task's `check.sh` (if any) passes, and that every case in `cases.txt` passes under `tests/lib/run-cases.sh`.
A trial passes only if all of these pass and the agent did not time out.
`check.sh` and the case run each have a wall-clock limit of `GRADE_TIMEOUT` seconds (default 300), so an infinite loop in a submitted class cannot hang the run.

## Reading results

Each run writes to its `--out` directory (`evals/results/` is gitignored):

| Path | Content |
|---|---|
| `results.jsonl` | One JSON line per trial. |
| `summary.md` | The summary table, also printed at the end of the run. |
| `trials/<task>/<mode>-<trial>/` | `PROMPT.md`, `agent.log`, `grade.log` (build, javap, check.sh, and case output), `result.json`, `files/` (the agent's `.hex` files), and `violations.log` if any. |

A result line looks like this:

```json
{"task":"01-greet","mode":"skill","trial":1,"pass":false,"reason":"cases failed: 7/9 passed","cases_passed":7,"cases_total":9,"duration_s":312,"timed_out":false,"agent_exit":0}
```

`reason` is `ok` on success, otherwise the first failed check, for example `shim violation: ...`, `forbidden source file: ...`, `class without hex: ...`, `class differs from build.sh output: ...`, `hex identical to reference solution: ...`, `timeout`, `missing hex: ...`, `build.sh failed: ...`, `javap failed: ...`, `wrong major: ...`, `check.sh failed`, or `cases failed: P/T passed`.
Cheating trials get `cases_passed` 0; a timed out trial still has its cases run for partial credit.

The summary has one row per task and mode with the pass rate, the mean fraction of cases passed, the mean duration, and the distinct failure reasons, plus overall rows per mode.
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

Keep the prompt independent of the mode: in baseline mode there is no skill and no `build.sh`.
Then run `evals/selftest.sh`; it checks that the oracle agent passes the new task with its reference solution in both modes.

## Self-test

`evals/selftest.sh` exercises the harness without any AI model, using the fake agents in `evals/fake-agents/`:

- `oracle.sh` copies the reference solution (exposed only with `--oracle`) and must pass every task in both modes;
- `cheater-javac.sh`, `cheater-source.sh`, and `noop.sh` must fail with the matching reason;
- inline fake agents cover a class without a hex, a tampered class, a copied reference, the timeout, a wrong major version, invalid hex, a failing `check.sh`, and wrong behavior.

It builds a throwaway two-class task in a temp dir from `tests/programs/factorial-v65`, so it does not depend on `evals/tasks/` and it writes nothing into the repository.
