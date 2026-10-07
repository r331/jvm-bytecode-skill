# Advanced recipes (JVMS 25 §4.4.10, §4.7.23, §4.7.30, §4.7.31, §3.13)

Recipes for features that need several cooperating structures.
Each lists every constant pool entry, attribute, and instruction involved.

## invokedynamic: string concatenation (major 51+, needs a Java 9+ runtime)

`java/lang/invoke/StringConcatFactory.makeConcatWithConstants` builds strings without StringBuilder.

Constant pool chain (indices are examples):

```
#a Utf8 "java/lang/invoke/StringConcatFactory"        #b Class #a
#c Utf8 "makeConcatWithConstants"
#d Utf8 "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;Ljava/lang/String;[Ljava/lang/Object;)Ljava/lang/invoke/CallSite;"
#e NameAndType #c #d                                   #f Methodref #b #e
#g MethodHandle  0F 06 00 f                            (kind 6 = REF_invokeStatic)
#h Utf8 "Total: \u0001 items"   (01 byte where the argument goes)
#i String #h                                           (the recipe MUST be a String constant, tag 08)
#j Utf8 "(I)Ljava/lang/String;" (call-site type: what is popped, returns String)
#k NameAndType #c #j            (name is free-form; javac uses makeConcatWithConstants)
#l InvokeDynamic 12 00 00 00 k  (first u2 = 0-based index into BootstrapMethods, NOT a cp index)
#m Utf8 "BootstrapMethods"
```

Class attribute:

```
00 m                     # "BootstrapMethods"
00 00 00 08              # attribute_length = 2 + per entry (4 + 2*num_args)
00 01                    # num_bootstrap_methods
00 g 00 01 00 i          # [0] method handle #g, 1 argument: recipe String #i
```

Call site: push the arguments in recipe order, then `BA 00 l 00 00`; the result is a String.

- `invokedynamic` has no receiver; it pops exactly what its descriptor lists and pushes the return type, which is all a stack map frame sees.
- Each distinct recipe needs its own BootstrapMethods entry; several InvokeDynamic constants may share one entry if their recipe is identical (the call-site descriptor may still differ).
- In the recipe, `\u0001` (byte `01`) takes the next dynamic argument and `\u0002` (byte `02`) takes the next extra constant bootstrap argument.
- Argument formatting follows `String.valueOf`: `D`/`F` like `Double.toString` (`1.0E7`), `C` as a character, `I`/`J` as numbers, `Z` as `true`/`false`, `null` as `null`.
- At most 200 argument slots per call site.
- No InnerClasses entry is needed for `MethodHandles$Lookup`, even though javac emits one.

## Records (major 60+) and ObjectMethods

A record class file must have all of these, or it silently loads as a plain class (`isRecord()` false, `getRecordComponents()` null):

- access `0031` (public final super), `super_class` = `java/lang/Record`.
- One `private final` field per component (`0012`), in component order.
- A canonical constructor calling `invokespecial java/lang/Record.<init>:()V` (protected, so call it on `this`), then `putfield` each component.
- Public accessor methods named like the components.
- A `Record` class attribute:

```
Record_attribute {
    u2 attribute_name_index;      // "Record"
    u4 attribute_length;
    u2 components_count;
    {   u2 name_index;            // Utf8 component name
        u2 descriptor_index;      // Utf8 field descriptor
        u2 attributes_count;      // usually 0
        attribute_info attributes[attributes_count];
    } components[components_count];
}
```

`toString`, `hashCode`, and `equals` are each one `invokedynamic` to `java/lang/runtime/ObjectMethods.bootstrap`:

```
bootstrap descriptor:
(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/TypeDescriptor;Ljava/lang/Class;Ljava/lang/String;[Ljava/lang/invoke/MethodHandle;)Ljava/lang/Object;
                                              ^ TypeDescriptor, not MethodType

BootstrapMethods entry: <MethodHandle REF_invokeStatic ObjectMethods.bootstrap>, N args:
    Class   <this record class>
    String  "left;right"                 (component names joined by ';', "" for none)
    MethodHandle 0F 01 <Fieldref left>   (kind 1 = REF_getField), one per component, in order
```

One BootstrapMethods entry serves all three methods; the indy NAME selects the behavior and the descriptor takes the receiver first:

