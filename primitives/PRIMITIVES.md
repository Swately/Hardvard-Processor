# The primitive layer — where the hierarchy stops, and why

> **Status:** `shipping` (2026-07-31).
> **Audience:** whoever works on this processor next, including the operator.

This processor is built structurally: each block is written as an
interconnection of smaller blocks, down to a floor of primitives. The VHDL is
meant to read as a schematic, not as a request to the synthesiser. Writing
`a * b` and letting the tool produce *some* multiplier is the thing this
project deliberately does not do.

A structural design has to declare where it stops. This file is that
declaration.

---

## The floor

| Primitive | Where | Can it be built from something smaller? |
|---|---|---|
| Boolean operators on `std_logic` (`and`, `or`, `xor`, `not`) | the language | **No.** One operator is one gate. |
| `dff` — D flip-flop | [`dff.vhd`](dff.vhd) | **No**, not in synthesisable VHDL. |
| Memory array | `Instruction_Memory`, `Data_Memory`, `Register_File` | **In principle yes, in practice no.** |

Everything above this line is composed. Everything below it is silicon.

### Why the boolean operators are the gates

`y <= a and b;` on `std_logic` is a single two-input gate — it occupies one
input pair of one LUT. Wrapping it in an `and_gate` entity would add hierarchy
and a page of boilerplate without adding a single fact. So the operators are
used directly, and the first thing that *does* get an entity is the 2:1
multiplexer ([`mux2.vhd`](mux2.vhd)), because a multiplexer is genuinely
composed of gates and is the cell that shifters and selects are built from.

Note the one place this is written the long way on purpose: `mux2` is

```vhdl
y <= (a and (not sel)) or (b and sel);
```

and not `y <= a when sel = '0' else b;`. Both describe the same function; only
the first one *is* the diagram.

### Why the flip-flop cannot go lower

A flip-flop made from cross-coupled NAND gates is a **combinational loop**. A
simulator may animate it, but a synthesiser either refuses it or produces
something that is not a flip-flop — the timing that makes the real circuit work
comes from transistor-level behaviour that gate-level VHDL cannot express.
Below the flip-flop you are describing transistors, not FPGA fabric.

Every structural methodology stops here for exactly this reason. Nand2Tetris,
which builds an entire computer from NAND gates, treats the DFF as a given
primitive and says so.

The **clock enable** on `dff` is likewise not a shortcut. An FPGA flip-flop has
a real CE input in silicon; building it as a feedback multiplexer would
describe hardware the chip does not contain and would cost logic for nothing.

### Why memory is the honest concession

A 32 x 32 register file built from primitives is 1,024 flip-flops plus a
32-to-1 multiplexer of 32-bit words. That is *describable* — but on an FPGA it
has to map to block RAM to be usable, and block RAM is a vendor macro that no
amount of structural VHDL will conjure.

Measured, on this design, with the register file left as logic: **5,313 cells**
for the register file alone. That is the price of refusing the concession.

So the rule is: memories are declared as arrays and the tool is allowed to
infer storage. It is the only place in the processor where that is true, and it
is marked in each file.

---

## The layers

| Layer | Contents | Built from |
|---|---|---|
| 0 | boolean operators, `dff`, memory arrays | — (the floor) |
| 1 | [`mux2`](mux2.vhd), `Full_Adder_1bit` | layer 0 |
| 2 | [`mux2_n`](mux2_n.vhd), [`register_n`](register_n.vhd), `Full_Adder_32bits`, `shifter_32` | layer 1 |
| 3 | `Arithmetic_Logic_Unit` | layer 2 |
| 4 | `Program_Counter`, address registers, `Register_File` | layers 2–3 |
| 5 | `Control_Unit` | layer 0 + a state register |
| 6 | `Central_Processing_Unit` — the wiring | layers 3–5 |
| 7 | `Top_Level_Unit`, then a board wrapper | layer 6 |

`Full_Adder_1bit` was already written this way before this restructuring: it is
two boolean equations, and `Full_Adder_32bits` instantiates 32 of them in a
ripple chain. That file is the model the rest of the design was brought up to.

---

## What this costs, measured

A structural description is not automatically smaller or faster. Two real
numbers from this project:

**Where structure wins.** A 32-bit add/subtract unit:

| | LUT4 |
|---|---|
| structural, 32 x `Full_Adder_1bit` | **64** |
| behavioural, the same function via `+` | 257 |

The reason is specific and worth knowing: **VHDL's `+` cannot take a carry
in.** Written behaviourally, an add/subtract unit becomes `(a+b)+carry` — two
adders — or two separate results and a multiplexer. The structural version
seeds `carry(0) <= mode` and gets subtraction from the same adder for free.
*The structural description expresses something the operator level cannot.*

**Where structure loses.** That measurement comes from a generic LUT4 mapper
which ignores the FPGA's dedicated carry chains. A vendor tool maps `+` onto
hardened carry logic — real silicon built for the job — and would likely beat
any adder assembled from LUTs on both area and speed. The ripple chain is also
slow by construction: 32 gate delays end to end.

So the honest statement is: structure buys **control and legibility**, and on
this design it also happened to buy area on the add/sub unit. It does not
categorically buy performance, and on a modern FPGA it usually costs some.

---

## The one rule

> Every operand of a multiplexer is produced by a block. The multiplexer
> selects between wires; it does not compute.

`Arithmetic_Logic_Unit.vhd` follows this literally, and the previous version
did not — its output `case` statement contained `*` and `/`, which is how a
32x32 multiplier and a 32-bit divider arrived without anyone deciding to build
them. The vendor flow puts those two blocks at **2,613 LUT4 plus 1,706 carry
cells**; an earlier draft of this file said 14,899 LUT4 and 73% of the core,
which was an open-source estimate quoted as if it were a fitting result. The
point stands without the inflated number: an operator in a `case` statement
builds hardware nobody chose. See `../syn/VENDOR_VS_ESTIMATE.md`.

Made with my soul - Swately <3
