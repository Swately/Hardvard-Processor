# PHarvard — diagnosis of the "no hace ni vrg" failure

> **Status:** `measured` (2026-07-31). Every number below comes from a GHDL run of
> the design **exactly as it was cloned**, not from reading the source.
> **Reproduce:** `python sim/run_diag.py` (see §6).
> **Audience:** the operator + any LLM session that picks this up.

---

## §1. Headline: the processor is not dead

The commit message on `0aeac5d` reads *"Implementaion de Top level Unit para
prgramacion en FPGA (no hace ni vrg :c)"*. Measured result: **the CPU fetches,
decodes and executes correctly.** It is not broken in the way the board suggests.

Measured PC sequence over a 200-cycle window:

```
PC: 0, 1, 2, 3, 4, 3, 4, 3, 4, 3, 4 ...
```

That is exactly the program in `Instruction_Memory.vhd`: three `LOAD`s, then a
`SUB`/`BNE` loop between addresses 3 and 4. The instruction-level trace shows
the correct architectural values:

| PC | Instruction | Decoded | Result observed |
|---|---|---|---|
| 0 | `0x0AA30009` | `LOAD DM[9] -> r3` | r3 = `0x05F5E100` (100,000,000) |
| 1 | `0x08070005` | `LOAD DM[5] -> r7` | r7 = `0x00000001` |
| 2 | `0x08060007` | `LOAD DM[7] -> r6` | r6 = `0xFFFFFFFF` |
| 3 | `0x04671801` | `SUB r3,r7 -> r3` | `0x05F5E100 - 1 = 0x05F5E0FF` |
| 4 | `0x28610003` | `BNE r3,r1,3` | branches back to 3 |

The ALU arithmetic is right, the register file holds values across instructions,
the branch resolves and redirects the PC. **The datapath works.**

## §2. Why the board looks dead — three compounding causes

### 2.1 The program is a 100-million-iteration countdown

`Instruction_Memory` address 0 loads `Data_Memory[9] = 0x05F5E100` into r3. That
is **100,000,000** (the source comment says "1M en decimal" — the comment is
wrong by 100x). The loop then decrements r3 until it equals r1, and r1 is never
loaded, so the exit condition is r3 = 0.

Measured steady-state loop cost: **34 clock cycles per pass**, constant across
all observed passes. `Top_Level_Unit` clocks the CPU from `Clock`'s `CLK_24Hz`.

```
1,133,333,333 clock cycles / 24 Hz = 47,222,222 s = 547 days = 1.5 years
```

The program cannot terminate in any observable time. This is a **program**
defect, not a hardware one.

### 2.2 The display is wired to the wrong end of the bus

