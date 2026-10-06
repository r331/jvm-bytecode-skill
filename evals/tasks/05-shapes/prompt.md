# Task: shapes with an interface

Using only hand-written JVM bytecode, write a program made of four classes that build and print a list of shapes.
All four class files must use major version 55 (Java 11), minor version 0.
All classes are in the default (unnamed) package.

## Classes

### `Shape` (interface)

- A public interface: `ACC_PUBLIC | ACC_INTERFACE | ACC_ABSTRACT`, super class `java/lang/Object`.
- Two public abstract methods, with no code:
  - `area` with descriptor `()D`
  - `name` with descriptor `()Ljava/lang/String;`

### `Circle implements Shape`

- A public class whose super class is `java/lang/Object` and which lists `Shape` in its interfaces.
- A public constructor `<init>` with descriptor `(D)V` that takes the radius.
- `area()D` returns `Math.PI * size * size`, evaluated left to right as `(Math.PI * size) * size`, where `size` is the constructor argument and `Math.PI` is 3.141592653589793.
- `name()Ljava/lang/String;` returns `"circle"`.

### `Square implements Shape`

- A public class whose super class is `java/lang/Object` and which lists `Shape` in its interfaces.
- A public constructor `<init>` with descriptor `(D)V` that takes the side length.
- `area()D` returns `size * size`.
- `name()Ljava/lang/String;` returns `"square"`.

### `Shapes` (main class)

- A public class with `public static void main(String[])` (descriptor `([Ljava/lang/String;)V`).
- It calls `area` and `name` through the interface: `invokeinterface` on `InterfaceMethodref` entries for `Shape.area:()D` and `Shape.name:()Ljava/lang/String;`.

## Behavior

Run as `java Shapes <kind> <size> [<kind> <size> ...]`, for example `java Shapes circle 1 square 2`.

1. If the number of arguments is zero or odd, print `Usage: java Shapes (circle|square) <size> ...` to stderr and exit with code 1.
2. Otherwise create a `Shape[]` array with one element per kind/size pair.
   Process the pairs from left to right; for each pair, validate the kind first, then the size:
   - The kind must be exactly `circle` or `square` (case-sensitive, compared with `String.equals`).
     Otherwise print `Unknown shape: <kind>` to stderr and exit with code 2.
   - The size is parsed with `Double.parseDouble(String)`.
     If that throws `NumberFormatException`, or the parsed value is not greater than 0 (this includes `0`, `-0.0`, negative values, and `NaN`), print `Invalid size: <arg>` to stderr, where `<arg>` is the original argument text, and exit with code 1.
     `Infinity` parses successfully and is greater than 0, so it is a valid size.
   - Store a new `Circle(size)` or `Square(size)` in the array.
   The first invalid pair stops the program; nothing is printed to stdout when any argument is invalid.
3. After all pairs are stored, go through the array in order and for each shape print one line to stdout: the result of `name()`, a single space, and the result of `area()` formatted as `String.valueOf(double)` would format it (for example `circle 3.141592653589793`, `square 4.0`, `square 1.0E8`).
4. Finally print `total <sum>` to stdout, where `<sum>` is the sum of the areas added in array order starting from `0.0`, formatted the same way, and exit with code 0.

Every output line ends with a single `\n`.
Error messages go to stderr only, with nothing on stdout.

## Examples

```
$ java Shapes circle 1 square 2
circle 3.141592653589793
square 4.0
total 7.141592653589793

$ java Shapes triangle 1        # stderr: Unknown shape: triangle   exit 2
$ java Shapes circle abc        # stderr: Invalid size: abc         exit 1
$ java Shapes circle            # stderr: Usage: java Shapes (circle|square) <size> ...   exit 1
```

## Deliverables

`Shape.hex`, `Circle.hex`, `Square.hex`, and `Shapes.hex`, each an annotated hex file that is the complete class file, plus the `.class` files built from them.
