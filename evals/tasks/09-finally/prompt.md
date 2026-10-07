# Task: Steps

Write a JVM program using only hand-authored class file bytes in annotated hex.
Do not write Java, Kotlin, or any other source, and do not use javac, an assembler, or a generator script.

## Class

- Exactly one class, named `Steps`, in the default package (no package).
- Class file major version 65 (Java 21), minor version 0.
- It must have a `public static void main(String[])` method (descriptor `([Ljava/lang/String;)V`).
  You may add other static methods.

## Program behavior

`java Steps <step>...`

If there are no arguments, print `Usage: java Steps <step>...` to stderr, print nothing to stdout, and exit with code 1.

Otherwise process the arguments as steps, numbered from 1 in argument order, then exit with code 0.
Nothing is ever printed to stderr in this case, and no exception may escape `main`.
Each step is exactly one of these lowercase words (comparison is exact and case-sensitive):

| Step | What running it does |
|---|---|
| `ok` | nothing |
| `fail` | throws `new IllegalStateException("step " + i + " failed")`, where `i` is the step number |
| `npe` | throws a `NullPointerException` by actually invoking an instance method on a `null` reference |
| `div` | throws an `ArithmeticException` by an `int` division (or remainder) by zero |
| `exit` | returns immediately from the processing method (see below) |
| anything else, including an empty argument | throws `new IllegalArgumentException("unknown step: " + s)`, where `s` is the argument |

The processing must have exactly the structure of this pseudocode, with real nested `try`/`catch`/`finally` semantics:

```
process(steps):
  try {                                              // outer try
    for i = 1 .. steps.length:
      try {                                          // inner try
        run step i (table above)                     // may throw, or return from process for exit
        println("step " + i + " ok")
      } catch (IllegalStateException e) {
        println("caught: " + e.getMessage())
      } finally {
        println("cleanup " + i)
      }
  } catch (RuntimeException e) {
    println("outer: " + e.getClass().getSimpleName())
  } finally {
    println("done")
  }
```

All `println` calls write one line to stdout ending with a single newline.
Consequences of these semantics, all of which must hold:

- A `fail` step is handled by the inner catch; processing continues with the next step.
- An `npe`, `div`, or unknown step is not caught by the inner catch: its `cleanup i` line is printed, then the outer catch prints `outer: NullPointerException`, `outer: ArithmeticException`, or `outer: IllegalArgumentException`, then `done`; no later steps run.
- An `exit` step returns from inside the inner try, so both finally blocks still run: `cleanup i`, then `done`; no later steps run and `step i ok` is not printed.
- After the last step completes normally, `done` is printed.

For example, `java Steps ok fail exit ok` prints:

```
step 1 ok
cleanup 1
caught: step 2 failed
cleanup 2
cleanup 3
done
```

and `java Steps fail npe ok` prints:

```
caught: step 1 failed
cleanup 1
cleanup 2
outer: NullPointerException
done
```

## Bytecode requirements

The grader inspects the class with `javap -v` and fails it unless all of these hold:

- Both catch clauses and both finally blocks are implemented with real exception table entries: typed entries for `java/lang/IllegalStateException` and `java/lang/RuntimeException`, and catch-all entries (type `any`, `catch_type` 0) for each `finally`.
  In total there must be at least 4 exception table entries, at least 2 of them of type `any`.
- Each `finally` body is duplicated on every path that leaves its `try` (normal completion, each catch clause, the `exit` return, and the exceptional path), and the catch-all handler saves the exception, runs the finally code, and rethrows it with `athrow`.
- No `jsr`, `jsr_w`, or `ret` instructions (they are illegal in this class file version anyway).
- `NullPointerException` and `ArithmeticException` are raised by the JVM itself: no `new` of either class anywhere.

## Deliverables

- `Steps.hex`: every byte of the class file, annotated.
- `Steps.class`: built from the hex.