[`Top_Level_Unit.vhd:40`](Top_Level_Unit.vhd#L40) feeds the 7-segment driver with:

```vhdl
entry_value => internal_alu_result(31 downto 19)
```

Those are the **top** 13 bits of a 32-bit result. With r3 = `0x05F5E100` the
display receives the constant **190**, and r3 must fall by 2^19 = **524,288**
before a single digit moves:

| | measured |
|---|---|
| one visible display change, as wired | every 247,580 s = **2.9 days** |
| one visible display change, if wired to `(12 downto 0)` | every **0.47 s** |

So the board shows a frozen `0190`. Combined with §2.1, that is
indistinguishable from a dead chip — which is exactly what was reported.

### 2.3 The SUB executes three times per loop pass

Measured, constant across all 3 observed passes:

```
period in clock cycles : [34, 34, 34]   constant=True
r3 decrement per pass  : [3, 3, 3]      constant=True
```

The program intends **one** decrement per pass. The extra two come from the
`ready`/`update_state` handshake in `Central_Processing_Unit`: `alu_state`
falls back to `cu_state` and re-runs the write when the comparison
`internal_write_reg = internal_des_reg` is re-evaluated, and `Register_File`
independently re-enters `set_state` whenever `write_data` changes — which it
does, because the ALU output moves as the register file re-reads. The two
handshakes retrigger each other.

This does not corrupt the arithmetic (each decrement is individually correct),
but it makes instruction timing depend on data, which is the opposite of what
the handshake was written to guarantee.

## §3. Defects that this program does not exercise (found by reading + a decoder script)

Verified by decoding `Control_Unit`'s literals against its own concurrent
assignments (`sim/decode_ctrl.py`), not by eye:

| Bit map, as actually assigned | |
|---|---|
| bit 0 | `branch` |
| bit 1 | `reg_write` |
| bit 2 | `mem_write` |
| bit 3 | `mem_read` |
| bit 4 | `memto_reg` |
| bit 5 | `IO_read` |
| bit 6 | `IO_write` |

The comment at [`Control_Unit.vhd:87`](Control_Unit.vhd#L87) lists this mapping
**reversed**. The code is correct; the comment is not.

Decoded control table:

| opcode | name | literal | signals actually asserted |
|---|---|---|---|
| `000001` | ALU | `0000010` | reg_write |
| `000010` | LOAD | `0011010` | memto_reg, mem_read, reg_write |
| `000011` | LOADI | `0100000` | **IO_read** |
| `000100` | ADDI | `0100000` | **IO_read** |
| `000101` | SUBI | `0100000` | **IO_read** |
| `000111` | MOVE | `0100000` | **IO_read** |
| `001000` | BEQ | `0000001` | branch |
| `001001` | HALT | `0000000` | (none) |
| `001010` | BNE | `0000001` | branch |
| `001011` | STORE_IO | `0010010` | memto_reg, reg_write |
| `001100` | NOP | `0000000` | (none) |

Computed: `mem_write` is asserted by **0 of 11** opcodes; `reg_write` by
**3 of 11**.

Consequences:

1. **`LOADI`, `ADDI`, `SUBI`, `MOVE` never write their destination register.**
   They assert `IO_read` instead of `reg_write` — bit 5 instead of bit 1.
2. **No opcode can write memory.** There is no `STORE` to data memory at all;
   `STORE_IO` asserts a LOAD-shaped pattern.
3. **The data-memory write port is tied to zero anyway.**
   `internal_data_memory_in` is declared at
   [`Central_Processing_Unit.vhd:26`](Central_Processing_Unit.vhd#L26) and wired
   to `Data_Memory.data_in` at
   [line 172](Central_Processing_Unit.vhd#L172), but **never assigned** — 0
   drivers.
4. **`MUL` and `DIV` are decoded but not implemented.** The CU emits ALU opcodes
   `{0010, 0011}`; the ALU implements 7 of the 9 it is sent, and the missing two
   fall through to `others` and return 0.
5. **`sign_flag`, `overflow`, `parity`, `result_low`, `result_high` have zero
   drivers inside the ALU.** Measured: they never leave `'0'` in simulation.
   (`zero` and `carry` are driven and do toggle.)
6. **`jump_address` is decoded and routed to the CPU but never used** — there is
   no jump instruction.

## §4. Structural findings

These do not stop the current program but block synthesis or make behaviour
tool-dependent:

- **Incomplete sensitivity lists.** `Central_Processing_Unit`'s decode process is
  `process(state)` yet reads ~13 other signals. In simulation it only
  re-evaluates when `state` changes; a synthesiser reads the whole body and
  infers latches. Simulation and silicon will not agree.
- **Memory arrays written from combinational processes.** `Register_File` writes
  `register_bank` and `Data_Memory` writes `data_memory` inside `process(all)`,
  reading and writing the same array in one combinational body. This does not
  map to block RAM and creates a combinational path through storage.
- **Asynchronous reset inside a `process(clk)`.** The reset branch sits outside
  `rising_edge` but `reset` is absent from the sensitivity list in
  `Central_Processing_Unit`, so reset is only sampled on a clock event.
- **`Display` mixes combinational and clocked logic in one process** and drives
  `DISPLAY_SELECTOR` outside the edge.
- **`Clock.CLK_1Hz` is off by 2x.** The counter toggles at 133,000,000, which
  produces a 0.5 Hz square wave. The 24 Hz and 400 Hz dividers use the correct
  half-period constants.
- **`Central_Processing_Unit_tb.vhd` is a stub.** Its "Test 1" block is empty and
  it maps only 2 of the entity's 7 ports; it can pass while proving nothing.
- **`interfaz.vhd`** (24 KB, an LED-matrix icon renderer) declares entity
  `Interfaz` and is instantiated by nothing in the repository.
- **Dead signals in `Central_Processing_Unit`:** `internal_write_data`,
  `internal_data_address_in`, `internal_breaker`, `internal_dmode` are declared
  and never used.

## §5. What this means for the repair

The datapath and the ISA decode are sound; the failure is concentrated in
(a) the control table, (b) unconnected store plumbing, (c) the display wiring,
(d) the handshake re-triggering, and (e) a program that cannot terminate. That
is a repair, not a rewrite — consistent with keeping the existing structure.

## §6. Repair results (2026-07-31)

The repair kept every module, entity name, port name and FSM state name. What
changed is how those states sequence and where storage is written.

### 6.1 Defects found only by repairing (not visible in §2–§4)

Fixing the listed defects exposed five more, each measured:

1. **`previous_state` could capture `update_state`.** Every module uses the idiom
   `when update_state => next_state <= previous_state`. `previous_state` was
   captured unconditionally, so a stall lasting two consecutive cycles recorded
   `update_state` as the place to return to and the FSM locked pointing at
   itself. Fixed in all six modules that use the idiom.
2. **The re-fetch override fired in every state.** `state <= instruction_state`
   when `pc_address_out(7:0) /= instruction_address_in` was applied
   unconditionally, so the PC increment of one instruction landed in the middle
   of the next one. Measured: the SUB reached `alu_state` holding the correct
   operands and was pulled to `instruction_state` one cycle before it could
   commit.
3. **The PC incremented twice per instruction.** The incrementer's input was
   `pc_address_out`, which moves the instant the counter accepts a new value, so
   a multi-cycle `pc_state` kept re-incrementing. Measured: address 1 was never
   fetched. The increment is now based on `instruction_address_in`, which is
   fixed for the whole instruction and therefore idempotent.
4. **Every `ready` signal led the data it advertised by one cycle.** The ready
   decode was combinational on `state`, so it asserted during the same cycle in
   which the clocked process was still computing the value. Measured: the CPU
   latched ALU sources one cycle early, computed `0 - 0`, and committed 0 into
   the loop counter. `ready` now asserts one state later, and additionally drops
   whenever the request on the inputs differs from the latched request — a
   `ready` that does not mean "these outputs answer the question you are asking
   right now" is not usable as a handshake.
5. **A STORE followed by a LOAD of the same address returned 0.** The data
   memory only restarted its walk on an address change, and zeroed `data_out`
   whenever `read_data_enable` was low. Measured: after `STORE r6 -> mem[20]`
   wrote 42, `LOAD mem[20] -> r8` read 0.

Item 4 is the interesting one: it is a single mistake made independently in the
control unit, the register file and the data memory, and it is invisible while
every instruction happens to be preceded by a different-opcode instruction. It
only surfaced on three consecutive `LOADI`s.

### 6.2 Structural changes

- Register-file and data-memory writes now happen on an explicit one-cycle
  `commit` strobe raised by the CPU in `store_state`, instead of from a state of
  the read walk. This is what removed the measured triple execution (§2.3): the
  write path no longer feeds back into the read path through the ALU.
- All storage arrays are written from clocked processes only.
- Datapath registers moved out of the combinational process into the clocked
  one; they were inferred latches driven by a case statement.
- Sensitivity lists completed throughout.

### 6.3 Verification

`python sim/check_cpu.py` builds a golden model by parsing the ROM out of
`Instruction_Memory.vhd`, emulates it, and compares against the GHDL run.
Result on 2026-07-31:

```
golden model: 14 instructions, 31 retired, halt at 13
observed    : 4004 rising edges, 18 register writes, 1 memory writes

  [PASS] reaches HALT -- emulator halts at 13
  [PASS] RTL fetched the HALT instruction
  [PASS] PC sequence matches the emulation -- 31 addresses
  [PASS] register-write count matches -- rtl=18 gold=18
  [PASS] every register write matches (register, value) -- 18 writes
  [PASS] memory-write count matches -- rtl=1 gold=1
  [PASS] every memory write matches (address, value) -- [(20, 42)]
  [PASS] mem_write is exercised
  [PASS] mem_read is exercised
  [PASS] reg_write is exercised
  [PASS] IO_read is NOT spuriously asserted

RESULT: PASS -- the RTL reproduces the golden model exactly
```

### 6.4 Second pass: what a synthesiser found that simulation could not

The behavioural regression in §6.3 passed while the design still contained a
class of defect a VHDL simulator is structurally unable to report: **inferred
latches**. A simulator holds the value of an unassigned signal quite happily.
Running `ghdl --synth` over the same source rejected it:

- **Every decoded field in `Control_Unit` was a latch.** `function_signal`,
  `internal_opcode`, the register numbers, the immediate and the jump address
  were assigned only in `decode1`, from a *combinational* process, so in the
  other states they held.
- **All three address registers had the same fault**, independently:
  `Program_Counter`, `Instruction_Memory_Address_Register` and
  `Data_Memory_Address_Register` each latched their `internal_address_in/out`,
  plus their `ready_count` **variable**, which was not assigned on every path.
- **`Display` was not synthesisable at all.** The digit sweep used
  `to_stdlogicvector(to_bitvector(x) ROR 1)`; GHDL reports
  `unhandled dyn operation: IIR_PREDEFINED_ARRAY_ROR`. It is now an explicit
  concatenation.

All are fixed by the same move used for the CPU datapath: state lives in the
clocked process, the combinational process computes `next_state` and `ready`
and nothing else. `Top_Level_Unit` now synthesises with zero errors, and
`sim/run_diag.py` runs the synthesiser as a gate so this cannot regress.

### 6.5 Area — measured, and it settles the "does it fit" question

Method: `ghdl --synth` to Verilog, then yosys `flowmap -maxlut 4`.
Reproduce with `python syn/estimate_area.py`.

| Configuration | LUT4 | FF | vs MachXO2-7000HE (6,864 LUT4) |
|---|---|---|---|
| `ENABLE_MUL_DIV = true` | 20,442 | 1,438 | **298% — does not fit** |
| `ENABLE_MUL_DIV = false` | 5,543 | 1,438 | **81% — fits** |

The combinational 32x32 multiplier and 32-bit divider cost **14,899 LUT4, 73%
of the core** BY THIS ESTIMATE — the vendor flow later measured the same blocks
at 2,613 LUT4 plus 1,706 carry cells, about 8x smaller, and the "does not fit"
verdict in the table above was wrong. The whole board design fits in 20% of the
part. Keep reading; the paragraph below already said not to trust these
numbers, and it was right. Per-module, with MUL/DIV on: ALU 15,174 cells, register file
5,313, control unit 289, program counter 158, data memory 85, address
registers 46 each.

**This is an estimate from an open-source mapper, not a vendor fitting
result.** A real tool packs LUTs differently and would infer block RAM where
yosys left the register file as logic, which would likely shrink it further.
81% is also tight enough that routing could still fail. Treat it as "the right
order of magnitude", which is all that was needed to answer the question.

Timing (Fmax) is still **not measured** in any configuration.

### 6.6 What is NOT verified

- **Synthesis was not run.** `syn/pharvard.tcl` and `syn/PHarvard.lpf` are
  written but Diamond's `pnmainc` would not execute even a trivial script from
  this session's shell (hangs with no output, both as an argument and on stdin;
  killed at 150 s). There are therefore **no area or Fmax numbers**, and no
  evidence that the design fits the MachXO2-7000HE.
- **The 32x32 MUL and the 32-bit DIV are the open area risk.** The part has no
  DSP blocks, so both map to LUT4 fabric. On this same device a much smaller
  8x16 multiplier measured 200–450 LUT4 (Holith `MEASUREMENT_LOG.md`). These
  two may well not fit alongside the rest; if they do not, the fix is a
  multi-cycle sequential unit, not a smaller instruction set. **This is a
  prediction, not a measurement.**
- **Nothing has been flashed.** Pin constraints are transcribed from the
  Holith board map; the 7-segment digit ORDER is derived from `Display.vhd`,
  not observed.
- Simulation used GHDL only. No second simulator, no gate-level run.

## §6b. Silicon bring-up (2026-08-01) — the defect simulation cannot see

Everything above was found by reading the code and by simulating it. This
section is the first time the design ran on the actual FPGA, and it found a
defect that **no amount of simulation could have found**, plus one process
failure worth more than the defect.

### The symptom

Flashed `sw/hello7seg.s` — three instructions: load 0x1234, store it to the
display, halt. The board showed `0000`. LEDs said the handshake signals were
frozen with the register file never ready.

### Isolating it

Rather than theorise, layers were separated the way the Holith bring-up did it:

1. **`Top_Display_Test.vhd`** — 88 LUT4, the display and a constant, no
   processor at all. It showed `1234`. So the oscillator, the segment order,
   the digit order, the sweep and every pin in that group were correct, and the
   fault was above them.
2. **A debug readout on a switch.** `Top_Level_Unit` gained a `dbg_mode` input
   that swaps the display from "what the program wrote" to "what the processor
   is doing": CPU state, register-file state, handshake bits, and the low
   nibble of read port 2. Diagnosing a stall became a switch flip instead of a
   rebuild and a reflash.
3. In debug mode the display still read `0000` — **and that reading is
   impossible**. The first digit is the processor's state code, and no legal
   state encodes as zero; the lowest is 1. A state code of zero means the
   machine is not in any of its states.

### The cause

The vendor pad report:

```
reset      | 1/5 | LVCMOS25_IN | PULL:DOWN
```

Reset came from a DIP switch **and nothing else**, with an internal pull-down,
so at rest it reads zero. **Reset was never asserted, not once.** The processor
began from whatever state configuration left its flip-flops in.

For a state machine written as an enumerated type that is fatal. The
synthesiser is free to encode the states one-hot, and then "all flip-flops at
zero" is not state zero — it is not a state at all. The next-state decode
matches nothing, the machine never leaves, and the processor is dead.

**Why simulation cannot find this.** Two independent reasons: signals have
initial values there, and every testbench begins by pulsing reset. The bench
would have to be *deliberately* written to skip reset and to start the FSM in
an illegal encoding — that is, someone would have to already suspect it. This
belongs to the same family as the 121 inferred latches: real, and invisible
until a tool outside the simulator looks.

### The fix

`primitives/power_on_reset.vhd` — a counter that holds reset for 1,024 cycles
(~0.5 ms) after configuration, ORed with the pin so manual restart still works.
That counter is the one register in the design that does not need a reset,
because zero is both the natural power-up value of an FPGA flip-flop and where
it wants to start. That is precisely what lets it supply reset to everything
else.

With it, the board showed `1234`. **First execution on silicon in the life of
this project.**

### The instruction set, verified on the board

`1234` proves three instructions. `sw/hwcheck.s` proves the rest: it runs the
same arithmetic the golden model verifies, checks every result against the
value it must have, and displays the count of checks that passed followed by
the values themselves.

**The board shows `0007`, then `0034`, cycling.** Seven of seven. That covers
software multiplication and division, a routine calling another routine through
the stack, a cross-bank store and load, shifts, comparisons and
register-indirect addressing — and the four decimal digits of every frame are
produced by four calls to `__div`, so the readout is itself the software
arithmetic working.

Verification before flashing, with its exact reach: the emulator produced all
eight frames in order and looped correctly; the RTL run confirmed **frame 0
only**, because the 1.2 s inter-frame delay puts the rest outside any
practical simulation window. Frame 0 is the one that carries the weight — to
write a seven the RTL had already computed all seven values and compared them.

### The process failure, which is the more useful finding

The first rebuild after adding the power-on reset reported **byte-identical
utilisation** to the run before it: 1,377 LUT4, 608 registers. Adding a 16-bit
counter cannot leave the area unchanged.

The file had been written and instantiated, but never added to
`syn/synplify_current.tcl`. Synplify never saw it, and the build **succeeded
silently**, producing a bitstream of the previous design. It was caught only
because the numbers were read, not because anything reported a problem.

`syn/build_vendor.py` now cross-checks the sources on disk against the project
file and **refuses to build** when one is missing, or requires it be declared
in `NOT_BUILT` with the reason it is excluded. It immediately found two more
undeclared files. A build that can silently ignore a source file cannot claim
to have built what was asked for — and every area and Fmax figure taken from
such a build is attached to an unknown design.

### One regression introduced and caught here

Adding hex glyphs A–F to `Display.vhd` overwrote the code for 15, which
`sw/slots.s` and `sw/jitter.s` both declare as `BLANK` and which `jitter.s`
writes as `0xFFFF` to mean "no samples yet". Both programs would have kept
running and kept writing the same values while the display said something else.
15 is now blank again and F has no glyph. A display code consumed by software
is a contract, and has to be changed as one.

## §7. Reproducing this

```bash
python sim/run_diag.py
```

Tooling used, all first-hand on this machine:

- GHDL 6.0.0 (mcode, ucrt64), installed 2026-07-31 via
  `winget install ghdl.ghdl.ucrt64.mcode`
- All 15 RTL files analyse clean under `--std=08` **as cloned** — the design is
  syntactically valid VHDL-2008; the defects are semantic.
- `sim/tb_cpu_diag.vhd` — observation-only bench, asserts nothing
- `sim/diag_vcd.py` — VCD parser and trace/arithmetic report
- `sim/decode_ctrl.py` — control-table decoder

Made with my soul - Swately <3
