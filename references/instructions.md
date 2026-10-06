# Instruction reference (JVMS 25, chapters 6 and 7)

Format of each row: hex opcode, mnemonic, operand bytes after the opcode, stack effect (`before -> after`, top of stack on the right).
`cat2` means a `long` or `double` (2 stack slots); everything else is 1 slot.
`idx` = u1 local variable index, `cp2` = u2 constant pool index, `s2`/`s4` = signed branch offset relative to this opcode's address.

## Constants

| Hex | Mnemonic | Operands | Stack |
|---|---|---|---|
| 00 | nop | | -> |
| 01 | aconst_null | | -> null |
| 02 | iconst_m1 | | -> int -1 |
| 03-08 | iconst_0..iconst_5 | | -> int 0..5 |
| 09-0A | lconst_0, lconst_1 | | -> long |
| 0B-0D | fconst_0..fconst_2 | | -> float |
| 0E-0F | dconst_0, dconst_1 | | -> double |
| 10 | bipush | s1 value | -> int (-128..127) |
| 11 | sipush | s2 value | -> int (-32768..32767) |
| 12 | ldc | u1 cp index | -> int/float/String/Class/MethodType/MethodHandle/Dynamic |
| 13 | ldc_w | cp2 | same as ldc, for index > 255 |
| 14 | ldc2_w | cp2 | -> long/double |

## Loads

| Hex | Mnemonic | Operands | Stack |
|---|---|---|---|
| 15 | iload | idx | -> int |
| 16 | lload | idx | -> long |
| 17 | fload | idx | -> float |
| 18 | dload | idx | -> double |
| 19 | aload | idx | -> ref |
| 1A-1D | iload_0..3 | | -> int |
| 1E-21 | lload_0..3 | | -> long |
| 22-25 | fload_0..3 | | -> float |
| 26-29 | dload_0..3 | | -> double |
| 2A-2D | aload_0..3 | | -> ref |
| 2E | iaload | | arrayref, index -> int |
| 2F | laload | | arrayref, index -> long |
| 30 | faload | | arrayref, index -> float |
| 31 | daload | | arrayref, index -> double |
| 32 | aaload | | arrayref, index -> ref |
| 33 | baload | | arrayref, index -> int (byte/boolean) |
| 34 | caload | | arrayref, index -> int (char) |
| 35 | saload | | arrayref, index -> int (short) |

## Stores

| Hex | Mnemonic | Operands | Stack |
|---|---|---|---|
| 36 | istore | idx | int -> |
| 37 | lstore | idx | long -> |
| 38 | fstore | idx | float -> |
| 39 | dstore | idx | double -> |
| 3A | astore | idx | ref -> (also accepts returnAddress) |
| 3B-3E | istore_0..3 | | int -> |
| 3F-42 | lstore_0..3 | | long -> |
| 43-46 | fstore_0..3 | | float -> |
| 47-4A | dstore_0..3 | | double -> |
| 4B-4E | astore_0..3 | | ref -> |
| 4F | iastore | | arrayref, index, int -> |
| 50 | lastore | | arrayref, index, long -> |
| 51 | fastore | | arrayref, index, float -> |
| 52 | dastore | | arrayref, index, double -> |
| 53 | aastore | | arrayref, index, ref -> |
| 54 | bastore | | arrayref, index, int -> |
| 55 | castore | | arrayref, index, int -> |
| 56 | sastore | | arrayref, index, int -> |

## Stack manipulation

| Hex | Mnemonic | Stack |
|---|---|---|
| 57 | pop | v1 -> (v1 is cat1) |
| 58 | pop2 | v2, v1 -> (two cat1) or cat2 -> |
| 59 | dup | v1 -> v1, v1 |
| 5A | dup_x1 | v2, v1 -> v1, v2, v1 |
| 5B | dup_x2 | v3, v2, v1 -> v1, v3, v2, v1 |
| 5C | dup2 | v2, v1 -> v2, v1, v2, v1 (or cat2 -> cat2, cat2) |
| 5D | dup2_x1 | v3, v2, v1 -> v2, v1, v3, v2, v1 |
| 5E | dup2_x2 | v4, v3, v2, v1 -> v2, v1, v4, v3, v2, v1 |
| 5F | swap | v2, v1 -> v1, v2 (cat1 only) |

