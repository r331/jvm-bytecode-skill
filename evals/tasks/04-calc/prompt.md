# Task: Calc

Write a JVM program using only hand-authored class file bytes in annotated hex.
Do not write Java, Kotlin, or any other source, and do not use javac, an assembler, or a generator script.

## Class

- Exactly one class, named `Calc`, in the default package (no package).
- Class file major version 61 (Java 17), minor version 0.
- It must have a `public static void main(String[])` method (descriptor `([Ljava/lang/String;)V`).

## Program behavior

`java Calc <a> <op> <b>`

- `a` and `b` are signed 64-bit integers (`long`) in decimal: an optional leading `-` or `+` followed by one or more digits, within the range of a `long`.
  Anything else, including an empty string, a decimal point, or a value outside the `long` range, is not a valid number.
- `op` is one of these single-character operators:

| `op` | Result |
|---|---|
| `+` | `a + b` |
| `-` | `a - b` |
| `x` | `a * b` (the letter `x`, so the shell does not expand `*`) |
| `/` | `a / b`, truncated toward zero |
| `%` | remainder of `a / b`, with the sign of `a` |

- All arithmetic is 64-bit two's complement and wraps silently on overflow, exactly like the JVM's `long` instructions.
  For example, `9223372036854775807 + 1` prints `-9223372036854775808`, and `-9223372036854775808 / -1` prints `-9223372036854775808` (no error).
- On success, print the result in decimal on its own line to stdout, print nothing to stderr, and exit with code 0.

## Dispatch requirement

`main` must select the operation with a `tableswitch` or `lookupswitch` instruction on the first character of `op`.
The grader checks this with `javap -c`; a chain of `if` comparisons alone does not pass.

## Errors

Each error prints exactly one line to stderr, prints nothing to stdout, and exits with the given code.
Check the conditions in this order and report only the first one that applies:

| Order | Condition | stderr | Exit code |
|---|---|---|---|
| 1 | Number of arguments is not exactly 3 | `Usage: java Calc <a> <op> <b>` | 1 |
| 2 | `a` or `b` is not a valid number | `Error: invalid number` | 1 |
| 3 | `op` is not exactly one of the five single characters above (this includes multi-character arguments such as `++` or `xx`, and `X`) | `Error: unknown operator <op>`, where `<op>` is the argument exactly as given | 2 |
| 4 | `op` is `/` or `%` and `b` is 0 | `Error: division by zero` | 3 |

For example, `java Calc abc ^ 0` prints `Error: invalid number` (exit 1), and `java Calc 1 ++ 2` prints `Error: unknown operator ++` (exit 2).

All lines end with a single newline (`println`).

## Deliverables

- `Calc.hex`: every byte of the class file, annotated.
- `Calc.class`: built from the hex.
