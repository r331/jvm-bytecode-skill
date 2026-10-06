# Verification and stack map frames (JVMS 25, §4.7.4, §4.9, §4.10)

## Which verifier runs

- Major < 50: verification by type inference; no StackMapTable needed (any present is ignored).
- Major 50: type checking with StackMapTable; if it fails, the JVM may fall back to type inference.
- Major >= 51: type checking only; a missing or wrong frame is a VerifyError.

A Code attribute without a StackMapTable is treated as having zero frames, which is only valid for straight-line code without branches or handlers.

## Where a frame is required (major >= 50)

1. Every branch target (`if*`, `goto`, `goto_w`), and every `tableswitch`/`lookupswitch` target including the default.
2. Every exception handler start (`handler_pc`).
3. Every instruction that directly follows an unconditional transfer (`goto`, `goto_w`, any `*return`, `athrow`, switches), even if nothing ever jumps to it.
   The type checker walks every instruction in order, so dead code still needs a frame and must still type-check; the simplest fix is to not emit dead code.

Frames must be listed in increasing offset order with at most one frame per offset.
The frame declares the types at that offset; every incoming path must be assignable to it.
The verifier then continues from the declared frame, not from the actual state of the incoming paths.

## Building frames step by step

1. List every offset that needs a frame (rules above), in increasing order.
2. For each, write the declared state as a comment: `locals [args, int, long]  stack [String]`.
   Declare only what is assigned on every incoming path; anything else is omitted (or Top if followed by a used slot).
3. Pick the compact encoding by comparing with the PREVIOUS FRAME in the table (not the previous instruction):

