# Greet

Write a command-line program in JVM bytecode only, as a class named `Greet` with class file major version 49.

Behavior:

- `java Greet` with no arguments prints `Hello, World!` to stdout, followed by a newline, and exits with code 0.
- `java Greet <name>` with exactly one argument prints `Hello, <name>!` to stdout, followed by a newline, and exits with code 0.
  For example, `java Greet Alice` prints `Hello, Alice!`.
  The name is printed exactly as given, including spaces and non-ASCII characters (for example `José`).
- With more than one argument, it prints `Usage: java Greet [name]` to stderr, followed by a newline, prints nothing to stdout, and exits with code 1.

Build the greeting with `java/lang/StringBuilder`; do not use `invokedynamic`.

Deliver `Greet.hex` and the `Greet.class` built from it.
