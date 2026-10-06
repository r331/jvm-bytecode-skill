# Primes

Write a JVM program, using only hand-written JVM bytecode, that prints all prime numbers up to a given limit.

Requirements:

- The class must be named `Primes` (file `Primes.class`, default package).
- The class file must use major version 65 (Java 21).
- Usage: `java Primes <n>`.
- Print every prime number less than or equal to `n` on a single line, separated by single spaces, followed by a newline.
  For example, `java Primes 10` prints `2 3 5 7`.
- If there are no primes less than or equal to `n`, print an empty line.
- Find the primes by trial division using nested loops.
- `n` must be an integer between 0 and 100000 inclusive.
  If the argument is not an integer or is outside that range, print `Error: n must be an integer between 0 and 100000` to stderr and exit with code 1.
- If the number of arguments is not exactly one, print `Usage: java Primes <n>` to stderr and exit with code 1.
- On success, exit with code 0 and print nothing to stderr.
