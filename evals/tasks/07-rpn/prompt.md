# Task: Rpn

Write a JVM program using only hand-authored class file bytes in annotated hex.
Do not write Java, Kotlin, or any other source, and do not use javac, an assembler, or a generator script.

## Class

- Exactly one class, named `Rpn`, in the default package (no package).
- Class file major version 65 (Java 21), minor version 0.
- It must have a `public static void main(String[])` method (descriptor `([Ljava/lang/String;)V`).
- All logic lives in static methods: besides `main` there must be at least 3 other static methods (for example one to evaluate a token, one to read a number, one to apply an operator).

## Program behavior

`java Rpn "<expression>"`

The program takes exactly one argument, a Reverse Polish Notation expression, evaluates it over `double` values, and prints the result.

### Tokens

- Tokens are separated by one or more space characters (`' '`, U+0020).
  Leading and trailing spaces are allowed and ignored.
  No other character is a separator.
- Tokens are processed strictly from left to right, each one executed as soon as it is read.
  The first error stops the program; tokens after it are never examined.
- A token is exactly one of the following (matching is case-sensitive):

| Token | Effect |
|---|---|
| `+` `-` `*` `/` | pop `b`, pop `a`, push `a + b`, `a - b`, `a * b`, `a / b` |
| `^` | pop `b`, pop `a`, push `Math.pow(a, b)` |
| `sqrt` | pop `a`, push `Math.sqrt(a)` |
| `neg` | pop `a`, push `-a` (negation, so `0 neg` is `-0.0`) |
| `dup` | push a copy of the top value |
| `swap` | exchange the top two values |
| a number | push its value |

- Any other token whose first character is a digit `0`-`9`, `-`, or `.` is a number token.
  Every other token is an unknown token.

### Numbers

- A number token must match `-?[0-9]+(\.[0-9]+)?`: an optional leading `-`, one or more digits, and optionally a `.` followed by one or more digits.
  Anything else, such as `1.2.3`, `5.`, `.5`, `-.5`, `--5`, `1e5`, or `-x`, is an invalid number.
- Numbers must be parsed by hand, character by character.
  The class must not use `Double.parseDouble`, `Double.valueOf(String)`, `Integer.parseInt`, `Long.parseLong`, `Integer.decode`, any other `parse*` or `valueOf(String)` method, `Scanner`, `String.split`, `StringTokenizer`, regular expressions, `java/util`, `java/text`, or `java/math` classes, reflection, or `javax/script`.
- Value: accumulate all digits (integer and fraction part, without the `.`) left to right as a `double` with `v = v * 10.0 + digit`, divide by `10.0` raised to the number of fraction digits (computed by repeated multiplication by `10.0`), then negate it if there is a leading `-` (so `-0` is `-0.0`).
  For example `007.250` is `7.25` and `0.1` is the same `double` as the Java literal `0.1`.

### Stack

- The operand stack is a fixed-size `double[]` of capacity 64 that the program manages itself (no collections).
- Pushing when it already holds 64 values is a stack overflow; popping from an empty stack is a stack underflow.
- An operator or function first checks that enough values are on the stack (2 for `+ - * / ^ swap`, 1 for `sqrt neg dup`), then, for `dup`, that there is room.
- A number token is validated first; only a valid number can cause a stack overflow.

### Output

- After the last token, exactly one value must remain on the stack.
  Print it to stdout with `println`, formatted exactly as Java's `String.valueOf(double)` / `Double.toString(double)`, for example `7.0`, `-6.0`, `0.30000000000000004`, `1.0E-4`, `1.2345678E10`, `Infinity`, `NaN`, `-0.0`.
  Print nothing to stderr and exit with code 0.
- Division by zero and `sqrt` of a negative number are not errors; they follow IEEE 754 (`1 0 /` prints `Infinity`, `0 0 /` prints `NaN`).

Examples:

| Command | stdout |
|---|---|
| `java Rpn "3 4 +"` | `7.0` |
| `java Rpn "5 1 2 + 4 * + 3 -"` | `14.0` |
| `java Rpn "2 0.5 ^"` | `1.4142135623730951` |
| `java Rpn "10 4 swap -"` | `-6.0` |

## Errors

Each error prints exactly one line to stderr, prints nothing to stdout, and exits with code 1.

| Condition | stderr |
|---|---|
| Number of arguments is not exactly 1 | `Usage: java Rpn "<expression>"` (the double quotes are part of the message) |
| Not enough values for an operator or function | `Error: stack underflow` |
| Pushing onto a full stack (a number or `dup`) | `Error: stack overflow` |
| A token that is neither an operator, a function, nor a number token | `Error: unknown token <tok>` |
| A number token that is not a valid number | `Error: invalid number <tok>` |
| After all tokens, the stack does not hold exactly one value (including an empty or all-space expression) | `Error: expected one result, got <k>`, where `<k>` is the number of values left, in decimal |

`<tok>` is the token exactly as written.
For example, `java Rpn "+ foo"` prints `Error: stack underflow`, `java Rpn "foo +"` prints `Error: unknown token foo`, `java Rpn "+5"` prints `Error: unknown token +5`, and `java Rpn "1 2"` prints `Error: expected one result, got 2`.

All lines end with a single newline (`println`).

## Structure requirements

The grader checks with `javap -v -p -c` that:

- there are at least 3 static methods besides `main`;
- the StackMapTable attributes of all methods have at least 20 entries in total;
- the class allocates the stack with a `newarray double` instruction and references `java/lang/Math.pow:(DD)D`;
- the constant pool contains none of the forbidden parsing or tokenizing references listed above.

## Deliverables

- `Rpn.hex`: every byte of the class file, annotated.
- `Rpn.class`: built from the hex.
