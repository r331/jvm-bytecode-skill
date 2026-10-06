# jvm-bytecode

An AI agent skill for writing JVM programs directly as hand-authored class file bytes.
No Java, Kotlin, Scala, or any other source language, and no assembler or bytecode library.
The program is an annotated hex file that is converted byte for byte into a `.class` file.

The reference material is condensed from The Java Virtual Machine Specification, Java SE 25 Edition.

## Contents

| Path | Purpose |
|---|---|
| `SKILL.md` | Skill entry point: rules, workflow, version choice, common patterns, pitfalls. |
| `references/class-file.md` | ClassFile layout, versions, constant pool, descriptors, access flags, attributes, limits. |
| `references/instructions.md` | Every opcode with hex value, operand bytes, and stack effect. |
| `references/verification.md` | StackMapTable encoding, where frames are required, code constraints, verifier error guide. |
| `build.sh` | Strips comments from `.hex` files, validates them, and writes the `.class` files. |
| `tests/` | Deterministic test suite: known-good programs, `build.sh` tests, doc drift checks, opcode table checks. |
| `evals/` | Model-agnostic eval harness and tasks that measure how well an agent writes bytecode with and without the skill. |

## Installation

The skill is plain Markdown and works with any model or agent that can read files and run shell commands.
`SKILL.md` has a YAML front matter block (`name`, `description`) used by agents that support skill discovery.

- **Agents with skill support:** place or link this directory into the agent's skills directory, for example:
  ```sh
  git clone https://github.com/r331/jvm-bytecode-skill.git <agent-skills-dir>/jvm-bytecode
  ```
  The agent picks the skill when a request matches the `description`, such as "write this only in JVM bytecode".
- **Any other model:** include `SKILL.md` in the prompt or system instructions, and give the model access to the `references/` files and `build.sh`.

## Hex file format

Each line holds hex bytes, optionally followed by a `#` comment that runs to the end of the line.
Whitespace and comments are ignored, so bytes can be grouped one logical item per line:

```
CA FE BA BE                     # magic
00 00 00 31                     # minor 0, major 49
```

## Building and running

```sh
./build.sh Hypotenuse                 # Hypotenuse.hex -> Hypotenuse.class
javap -v -p -c Hypotenuse.class       # inspect the structure
java -cp . Hypotenuse 3 4             # run it; loading also runs the verifier

./build.sh -d out Shape Circle Main   # several classes into one classpath dir
java -cp out Main
```

`build.sh` fails on non-hex characters outside comments, an odd number of digits, an empty file, or a wrong magic number, because `xxd -r -p` would otherwise silently skip or shift bytes.
When a build fails it also deletes the stale `.class`, so an old build is never run by mistake.

## Requirements

- A JDK (`java`, `javap`); the highest supported class file major version is the Java feature release + 44.
- `xxd`, `sed`, `grep`, `tr`, `wc` (preinstalled on macOS and most Linux distributions).

## Testing

```sh
tests/run.sh        # deterministic suite, no model needed (about 40 seconds)
evals/selftest.sh   # checks the eval harness itself with fake agents
evals/run-evals.sh --agent-cmd '<your agent command>' --trials 3   # real model evals
```

`tests/run.sh` builds and runs every hand-written program in `tests/programs/` and every eval reference solution, checks `build.sh`, checks that the worked examples in `references/verification.md` match verified bytes, and checks every opcode in `references/instructions.md` against `javap`.
See [tests/README.md](tests/README.md).

`evals/run-evals.sh` gives each task to an agent in a fresh directory, with the skill and without it, blocks compilers and assemblers, and grades the result by rebuilding and running it.
The pass-rate difference between the two modes is the measured value of the skill.
Each trial is a full agent run, so real evals cost model usage.
See [evals/README.md](evals/README.md).

All hand-written programs and reference solutions are verified on Java 21:

| Program | Major | Covers |
|---|---|---|
| `tests/programs/hypotenuse-v49` | 49 | type-inference verifier, exception handler |
| `tests/programs/hypotenuse-v52` | 52 | StackMapTable with same and same_locals_1_stack_item frames |
| `tests/programs/factorial-v65` | 65 | loop, `long` locals, append, chop, and full frames |
| `evals/tasks/01-greet` | 49 | StringBuilder, optional argument, non-ASCII output |
| `evals/tasks/02-primes` | 65 | nested loops, 11 stack map frames |
| `evals/tasks/03-counter` | 52 | fields, constructor, instance methods, `toString` |
| `evals/tasks/04-calc` | 61 | `lookupswitch`, `long` arithmetic, error dispatch |
| `evals/tasks/05-shapes` | 55 | interface, two implementations, `invokeinterface`, arrays |

## License

[MIT](LICENSE)
