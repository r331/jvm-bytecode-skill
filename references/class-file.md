# Class file format reference (JVMS 25, chapter 4)

A class file is a stream of bytes; `u1`, `u2`, `u4` are unsigned 1-, 2-, 4-byte big-endian values.
Items are stored sequentially without padding or alignment.

## ClassFile (§4.1)

```
ClassFile {
    u4             magic;                 // CA FE BA BE
    u2             minor_version;
    u2             major_version;         // 45..69 for Java SE 25
    u2             constant_pool_count;   // entries + 1
    cp_info        constant_pool[constant_pool_count-1];
    u2             access_flags;
    u2             this_class;            // cp index -> CONSTANT_Class
    u2             super_class;           // cp index -> CONSTANT_Class, 0 only for java/lang/Object
    u2             interfaces_count;
    u2             interfaces[interfaces_count];   // cp indices -> CONSTANT_Class
    u2             fields_count;
    field_info     fields[fields_count];
    u2             methods_count;
    method_info    methods[methods_count];
    u2             attributes_count;
    attribute_info attributes[attributes_count];
}
```

Minor version: for major 56+ it must be 0 or 65535 (65535 = depends on preview features of exactly that release).
For major 45-55 any minor is accepted; use 0.

### Class access flags (Table 4.1-B)

| Flag | Value | Meaning |
|---|---|---|
| ACC_PUBLIC | 0x0001 | public |
| ACC_FINAL | 0x0010 | no subclasses |
| ACC_SUPER | 0x0020 | modern invokespecial semantics; always set it for classes (JVM treats it as set since Java 8) |
| ACC_INTERFACE | 0x0200 | interface; requires ACC_ABSTRACT, forbids FINAL/SUPER/ENUM/MODULE |
| ACC_ABSTRACT | 0x0400 | cannot be instantiated; not with FINAL |
| ACC_SYNTHETIC | 0x1000 | compiler generated |
| ACC_ANNOTATION | 0x2000 | annotation interface; requires ACC_INTERFACE |
| ACC_ENUM | 0x4000 | enum class |
| ACC_MODULE | 0x8000 | module-info |

Typical values: public class `0021`, public final class `0031`, public interface `0601`.

## field_info (§4.5) and method_info (§4.6)

```
field_info / method_info {
    u2             access_flags;
    u2             name_index;         // Utf8
    u2             descriptor_index;   // Utf8
    u2             attributes_count;
    attribute_info attributes[attributes_count];
}
```

### Field flags (Table 4.5-A)

PUBLIC 0001, PRIVATE 0002, PROTECTED 0004, STATIC 0008, FINAL 0010, VOLATILE 0040, TRANSIENT 0080, SYNTHETIC 1000, ENUM 4000.
Interface fields must be `0019` (public static final).

### Method flags (Table 4.6-A)

PUBLIC 0001, PRIVATE 0002, PROTECTED 0004, STATIC 0008, FINAL 0010, SYNCHRONIZED 0020, BRIDGE 0040, VARARGS 0080, NATIVE 0100, ABSTRACT 0400, STRICT 0800 (only meaningful for major 46-60), SYNTHETIC 1000.

- `main`: `0009` public static, name `main`, descriptor `([Ljava/lang/String;)V`.
- Instance initializer: name `<init>`, return type `V`; only `invokespecial` may call it.
- Class initializer: name `<clinit>`, descriptor `()V`, flag `0008`; called only by the JVM.
- Abstract and native methods have no Code attribute; every other method has exactly one.

## Descriptors (§4.3)