## Arithmetic and logic

Prefix letter: i int, l long, f float, d double.
Binary ops: `a, b -> result` (result = a op b); unary ops: `a -> result`.

| Op | i | l | f | d |
|---|---|---|---|---|
| add | 60 | 61 | 62 | 63 |
| sub | 64 | 65 | 66 | 67 |
| mul | 68 | 69 | 6A | 6B |
| div | 6C | 6D | 6E | 6F |
| rem | 70 | 71 | 72 | 73 |
| neg (unary) | 74 | 75 | 76 | 77 |

| Hex | Mnemonic | Stack |
|---|---|---|
| 78 / 79 | ishl / lshl | value, int shift -> value |
| 7A / 7B | ishr / lshr | value, int shift -> value |
| 7C / 7D | iushr / lushr | value, int shift -> value |
| 7E / 7F | iand / land | a, b -> a & b |
| 80 / 81 | ior / lor | a, b -> a \| b |
| 82 / 83 | ixor / lxor | a, b -> a ^ b |
| 84 | iinc | operands: idx, s1 const; stack unchanged; local[idx] += const |

`idiv`/`irem`/`ldiv`/`lrem` throw ArithmeticException on division by zero; float/double ops follow IEEE 754.

## Conversions

| Hex | Mnemonic | | Hex | Mnemonic |
|---|---|---|---|---|
| 85 | i2l | | 8D | f2d |
| 86 | i2f | | 8E | d2i |
| 87 | i2d | | 8F | d2l |
| 88 | l2i | | 90 | d2f |
| 89 | l2f | | 91 | i2b |
| 8A | l2d | | 92 | i2c |
| 8B | f2i | | 93 | i2s |
| 8C | f2l | | | |

## Comparisons and branches

| Hex | Mnemonic | Operands | Stack |
|---|---|---|---|
| 94 | lcmp | | long a, long b -> int (-1/0/1) |
| 95 | fcmpl | | float a, float b -> int, NaN -> -1 |
| 96 | fcmpg | | float a, float b -> int, NaN -> 1 |
| 97 | dcmpl | | double a, double b -> int, NaN -> -1 |
| 98 | dcmpg | | double a, double b -> int, NaN -> 1 |
| 99 | ifeq | s2 | int -> (jump if == 0) |
| 9A | ifne | s2 | int -> (!= 0) |
| 9B | iflt | s2 | int -> (< 0) |
| 9C | ifge | s2 | int -> (>= 0) |
| 9D | ifgt | s2 | int -> (> 0) |
| 9E | ifle | s2 | int -> (<= 0) |
| 9F | if_icmpeq | s2 | int a, int b -> (a == b) |
| A0 | if_icmpne | s2 | int a, int b -> (a != b) |
| A1 | if_icmplt | s2 | int a, int b -> (a < b) |
| A2 | if_icmpge | s2 | int a, int b -> (a >= b) |
| A3 | if_icmpgt | s2 | int a, int b -> (a > b) |
| A4 | if_icmple | s2 | int a, int b -> (a <= b) |
| A5 | if_acmpeq | s2 | ref a, ref b -> (same object) |
| A6 | if_acmpne | s2 | ref a, ref b -> (different objects) |
| C6 | ifnull | s2 | ref -> (null) |
| C7 | ifnonnull | s2 | ref -> (not null) |

Long/float/double comparisons: emit the `*cmp*` instruction, then an `if<cond>` on its int result.
To branch on the opposite of a condition, use the inverse opcode (`ifeq`<->`ifne`, `iflt`<->`ifge`, `ifgt`<->`ifle`).

