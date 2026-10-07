# Task: Patch a legacy Inventory class

We have a legacy JVM program, `legacy/Inventory.class` (in your working directory).
Its source code is lost; only the compiled class file exists.
Users report that some of its outputs are wrong.
Fix it by patching the class file, written as hand-authored class file bytes in annotated hex.
Do not write Java, Kotlin, or any other source, and do not use javac, an assembler, or a generator script.
You may inspect the legacy class with read-only tools such as `javap` and `xxd`, and run it with `java -cp legacy Inventory ...`.
Do not modify or delete anything under `legacy/`.

## What to deliver

- `Inventory.hex` in the working directory root: every byte of the fixed class file, one logical item per line, each with a `#` comment explaining it.
- `Inventory.class` in the working directory root, built from that hex.

This is a patch, not a rewrite:

- Keep the class name `Inventory` in the default package, its access flags, and its superclass.
- Keep exactly the same fields and methods as the legacy class: same names, descriptors, and access flags; add or remove none.
- Keep the same class file version as the legacy class (major 65, minor 0).
- Change only what is needed to make the program behave as specified below.

## Intended behavior

`java Inventory <command>...`

The program keeps an inventory of named items with integer quantities, which starts empty on every run and holds at most 8 distinct items.
It processes the command-line arguments from left to right as a sequence of commands:

| Command | Arguments consumed | Effect |
|---|---|---|
| `add <name> <qty>` | 3 | If an item named `<name>` exists, increase its quantity by `<qty>`; otherwise append a new item `<name>` with quantity `<qty>`. |
| `remove <name> <qty>` | 3 | Decrease the quantity of item `<name>` by `<qty>`. An item whose quantity reaches 0 stays in the inventory, in its place, with quantity 0. |
| `total` | 1 | Print the sum of all quantities on its own line (`0` when the inventory is empty). |
| `list` | 1 | Print every item as `<name>=<qty>` on its own line, in the order the items were first added. Print nothing when the inventory is empty. |

Details:

- Command names are case-sensitive and must match exactly (`Total` is not a command).
- `add` and `remove` always take the next two arguments as `<name>` and `<qty>`, whatever they contain, so `add total 5` adds an item named `total`.
- Item names are arbitrary strings, including the empty string, and are compared exactly (case-sensitive).
- A `<qty>` is valid if it is exactly a string accepted by Java's `Integer.parseInt(String)` (an optional `+` or `-` sign followed by decimal digits, within the 32-bit signed `int` range; leading zeros allowed) and its value is at least 1.
- Quantities and the total are 32-bit `int` values; additions wrap silently on overflow (for example `add a 2147483647 add a 1 total` prints `-2147483648`).
- Output of commands that already ran stays on stdout even if a later command fails.
- On success the program prints nothing to stderr and exits with code 0.

## Errors

Each error prints exactly one line to stderr and immediately ends the program with the given exit code; no later command runs.

| Condition | stderr | Exit code |
|---|---|---|
| No arguments at all | `Usage: java Inventory <command>...` | 1 |
| A command is not one of `add`, `remove`, `total`, `list` | `Error: unknown command <cmd>` | 2 |
| `add` or `remove` is followed by fewer than two more arguments | `Error: missing argument for <cmd>` | 2 |
| The `<qty>` of `add` or `remove` is not valid | `Error: invalid quantity <qty>` | 3 |
| `remove` names an item that is not in the inventory | `Error: unknown item <name>` | 4 |
| `remove` asks for more than the item's current quantity | `Error: insufficient stock for <name>` | 4 |
| `add` of a new item when the inventory already holds 8 items | `Error: inventory full` | 5 |

`<cmd>`, `<qty>`, and `<name>` are the arguments exactly as given (an empty argument leaves the trailing space, e.g. `Error: unknown item ` for an empty name).
For one `add` or `remove`, check in this order: missing arguments, then the quantity, then (for `remove`) unknown item, then insufficient stock.
Adding to an item that already exists never reports `inventory full`.

All lines end with a single newline.

Examples:

- `java Inventory add apple 3 add pear 2 list total` prints `apple=3`, `pear=2`, `5` (exit 0).
- `java Inventory add a 4 remove a 4 list` prints `a=0` (exit 0).
- `java Inventory add a 3 total remove b 1 total` prints `3` to stdout, then `Error: unknown item b` to stderr (exit 4).
- `java Inventory add a -2` prints `Error: invalid quantity -2` to stderr (exit 3).