| Char | Type |
|---|---|
| B | byte |
| C | char |
| D | double (2 slots) |
| F | float |
| I | int |
| J | long (2 slots) |
| S | short |
| Z | boolean |
| V | void (return only) |
| L*ClassName*; | reference, e.g. `Ljava/lang/String;` |
| [ | one array dimension, e.g. `[I`, `[[Ljava/lang/Object;` |

Method descriptor: `(` parameter descriptors `)` return descriptor, e.g. `(IDLjava/lang/Thread;)Ljava/lang/Object;`.
Max 255 parameter slots including `this`; `long`/`double` count as 2.
Binary names in `CONSTANT_Class` use `/`; array classes use the descriptor form (`[I`, `[Ljava/lang/String;`).

## Constant pool (§4.4)

| Tag | Kind | Layout after tag | Since major | Loadable by ldc |
|---|---|---|---|---|
| 1 | Utf8 | u2 length, u1 bytes[length] | 45 | no |
| 3 | Integer | u4 bytes | 45 | yes |
| 4 | Float | u4 IEEE 754 binary32 | 45 | yes |
| 5 | Long | u4 high, u4 low (uses 2 indices) | 45 | ldc2_w |
| 6 | Double | u4 high, u4 low IEEE 754 binary64 (uses 2 indices) | 45 | ldc2_w |
| 7 | Class | u2 name_index (Utf8) | 45 | yes, from 49 |
| 8 | String | u2 string_index (Utf8) | 45 | yes |
| 9 | Fieldref | u2 class_index, u2 name_and_type_index | 45 | no |
| 10 | Methodref | u2 class_index, u2 name_and_type_index | 45 | no |
| 11 | InterfaceMethodref | u2 class_index, u2 name_and_type_index | 45 | no |
| 12 | NameAndType | u2 name_index, u2 descriptor_index | 45 | no |
| 15 | MethodHandle | u1 reference_kind, u2 reference_index | 51 | yes |
| 16 | MethodType | u2 descriptor_index (Utf8 method descriptor) | 51 | yes |
| 17 | Dynamic | u2 bootstrap_method_attr_index, u2 name_and_type_index (field descriptor) | 55 | yes |
| 18 | InvokeDynamic | u2 bootstrap_method_attr_index, u2 name_and_type_index (method descriptor) | 51 | no (invokedynamic) |
| 19 | Module | u2 name_index | 53 | no |
| 20 | Package | u2 name_index | 53 | no |

Tags 2, 13, 14 are unused.
An entry may only use a tag defined in the class file's version or earlier.
Valid indices are 1..constant_pool_count-1; the index after a Long/Double must exist but is unusable.

### Common constant encodings

- int 1000 -> `03 00 00 03 E8`; small ints should use `iconst_*`, `bipush`, `sipush` instead.
- double 0.5 -> `06 3F E0 00 00 00 00 00 00`; 1.0 -> `3F F0 00 00 00 00 00 00`; 2.0 -> `40 00 00 00 00 00 00 00`.
- float 1.0 -> `04 3F 80 00 00`.

### Modified UTF-8 (§4.4.7)

- U+0001..U+007F: 1 byte `0xxxxxxx`.
- U+0000 and U+0080..U+07FF: 2 bytes `110xxxxx 10xxxxxx` (so NUL is `C0 80`).
- U+0800..U+FFFF: 3 bytes `1110xxxx 10xxxxxx 10xxxxxx`.
- Supplementary characters: each UTF-16 surrogate encoded separately as 3 bytes (6 total); the standard 4-byte UTF-8 form is invalid.
- No byte may be 0x00 or in 0xF0..0xFF; `length` is the byte count.

### MethodHandle reference_kind (§4.4.8)

| Kind | Name | reference_index points to |
|---|---|---|
| 1 | REF_getField | Fieldref |
| 2 | REF_getStatic | Fieldref |
| 3 | REF_putField | Fieldref |
| 4 | REF_putStatic | Fieldref |
| 5 | REF_invokeVirtual | Methodref |
| 6 | REF_invokeStatic | Methodref (or InterfaceMethodref from 52) |
| 7 | REF_invokeSpecial | Methodref (or InterfaceMethodref from 52) |
| 8 | REF_newInvokeSpecial | Methodref named `<init>` |
| 9 | REF_invokeInterface | InterfaceMethodref |

## Attributes (§4.7)

Every attribute starts with `u2 attribute_name_index` (Utf8 name) and `u4 attribute_length` (bytes that follow, excluding these 6).
Unknown attributes are ignored by the JVM.

| Attribute | Location | Since major | Notes |
|---|---|---|---|
| Code | method_info | 45 | Required for non-abstract, non-native methods. |
| ConstantValue | field_info | 45 | `u2 constantvalue_index`; initializes static final fields. |
| Exceptions | method_info | 45 | `throws` clause; informational for the JVM. |
| SourceFile | ClassFile | 45 | `u2 sourcefile_index`; shown in stack traces. Optional. |
| LineNumberTable | Code | 45 | Optional debug info. |
| LocalVariableTable | Code | 45 | Optional debug info. |
| InnerClasses | ClassFile | 45 | Needed for nested class metadata. |
| StackMapTable | Code | 50 | Required for type-checking verification (see verification.md). |
| Signature | ClassFile, field, method | 49 | Generic signatures; optional at run time. |
| BootstrapMethods | ClassFile | 51 | Required when Dynamic/InvokeDynamic constants exist. |
| MethodParameters | method_info | 52 | Optional. |
| Module, ModulePackages, ModuleMainClass | ClassFile | 53 | module-info only. |
| NestHost, NestMembers | ClassFile | 55 | Private access between nest members. |
| Record | ClassFile | 60 | Record components. |
| PermittedSubclasses | ClassFile | 61 | Sealed classes. |

### Code (§4.7.3)

```
Code_attribute {
    u2 attribute_name_index;      // "Code"
    u4 attribute_length;
    u2 max_stack;
    u2 max_locals;                // includes parameters and this
    u4 code_length;               // 1..65535
    u1 code[code_length];
    u2 exception_table_length;
    {   u2 start_pc;              // inclusive, opcode boundary
        u2 end_pc;                // exclusive, opcode boundary or code_length
        u2 handler_pc;            // opcode boundary
        u2 catch_type;            // Class (Throwable subclass) or 0 = any
    } exception_table[exception_table_length];
    u2 attributes_count;
    attribute_info attributes[attributes_count];
}
```

`attribute_length = 12 + code_length + 8*exception_table_length + sum(6 + len of each nested attribute)`.
Handler order matters: the first matching entry wins.
The greatest local index for a `long`/`double` is `max_locals - 2`.

### BootstrapMethods (§4.7.23)

```
BootstrapMethods_attribute {
    u2 attribute_name_index;      // "BootstrapMethods"
    u4 attribute_length;
    u2 num_bootstrap_methods;
    {   u2 bootstrap_method_ref;  // MethodHandle
        u2 num_bootstrap_arguments;
        u2 bootstrap_arguments[num_bootstrap_arguments];   // loadable constants
    } bootstrap_methods[num_bootstrap_methods];
}
```

String concatenation via `invokedynamic` uses bootstrap `java/lang/invoke/StringConcatFactory.makeConcatWithConstants` (REF_invokeStatic) with descriptor `(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;Ljava/lang/String;[Ljava/lang/Object;)Ljava/lang/invoke/CallSite;` and a recipe String argument where `\u0001` (encoded `01`) marks each dynamic argument.

### SourceFile (§4.7.10)

`00 xx` ("SourceFile") `00 00 00 02` `00 yy` (Utf8 file name); costs 8 bytes and improves stack traces.

## Limits (§4.11)

- Constant pool, fields, methods, interfaces: at most 65535 each.
- `max_locals`, `max_stack`: at most 65535 (long/double count 2).
- Method parameters: at most 255 slots including `this`.
- Utf8 strings: at most 65535 bytes.
- Array dimensions: at most 255.
- Code length: less than 65536; keep it at most 65534 so the last instruction can be covered by an exception handler.
