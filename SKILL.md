---
name: jvm-bytecode
description: Write any JVM program (CLI apps, libraries, classes with fields, constructors, instance methods, interfaces, exceptions) directly as hand-authored class file bytes in annotated hex, with no Java/Kotlin/Scala source and no assembler. Use when the user asks to write something "only in JVM bytecode", hand-craft or patch a .class file, or avoid any high-level JVM language.
---

# Hand-written JVM bytecode

The deliverable is an annotated hex file that IS the class file.
No Java, Kotlin, Scala, Groovy, Clojure, Jasmin, Krakatau, ASM, ByteBuddy, or generator scripts.
The only tooling allowed is turning hex into bytes (`xxd -r -p`) and inspecting/running the result (`javap`, `java`).
Reading `javac` output for inspiration is also not allowed; derive everything from the spec.

One helper is allowed because it only encodes text, not bytecode: getting the bytes and byte length of string data for Utf8 entries.
```
printf '%s' 'java/lang/String' | xxd -p -c 256 | sed 's/../& /g'   # hex bytes
printf '%s' 'java/lang/String' | wc -c                             # Utf8 length
```
For non-ASCII text, remember Utf8 entries use modified UTF-8 (see class-file.md); `printf` gives standard UTF-8, which differs only for U+0000 and characters above U+FFFF.

Authoritative source: The Java Virtual Machine Specification, Java SE 25 Edition (JVMS), chapters 4 (class file format), 6 (instruction set), and 7 (opcode table).
The reference files below are condensed from it:

- [references/class-file.md](references/class-file.md) - ClassFile layout, versions, constant pool, descriptors, flags, attributes, limits.
- [references/instructions.md](references/instructions.md) - every opcode with hex value, operand bytes, and stack effect.
- [references/verification.md](references/verification.md) - StackMapTable encoding, where frames are required, code constraints, common verifier errors.

Read the reference file relevant to the step you are on instead of guessing a value.

## Deliverables

1. One `<ClassName>.hex` per class: every byte of the class file, one logical item per line, with a `#` comment explaining it.
2. `build.sh` - copy [build.sh](build.sh) next to the hex files and run `./build.sh <ClassName>` for each class; it rejects stray non-hex characters and odd digit counts, which `xxd` alone would silently mangle.
3. `<ClassName>.class` - produced by `build.sh`, never edited directly.

Comments start with `#` and run to end of line; never put `#` inside the hex part.

## Workflow

1. **Pick the class file version.**
   Run `java -version`; the highest supported major is feature release + 44 (Java 21 -> 65, Java 25 -> 69).
   Choose the lowest version that has every feature you need (see "Choosing a version" below).
2. **Design the program as pseudocode** in a hex comment block, never as a Java file.
   List each method with its descriptor, and decide local variable slot numbers (remember `long`/`double` take 2 slots, and instance methods have `this` in slot 0).
3. **Lay out the constant pool** before writing any instruction bytes.
   Number every entry from 1 in its comment (`# 13 Fieldref System.out`).
   Add the Utf8 entries for attribute names you will use (`Code`, `StackMapTable`, `SourceFile`, ...).
   `Long`/`Double` entries consume two indices.
4. **Write each method's code** one instruction per line, with its byte offset and mnemonic in the comment (`# 19 aload_0`).
   Track stack depth in the comment when it is not obvious.
5. **Compute derived values** from the offsets: branch offsets, `code_length`, `max_stack`, `max_locals`, exception table, `attribute_length` of every attribute, `constant_pool_count`.
6. **Add stack map frames** if the version is 50 or above and the method has any branch, switch, or exception handler; follow "Building frames step by step" in [references/verification.md](references/verification.md).
7. **Build and inspect**: `./build.sh <ClassName> && javap -v -p -c <ClassName>.class`.
   `javap` must parse cleanly and show exactly the intended constant pool, instructions, and frames.
8. **Run and test** with normal inputs, edge cases, and invalid inputs; check stdout, stderr, and exit codes.
   Loading proves verification passed; `javap` alone does not run the verifier.

## Choosing a version

