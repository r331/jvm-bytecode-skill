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
| `build.sh` | Strips comments from a `.hex` file, validates it, and writes the `.class` file. |

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
```

`build.sh` fails if the hex contains non-hex characters outside comments or an odd number of digits, because `xxd -r -p` would otherwise silently skip or shift bytes.

## Requirements

- A JDK (`java`, `javap`); the highest supported class file major version is the Java feature release + 44.
- `xxd`, `sed`, `grep`, `tr`, `wc` (preinstalled on macOS and most Linux distributions).

## Verification status

The workflow has been tested end to end on Java 21 with two hand-written programs:

- A hypotenuse calculator at major 49 (no stack map frames) and major 52 (with frames).
- A factorial calculator at major 65 using a loop, `long` locals, an exception handler, and append, chop, and full frames.

## License

[MIT](LICENSE)
