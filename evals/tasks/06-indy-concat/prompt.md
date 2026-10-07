# Task: Report

Write a JVM program using only hand-authored class file bytes in annotated hex.
Do not write Java, Kotlin, or any other source, and do not use javac, an assembler, or a generator script.

## Class

- Exactly one class, named `Report`, in the default package (no package).
- Class file major version 65 (Java 21), minor version 0.
- It must have a `public static void main(String[])` method (descriptor `([Ljava/lang/String;)V`).

## Program behavior

`java Report <name> <n1> <n2> ...`

- `<name>` is any string (it may be empty or contain spaces) and is printed as given.
- Each `<nK>` is a 32-bit signed integer accepted by `java.lang.Integer.parseInt(String)`: an optional leading `-` or `+` followed by decimal digits, within the `int` range.
  Anything else, including an empty string, `2.5`, `0x10`, a lone `-`, or a value outside the `int` range, is invalid.
- Let `count` be the number of values, `sum` their sum as a 64-bit `long` (it must not overflow for any number of `int` values that fits on a command line, e.g. three times `2147483647` gives `6442450941`), `min` and `max` the smallest and largest value, and `avg` the `double` value `(double) sum / (double) count`.
- On success print exactly two lines to stdout, print nothing to stderr, and exit with code 0:

```
Report for <name>: count=<count>, sum=<sum>, min=<min>, max=<max>, avg=<avg>
Values: [<n1>, <n2>, ...]
```

- Integers are printed in plain decimal with a leading `-` when negative.
- `avg` is printed exactly as Java's `String.valueOf(double)` / `Double.toString(double)` formats it, for example `3.0`, `-2.5`, `1.6666666666666667`, `0.1`, `9999999.0`, `1.0E7`, `2.147483647E9`.
- The `Values` line lists the parsed values in input order, normalized as integers (`+5` prints `5`, `-0` prints `0`), separated by `, ` (comma and space), inside `[` and `]`.

Example: `java Report alice 3 -1 7` prints

```
Report for alice: count=3, sum=9, min=-1, max=7, avg=3.0
Values: [3, -1, 7]
```

## String building requirement

Every string the program builds at run time must be built with `invokedynamic` call sites whose bootstrap method is `java/lang/invoke/StringConcatFactory.makeConcatWithConstants` (a `REF_invokeStatic` method handle), each with a recipe String constant in which `\u0001` marks each dynamic argument.
This includes both output lines and the invalid-number error message.

- There must be at least 2 `invokedynamic` call sites, using at least 2 different recipes.
- The `Values` line must be built by `invokedynamic` too, for example with one call site per element inside a loop.
- The class must not reference `StringBuilder`, `StringBuffer`, `StringJoiner`, `String.concat`, `String.format`, `String.valueOf`, any `toString` method, or any `print` other than `println(String)`.
  The only method references allowed in the constant pool are:
  `java/lang/Integer.parseInt:(Ljava/lang/String;)I`, `java/io/PrintStream.println:(Ljava/lang/String;)V`, `java/lang/System.exit:(I)V`, `java/lang/Object.<init>:()V`, `java/lang/String.length:()I`, `java/lang/String.charAt:(I)C`, `java/lang/Math.min:(II)I`, `java/lang/Math.max:(II)I`, and the `makeConcatWithConstants` bootstrap method itself.
  Field references (such as `System.out` and `System.err`) are not restricted.

The grader checks all of this with `javap -v -c`.

## Errors

Each error prints exactly one line to stderr, prints nothing to stdout, and exits with code 1.
Check the conditions in this order and report only the first one that applies:

| Order | Condition | stderr |
|---|---|---|
| 1 | No arguments at all | `Usage: java Report <name> <int>...` |
| 2 | A name but no values | `Error: no values` |
| 3 | Some value is not a valid `int` | `Error: invalid int: <arg>`, where `<arg>` is the first invalid value exactly as given (it may be empty) |

For example, `java Report x 1 zz 3 yy` prints `Error: invalid int: zz` and nothing to stdout.

All lines end with a single newline (`println`).

## Deliverables

- `Report.hex`: every byte of the class file, annotated.
- `Report.class`: built from the hex.