| Major | Java SE | What it unlocks / requires |
|---|---|---|
| 49 | 5 | Last version verified by type inference; no StackMapTable needed; `ldc` of Class constants. Simplest for small programs. |
| 50 | 6 | Type checking with StackMapTable; may fall back to inference on failure. |
| 51 | 7 | StackMapTable mandatory; `invokedynamic`, MethodHandle, MethodType constants; `jsr`/`ret` forbidden. |
| 52 | 8 | `invokestatic`/`invokespecial` on interface methods (static and default interface methods). |
| 53 | 9 | Modules (`module-info`). |
| 55 | 11 | `CONSTANT_Dynamic`, nest-based access (NestHost/NestMembers). |
| 60 | 16 | Records (Record attribute). |
| 61 | 17 | Sealed classes (PermittedSubclasses); `ACC_STRICT` no longer meaningful. |
| 62-64 | 18-20 | No class file format changes. |
| 65 | 21 | No class file format changes; a common LTS target. |
| 66-68 | 22-24 | No class file format changes. |
| 69 | 25 | Highest major for Java SE 25. |

Minor version: use 0. For major 56+ only 0 or 65535 (preview) are legal.
Prefer 49 when the program needs nothing newer: it avoids hand-computing stack map frames and every modern JVM still runs it.
If the user asks for a modern version, or uses features from 51+, write the StackMapTable.

## Canonical patterns

**Hello world `main`:**
```
B2 00 xx      getstatic java/lang/System.out:Ljava/io/PrintStream;
12 yy         ldc "text"                   (String constant index < 256, else 13 hi lo ldc_w)
B6 00 zz      invokevirtual java/io/PrintStream.println:(Ljava/lang/String;)V
B1            return
```

**Default constructor**: a class with only static methods (e.g. just `main`) needs no `<init>` at all.
Add one only if the class is instantiated: method `<init>` `()V`, access `0001`:
```
2A            aload_0
B7 00 xx      invokespecial java/lang/Object.<init>:()V
B1            return
```

**Creating an object:** `BB new #Class`, `59 dup`, push constructor args, `B7 invokespecial #Class.<init>`.
The value is "uninitialized" until `invokespecial <init>` runs; frames between `new` and `<init>` use `Uninitialized(offset_of_new)`.

**String concatenation without `invokedynamic`:** `new java/lang/StringBuilder`, `dup`, `invokespecial <init>()V`, then `append(...)` calls, then `toString()`.

**Exit code:** `iconst_1` + `invokestatic java/lang/System.exit:(I)V`, then still emit a `return` so code never falls off the end.

**Parsing input:** `Integer.parseInt(String)I`, `Long.parseLong(String)J`, `Double.parseDouble(String)D` take `args[i]` loaded via `aload_0`, index const, `aaload`.
For stdin, use `java/util/Scanner` or `java/io/BufferedReader` over `System.in`.

**Catching an exception:** exception table entry `[start, end) -> handler, catch_type`; the handler starts with the exception object as the only stack item.

## Rules that are easy to get wrong

- All multibyte values are big-endian; branch offsets are signed.
- Branch and switch offsets are relative to the address of the branch/switch opcode itself, not the next instruction.
- `long` and `double` occupy two local slots and two stack slots; `max_locals` and `max_stack` count both, but a StackMapTable lists them as ONE verification type entry.
- `Long`/`Double` constant pool entries occupy two indices; the following index is unusable.
- `constant_pool_count` is the highest index + 1.
- `attribute_length` excludes the 6-byte header (name index + length) of that attribute.
- Code `attribute_length` = 12 + code_length + 8 * exception_table_length + total bytes of nested attributes (each nested attribute is 6 + its length).
- `end_pc` in the exception table is exclusive; `catch_type` 0 catches everything (used for `finally`).
- Every path that reaches an instruction must arrive with the same stack depth and compatible types.
- Execution must never fall off the end of the code array: the last instruction must be a return, `athrow`, `goto`, or switch.
- Class names in the pool use `/` separators (`java/lang/String`), descriptors use `L...;`.
- Utf8 length is a byte count in modified UTF-8, not a character count; `\u0000` and non-ASCII take multiple bytes.
- `tableswitch` and `lookupswitch` need 0-3 padding bytes so the first 4-byte operand starts at an offset divisible by 4 from the code start.
- `invokeinterface` has 2 extra operand bytes: argument slot count (including the receiver) and a 0.
- Use `dcmpl`/`fcmpl` for `>`/`>=` style checks and `dcmpg`/`fcmpg` for `<`/`<=`, so `NaN` makes the condition false.
- `boolean`, `byte`, `char`, `short` are `int` on the stack and in locals.

## Testing tips

`javap -v -p -c` validates the format; only running the class exercises the verifier and the logic.
In zsh, `$var` holding `"3 4"` does not word-split; use `${=var}` or pass arguments literally when looping over test cases.
Map errors to causes with the table in [references/verification.md](references/verification.md).