## Control

| Hex | Mnemonic | Operands | Stack |
|---|---|---|---|
| A7 | goto | s2 | -> |
| C8 | goto_w | s4 | -> |
| A8 | jsr | s2 | -> returnAddress (forbidden from major 51) |
| C9 | jsr_w | s4 | -> returnAddress (forbidden from major 51) |
| A9 | ret | idx | -> (forbidden from major 51) |
| AA | tableswitch | pad, s4 default, s4 low, s4 high, s4 offsets[high-low+1] | int key -> |
| AB | lookupswitch | pad, s4 default, s4 npairs, {s4 match, s4 offset}[npairs] sorted by match | int key -> |
| AC | ireturn | | int -> (method returns boolean/byte/char/short/int) |
| AD | lreturn | | long -> |
| AE | freturn | | float -> |
| AF | dreturn | | double -> |
| B0 | areturn | | ref -> |
| B1 | return | | -> (void, `<init>`, `<clinit>`) |

Switch padding: after the opcode at offset `p`, insert `(4 - ((p + 1) % 4)) % 4` zero bytes so the default offset starts at a multiple of 4.
All switch offsets are relative to the switch opcode address.

## Objects, fields, methods

| Hex | Mnemonic | Operands | Stack |
|---|---|---|---|
| B2 | getstatic | cp2 Fieldref | -> value |
| B3 | putstatic | cp2 Fieldref | value -> |
| B4 | getfield | cp2 Fieldref | objectref -> value |
| B5 | putfield | cp2 Fieldref | objectref, value -> |
| B6 | invokevirtual | cp2 Methodref | objectref, args... -> [result] |
| B7 | invokespecial | cp2 Methodref (or InterfaceMethodref from 52) | objectref, args... -> [result]; constructors, private and super calls |
| B8 | invokestatic | cp2 Methodref (or InterfaceMethodref from 52) | args... -> [result] |
| B9 | invokeinterface | cp2 InterfaceMethodref, u1 count, u1 0 | objectref, args... -> [result]; count = 1 + argument slots |
| BA | invokedynamic | cp2 InvokeDynamic, u1 0, u1 0 | args... -> [result]; major 51+ |
| BB | new | cp2 Class | -> uninitialized objectref |
| BC | newarray | u1 atype | int count -> arrayref |
| BD | anewarray | cp2 Class (component) | int count -> arrayref |
| BE | arraylength | | arrayref -> int |
| BF | athrow | | Throwable ref -> (clears stack, transfers to handler) |
| C0 | checkcast | cp2 Class | ref -> ref (ClassCastException if incompatible) |
| C1 | instanceof | cp2 Class | ref -> int 0/1 |
| C2 | monitorenter | | ref -> |
| C3 | monitorexit | | ref -> |
| C5 | multianewarray | cp2 Class (array type), u1 dimensions | count1, ..., countN -> arrayref |

`newarray` atype: 4 boolean, 5 char, 6 float, 7 double, 8 byte, 9 short, 10 int, 11 long.
`[result]` follows the method descriptor's return type (none for `V`, 2 slots for `J`/`D`).

## Extended and reserved

| Hex | Mnemonic | Operands |
|---|---|---|
| C4 | wide | `C4 <load/store/ret opcode> u2 index` or `C4 84 u2 index s2 const` (wide iinc) |
| CA | breakpoint | reserved, must not appear in class files |
| FE / FF | impdep1 / impdep2 | reserved, must not appear in class files |

Opcodes CB..FD are unassigned and must not appear.
Use `wide` only for local indices above 255 or `iinc` constants outside -128..127.

## Computing max_stack

Walk each path, adding pushes and subtracting pops using the table above; `max_stack` is the highest value reached.
Example: `getstatic System.out` (1), `dload_1` (3), `dload_3` (5), `invokestatic Math.hypot(DD)D` (1 + 2 = 3), `invokevirtual println(D)V` (0) -> max_stack 5.
