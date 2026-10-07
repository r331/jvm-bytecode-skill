# Task: sealed interface and records

Using only hand-written JVM bytecode, write a prefix-expression calculator made of five classes: a sealed interface, three records, and a main class.
All five class files must use major version 61 (Java 17), minor version 0.
All classes are in the default (unnamed) package.

The three record classes must be real records, laid out the way a Java compiler lays them out, so that `Class.isRecord()` and `Class.getRecordComponents()` work on them.
The interface must be really sealed, so that `Class.isSealed()` and `Class.getPermittedSubclasses()` work on it.

## Classes

### `Expr` (sealed interface)

- Access flags exactly `ACC_PUBLIC | ACC_INTERFACE | ACC_ABSTRACT`, super class `java/lang/Object`, no superinterfaces.
- No fields and no methods.
- Sealed: a `PermittedSubclasses` attribute listing exactly `Num`, `Add`, `Mul`, in that order.

### `Num`, `Add`, `Mul` (records)

| Record | Components, in order |
|---|---|
| `Num` | `long value` |
| `Add` | `Expr left`, `Expr right` |
| `Mul` | `Expr left`, `Expr right` |

Each record class must have:

- Access flags exactly `ACC_PUBLIC | ACC_FINAL | ACC_SUPER`, super class `java/lang/Record`, and `Expr` as its only interface.
- One `private final` instance field per component, with the component's name and type (`J` for `long`, `LExpr;` for `Expr`).
- A `public` canonical constructor taking the components in order (`(J)V` or `(LExpr;LExpr;)V`) that calls `java/lang/Record.<init>()V` and stores every field.
- A `public` accessor method per component, named like the component and returning its type (`value()J`, `left()LExpr;`, `right()LExpr;`).
- `public final` methods `toString()Ljava/lang/String;`, `hashCode()I`, and `equals(Ljava/lang/Object;)Z`, each implemented the way the Java compiler implements them for records: a single `invokedynamic` whose bootstrap method is `java/lang/runtime/ObjectMethods.bootstrap` (a `REF_invokeStatic` method handle), with the static bootstrap arguments being, in order, the record class itself, a String with the component names joined by `;` (for example `left;right`), and one `REF_getField` method handle per component field, in component order.
  Every entry in the record's `BootstrapMethods` attribute must be such an `ObjectMethods.bootstrap` entry.
  Do not hand-code the string building, hashing, or comparison.
- A `Record` attribute listing the components in order with their names and descriptors.

### `Calc8` (main class)

- A public class with `public static void main(String[])` (descriptor `([Ljava/lang/String;)V`).
- A static method `eval` with descriptor `(LExpr;)J` that computes the value of a tree.
  It must dispatch with `instanceof` and `checkcast` on the record classes (at least `instanceof Num` and `instanceof Add`, and `checkcast` to each of `Num`, `Add`, `Mul`), reading the operands through the record accessor methods.
  `Expr` has no `eval` method; do not add one.
- The record text printed below must come from the records' own `toString`; `Calc8` must not contain it as string constants.

## Behavior

Run as `java Calc8 <token>...`.

### Expression mode

The arguments are one expression in prefix notation, read left to right:

- `add` is followed by two expressions, the left operand then the right operand, and builds `new Add(left, right)`.
- `mul` is followed by two expressions in the same way and builds `new Mul(left, right)`.
- Any other token is a number, parsed with `Long.parseLong(String)` (so an optional `+` or `-` sign and decimal digits within the `long` range), and builds `new Num(value)`.
  Tokens are case-sensitive: `ADD` is not `add`.

Parse the arguments into a tree `t1`, then parse the same arguments again into a second, independently built tree `t2`.
Then print these six lines to stdout and exit with code 0:

1. `t1.toString()`, the record's own `toString`, for example `Add[left=Num[value=1], right=Mul[left=Num[value=2], right=Num[value=3]]]`.
2. `= ` followed by `eval(t1)` in decimal.
   Arithmetic is 64-bit two's complement and wraps silently on overflow (`ladd`/`lmul`); for example `mul 9223372036854775807 2` gives `= -2`.
3. `equal: ` followed by `t1.equals(t2)` (`true` or `false`).
4. `hash: ` followed by whether `t1.hashCode() == t2.hashCode()`.
5. `identical: ` followed by whether `t1` and `t2` are the same object (`==`).
6. `literal: ` followed by `new Num(eval(t1)).equals(t1)`, which is `true` only when the whole expression is a single number.

### Introspection mode

If there is exactly one argument and it is `--introspect`, print these four lines to stdout and exit with code 0:

```
Num.isRecord()=true components=value:long
Add.isRecord()=true components=left:Expr,right:Expr
Mul.isRecord()=true components=left:Expr,right:Expr
Expr.isSealed()=true permitted=Num,Add,Mul
```

These values must be computed at run time with reflection, not printed as constants:
for each of `Num`, `Add`, `Mul` print `Class.getSimpleName()`, `.isRecord()=`, the result of `Class.isRecord()`, ` components=`, then for each element of `Class.getRecordComponents()` its `RecordComponent.getName()`, `:`, and `RecordComponent.getType().getSimpleName()`, separated by `,`.
For `Expr` print `Expr.isSealed()=`, the result of `Class.isSealed()`, ` permitted=`, and the `getSimpleName()` of each element of `Class.getPermittedSubclasses()` in array order, separated by `,`.

If `--introspect` appears together with any other argument it is just an ordinary token (and therefore an unknown token).

### Errors

Each error prints exactly one line to stderr, prints nothing to stdout, and exits with the given code.
Errors are detected while parsing `t1` from left to right; the first one found is reported.

| Condition | stderr | Exit code |
|---|---|---|
| No arguments at all | the usage line shown below the table | 1 |
| A token in number position that `Long.parseLong` rejects (including an empty-string argument, `1.5`, `ADD`, or a value outside the `long` range) | `Unknown token: <token>`, with the token exactly as given | 2 |
| `add` or `mul` needs another operand but the arguments ran out | `Missing operand` | 3 |
| A complete expression was parsed but arguments remain | `Trailing token: <token>`, where `<token>` is the first unused argument | 4 |

The usage line is exactly:

```
Usage: java Calc8 <prefix-expr> | --introspect
```

For example, `add x` reports `Unknown token: x` (exit 2) because `x` is reached before the missing right operand, `add 1 mul 2` reports `Missing operand` (exit 3), and `add 1 2 3 x` reports `Trailing token: 3` (exit 4).

Every output line ends with a single `\n`.

## Examples

```
$ java Calc8 add 1 mul 2 3
Add[left=Num[value=1], right=Mul[left=Num[value=2], right=Num[value=3]]]
= 7
equal: true
hash: true
identical: false
literal: false

$ java Calc8 42
Num[value=42]
= 42
equal: true
hash: true
identical: false
literal: true

$ java Calc8 add 1          # stderr: Missing operand        exit 3
$ java Calc8 1 2            # stderr: Trailing token: 2      exit 4
$ java Calc8 foo            # stderr: Unknown token: foo     exit 2
```

## Deliverables

`Expr.hex`, `Num.hex`, `Add.hex`, `Mul.hex`, and `Calc8.hex`, each an annotated hex file that is the complete class file byte for byte, plus the `.class` files built from them.