| Declared state vs previous frame | Encoding |
|---|---|
| same locals, empty stack | same_frame (`00`-`3F`) or same_frame_extended (`FB`) |
| same locals, exactly 1 stack item | same_locals_1_stack_item (`40`-`7F`) or extended (`F7`) |
| previous locals plus 1-3 new locals, empty stack | append_frame (`FC`-`FE`) |
| previous locals minus the last 1-3 locals, empty stack | chop_frame (`F8`-`FA`) |
| anything else (locals change AND stack non-empty, more than 3 locals added/removed, a local's type changes) | full_frame (`FF`) |

A merge point where locals differ from the previous frame and the stack is not empty (e.g. a shared error label that receives a message String) always needs a full_frame.

### frame_type byte lookup

| Byte | Meaning |
|---|---|
| `00`-`3F` | same_frame, offset_delta = byte |
| `40`-`7F` | same_locals_1_stack_item, offset_delta = byte - 0x40 |
| `F7` | same_locals_1_stack_item_extended |
| `F8` | chop 3 |
| `F9` | chop 2 |
| `FA` | chop 1 |
| `FB` | same_frame_extended |
| `FC` | append 1 |
| `FD` | append 2 |
| `FE` | append 3 |
| `FF` | full_frame |

Chop and append count frame ENTRIES, not slots: a `long` or `double` local is one entry, so dropping `[long, int]` is chop 2 (`F9`).

## StackMapTable layout

```
StackMapTable_attribute {
    u2              attribute_name_index;   // Utf8 "StackMapTable"
    u4              attribute_length;
    u2              number_of_entries;
    stack_map_frame entries[number_of_entries];
}
```

The initial frame is implicit, derived from the method descriptor:
locals = `this` (instance methods; `UninitializedThis` in `<init>`) followed by the parameters, stack empty.
`entries[0]` describes the second frame.

### Offsets

- The first explicit frame applies at offset `offset_delta`.
- Every later frame applies at `previous_offset + offset_delta + 1`.
- So `offset_delta = target - previous_target - 1` for all frames after the first.

### Frame types

| frame_type | Name | Following bytes | Meaning |
|---|---|---|---|
| 0-63 | same_frame | none | same locals as previous frame, empty stack; offset_delta = frame_type |
| 64-127 | same_locals_1_stack_item_frame | verification_type_info | same locals, stack = 1 item; offset_delta = frame_type - 64 |
| 128-246 | reserved | | |
| 247 | same_locals_1_stack_item_frame_extended | u2 offset_delta, verification_type_info | as above with a large delta |
| 248-250 | chop_frame | u2 offset_delta | drop the last 251 - frame_type local entries (a long/double counts as 1), empty stack |
| 251 | same_frame_extended | u2 offset_delta | same_frame with a large delta |
| 252-254 | append_frame | u2 offset_delta, verification_type_info[frame_type - 251] | add 1-3 locals, empty stack |
| 255 | full_frame | u2 offset_delta, u2 n_locals, locals[], u2 n_stack, stack[] | everything explicit |

Use `full_frame` (`FF`) whenever unsure; it is always valid, just longer.

### verification_type_info

| Tag | Type | Extra bytes |
|---|---|---|
| 00 | Top (unused or unusable slot) | |
| 01 | Integer (also boolean, byte, char, short) | |
| 02 | Float | |
| 03 | Double (covers 2 slots) | |
| 04 | Long (covers 2 slots) | |
| 05 | Null | |
| 06 | UninitializedThis | |
| 07 | Object | u2 cp index of a CONSTANT_Class (arrays use descriptor names like `[Ljava/lang/String;`) |
| 08 | Uninitialized | u2 code offset of the `new` instruction that created it |

A `long`/`double` is a single entry in a frame's locals or stack list, even though it occupies two slots; do not add a Top after it.
Locals must be listed contiguously from slot 0; use Top (`00`) for gaps.
Trailing Top entries can be omitted.

### Worked example 1: branches and a handler

Static method `main([Ljava/lang/String;)V`, locals: 0 = args, 1-2 = double a, 3-4 = double b.
Frames at 19 (branch target, empty stack, locals = [args]), 57 (handler for NumberFormatException), 58 (branch target from paths where a and b are set and from the handler where they may not be):

```
00 30                 # attribute_name_index -> Utf8 "StackMapTable"
00 00 00 08           # attribute_length
00 03                 # number_of_entries
13                    # same_frame, offset 19
65 07 00 2B           # same_locals_1_stack_item, delta 37 -> offset 57, stack [NumberFormatException]
00                    # same_frame, delta 0 -> offset 58; locals [args] is a valid merge of both paths
```

The frame at 58 declares only `args` because the handler path does not have `a` and `b` assigned; declaring fewer locals is valid as long as code after 58 does not read them.

### Worked example 2: loop with long/int locals, append, chop, full_frame

Verified on Java 21 at major 65.
`main([Ljava/lang/String;)V` computing n!, locals: 0 = args, 1 = n (int), 2-3 = result (long), 4 = i (int).
Class #38 = NumberFormatException, #40 = `[Ljava/lang/String;`, #42 = java/lang/String.

```
 0 aload_0; arraylength; iconst_1
 3 if_icmpeq -> 11
 6 ldc USAGE                     [String]
 8 goto -> 70 (err)
11 aload_0; iconst_0; aaload      (try start)
14 invokestatic Integer.parseInt
17 istore_1                       (try end = 18)
18 goto -> 27
21 pop                            (handler)
22 ldc NOTINT                     [String]
24 goto -> 70 (err)
27 iload_1; iflt -> 68
31 iload_1; bipush 20; if_icmpgt -> 68
37 lconst_1; lstore_2; iconst_2; istore 4
42 iload 4; iload_1; if_icmpgt -> 60     (loop head)
48 lload_2; iload 4; i2l; lmul; lstore_2; iinc 4 1
57 goto -> 42
60 getstatic System.out; lload_2; invokevirtual println(J)V
67 return
68 ldc RANGE                      [String]   (bad)
70 getstatic System.err; swap; invokevirtual println(String)V; iconst_1; invokestatic System.exit; return  (err)
```

```
00 07                                  # number_of_entries (attribute_length 33)
0B                                     # @11 same_frame                      locals [args]
49 07 00 26                            # @21 same_locals_1_stack, delta 9     stack [NumberFormatException]
FC 00 05 01                            # @27 append 1, delta 5               locals [args, int]
FD 00 0E 04 01                         # @42 append 2, delta 14              locals [args, int, long, int]
11                                     # @60 same_frame, delta 17
F9 00 07                               # @68 chop 2 (long and int), delta 7   locals [args, int]
FF 00 01 00 01 07 00 28 00 01 07 00 2A # @70 full_frame, delta 1             locals [String[]] stack [String]
```

Notes:

- @27 and @42 are branch targets AND follow a `goto`; one frame covers both requirements.
- @60 and @68 follow the loop's `goto` and the `return`.
- @70 is reached with locals `[args]` (from 8 and 24) and `[args, int]` (from 68), each with a String on the stack, so it needs a full_frame.
- The loop head @42 declares the loop variables; the back edge from 57 must arrive with the same types.

## Handler frames

At `handler_pc` the stack holds exactly one item: the caught exception type (`catch_type` class, or `java/lang/Throwable` when catch_type is 0).
Its locals must be assignable from the locals at every instruction inside `[start_pc, end_pc)`, so only declare locals that are assigned before `start_pc`.

## Constructors and uninitialized objects

- In `<init>`, slot 0 starts as `UninitializedThis`; after `invokespecial super.<init>` it becomes the class type.
- `new` pushes `Uninitialized(offset_of_new)`; after `invokespecial <init>` all copies become the class type.
- An exception handler must not use a local that held an uninitialized object anywhere inside its protected range.

## Code constraints worth checking (§4.9)

- Only documented opcodes; no `jsr`, `jsr_w`, `ret` from major 51.
- The first instruction is at 0; the last instruction ends at `code_length - 1`; execution never falls off the end.
- Every branch, switch, and handler target is the start of an instruction (never inside operands or the opcode modified by `wide`).
- `ldc`/`ldc_w` must not reference Long/Double; `ldc2_w` must reference Long/Double (or a J/D Dynamic constant).
- `getfield`/`putfield`/`getstatic`/`putstatic` reference Fieldref; `invokevirtual` references Methodref; `invokeinterface` references InterfaceMethodref with a correct count byte and a 0 byte.
- Only `invokespecial` may call `<init>`; nothing may call `<clinit>`.
- `new` must not reference an array class; `newarray` atype is 4-11; `multianewarray` dimensions >= 1.
- Local indices: single-slot types at most `max_locals - 1`, long/double at most `max_locals - 2`; never read a local before it is assigned, never split a long/double pair.
- Same stack depth on every path into an instruction; never exceed `max_stack`; never pop an empty stack.
- Return instruction must match the descriptor's return type; `<init>`, `<clinit>`, and void methods use `return`.
- Every `<init>` (except Object's) must call `this.<init>` or `super.<init>` before using `this` or returning.
- `catch_type` and `athrow` operands must be Throwable subclasses.

## Reading a HotSpot VerifyError

HotSpot's VerifyError message is the best debugging tool; read all of it.
It names the failing offset (`Location: Factorial.main([Ljava/lang/String;)V @68`), prints the reason, the current frame (actual types), the stackmap frame (declared types), the decoded StackMapTable (`chop_frame(@68,1)`), and the bytecode.
Compare the decoded table against your comments: a wrong frame_type byte or delta shows up immediately.
`javap -v` also prints each `frame_type = N` with its decoded locals/stack, which can be checked before running.

## Error -> likely cause

| Error message | Likely cause |
|---|---|
| `Incompatible magic value` | Header bytes wrong, or the hex had stray characters (check `#` comments). |
| `UnsupportedClassVersionError` | Major version above what the running JVM supports. |
| `ClassFormatError: Truncated class file` / `Extra bytes at the end` | A length (`code_length`, `attribute_length`, Utf8 length, counts) is wrong. |
| `ClassFormatError: Invalid constant pool index` / `Illegal constant pool type` | Miscounted entries, Long/Double second slot not skipped, or tag not allowed for the version. |
| `ClassFormatError: Illegal UTF8 string` | Wrong Utf8 length or invalid modified UTF-8 bytes. |
| `ClassFormatError: Method ... has illegal modifiers` | Conflicting access flags (e.g. abstract + final, interface rules). |
| `NoSuchMethodError` / `NoSuchFieldError` | Name or descriptor string does not match the target exactly. |
| `VerifyError: Expecting a stackmap frame at branch target` | Major >= 50 and a required frame is missing or at the wrong offset. |
| `VerifyError: Inconsistent stackmap frames` / `Bad type on operand stack` | Frame types do not match the real state, or an instruction gets the wrong type. |
| `VerifyError: Inconsistent stack height` | Two paths reach one instruction with different stack depths. |
| `VerifyError: Operand stack overflow` | `max_stack` too small (long/double count 2). |
| `VerifyError: Local variable table overflow` / `Illegal local variable number` | `max_locals` too small or index out of range. |
| `VerifyError: Falling off the end of the code` | Last instruction is not a return, `athrow`, `goto`, or switch. |
| `VerifyError: Accessing value from uninitialized register` | Reading a local that is not assigned on some path. |
| `VerifyError: Constructor must call super() or this()` | `<init>` returns without `invokespecial` on `this`. |
| `Error: Main method not found` | Missing `main`, wrong descriptor, or flags are not `0009`. |
