# Task: Counter

Write a JVM program using only hand-authored class file bytes in annotated hex.
Do not write Java, Kotlin, or any other source, and do not use javac, an assembler, or a generator script.

## Class

- Exactly one class, named `Counter`, in the default package (no package).
- Class file major version 52 (Java 8), minor version 0.
- Access: `public` class (ACC_PUBLIC | ACC_SUPER), superclass `java/lang/Object`, no interfaces.

## Required members

The grader inspects the class with `javap -p`, so names, descriptors, and access flags must match exactly.

| Member | Name | Descriptor | Access |
|---|---|---|---|
| field | `count` | `I` | `private` |
| field | `name` | `Ljava/lang/String;` | `private final` |
| constructor | `<init>` | `(Ljava/lang/String;)V` | `public` |
| method | `increment` | `()V` | `public` |
| method | `get` | `()I` | `public` |
| method | `toString` | `()Ljava/lang/String;` | `public` |
| method | `main` | `([Ljava/lang/String;)V` | `public static` |

Behavior of the members:

- `Counter(String)` calls `java/lang/Object.<init>()V`, stores its argument in `name`, and leaves `count` at 0.
- `increment()` adds 1 to `count`.
- `get()` returns `count`.
- `toString()` returns `name`, then `=`, then `count` in decimal, e.g. `apples=3`.

## Program behavior

`java Counter <name> [inc|get|show]...`

- With no arguments: print `Usage: java Counter <name> [inc|get|show]...` to stderr and exit with code 1.
- Otherwise `main` must create the object with `new Counter(args[0])` (a real instance; do not reimplement the logic statically) and then process the remaining arguments left to right, calling the instance methods:
  - `inc`: call `increment()`; prints nothing.
  - `get`: print the value of `get()` on its own line to stdout.
  - `show`: print the result of `toString()` on its own line to stdout.
  - anything else (matched exactly and case-sensitively): print `Unknown command: <cmd>` to stderr, where `<cmd>` is the argument as given, and exit with code 2 immediately; output from earlier commands stays printed and later arguments are not processed.
- When all arguments are processed, exit with code 0.
  With only a name and no commands, nothing is printed.

All lines end with a single newline (`println`).

## Deliverables

- `Counter.hex`: every byte of the class file, annotated.
- `Counter.class`: built from the hex.