| Method | Code | InvokeDynamic NameAndType |
|---|---|---|
| `toString()Ljava/lang/String;` | `aload_0; invokedynamic; areturn` | `toString:(LAdd;)Ljava/lang/String;` |
| `hashCode()I` | `aload_0; invokedynamic; ireturn` | `hashCode:(LAdd;)I` |
| `equals(Ljava/lang/Object;)Z` | `aload_0; aload_1; invokedynamic; ireturn` | `equals:(LAdd;Ljava/lang/Object;)Z` |

`toString` output looks like `Add[left=Num[value=1], right=Num[value=2]]`.

## Sealed classes and interfaces (major 61+)

```
PermittedSubclasses_attribute {
    u2 attribute_name_index;      // "PermittedSubclasses"
    u4 attribute_length;          // 2 + 2 * number_of_classes
    u2 number_of_classes;
    u2 classes[number_of_classes];   // CONSTANT_Class indices
}
```

- Put it on the sealed class or interface; each permitted subclass must be in the same package (or the same module).
- The JVM enforces only the list; `final`/`sealed`/`non-sealed` on the subclasses is a language rule (records are final anyway).
- The JVM checks a subclass against the list when the subclass loads (`IncompatibleClassChangeError` if not permitted).
- Without the attribute everything still loads; only reflection shows it (`isSealed()` false, `getPermittedSubclasses()` null).
- `javap` never prints `sealed`/`permits` in the header line; look for the `PermittedSubclasses:` section in `javap -v`.

## try / catch / finally (no jsr/ret)

javac's layout, which the verifier accepts at every version:

```
try { A } catch (E e) { B } finally { F }

L0:  A
L1:  F            (copy 1, normal exit)
     goto END
H_E: astore e     (stack: [E])
     B
L2:  F            (copy 2, after catch)
     goto END
H_ANY: astore t   (stack: [Throwable])
     F            (copy 3, exceptional exit)
     aload t
     athrow
END:

Exception table (order matters, first match wins):
[L0, L1)  -> H_E,   catch E
[L0, L1)  -> H_ANY, any (0)
[H_E, L2) -> H_ANY, any (0)
```

Rules:

- `finally` code is duplicated on every exit path: normal end, end of each catch, the catch-all handler, and before every `return`, `break`, or `continue` that leaves the block.
- The inlined copies must NOT be inside the ranges of their own `any` handler, or an exception thrown in the copy runs `finally` twice; split ranges around each copy (one range ends at L1, the next starts at H_E).
- A `return` inside a try: compute the value, store it in a temp local, inline the finally copy (or copies, innermost first when nested), reload the value, return it.
- Nested blocks: list the inner entries (typed catches, then the inner `any`) before the outer ones; outer ranges cover the inner try, the inner handlers, and the inner finally copies.
- Handler frames: stack = `[catch type]` (`java/lang/Throwable` for `any`); locals = only those assigned before the range start (use full_frame or chop when the protected code added locals).
- A handler may reuse a dead local slot for the caught exception, but the frame must then declare the new type for that slot.

## Patching an existing class file

Reading and dumping an existing `.class` is allowed (`javap`, `xxd`); the deliverable is still an annotated hex file.

1. Inspect: `javap -v -p -c Old.class` gives constant pool numbers, code offsets, frames, line tables.
   `javap` does not print file offsets; anchor on a unique byte sequence and use `xxd -g1 -s <offset> -l <len> Old.class`.
2. Start the hex from a dump: `xxd -p -c16 Old.class > Old.hex`, then split and annotate it item by item (header, each pool entry, members, each attribute).
   Annotate at least every region you change and every length, count, and offset field that depends on it.
3. Prefer same-length edits, which leave all offsets valid:
   swapping an opcode (`9A ifne` -> `9D ifgt`), changing a cp index operand, or overwriting removed instructions with `00 nop`.
4. Adding constants: append new entries at the end so existing indices stay valid, raise `constant_pool_count`, and use `13 ldc_w` for indices above 255.
   Do not edit a Utf8/String that other code shares; add a new one.
5. Inserting or removing code bytes requires updating all of:
   - `code_length` and the Code `attribute_length`
   - every branch and switch offset that crosses the edit, and switch padding when the switch moves
   - exception table `start_pc`/`end_pc`/`handler_pc`
   - LineNumberTable and LocalVariableTable(Type) `start_pc` (and `length`)
   - the `offset_delta` of the first StackMapTable frame after the edit (later deltas are relative and stay the same)
   - `max_stack`/`max_locals` if the new code needs more
6. Verify: `javap -p -s` of old and new must match (same members), and the class must load and pass the cases.
