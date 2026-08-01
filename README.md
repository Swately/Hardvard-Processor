# PHarvard — a 32-bit modified-Harvard processor in VHDL

A multi-cycle processor with separate instruction and data buses over a single
address space, built for the Lattice **MachXO2-7000HE** (TQFP-144) on a custom
I/O daughterboard. It runs on the hardware: the full instruction set is
verified on silicon, and it plays a slot machine as an ordinary program.

**The point of this project is not speed. It is to build a processor the way
one is actually built** — as a diagram in text, structurally, where complex
operations are composed from simple ones rather than requested from the
synthesiser. There is no multiplier circuit here. There is a multiply
*routine*, made of adds and shifts, and it costs zero gates.

---

## State

| | |
|---|---|
| **Hardware** | **runs on silicon.** Full instruction set verified on the board, 2026-08-01 |
| Simulation | passes — reproduces a golden model of its own program exactly |
| Area | **1,409 LUT4 of 6,864 (21 %)**, 625 registers (9 %), 12 of 26 block RAMs (46 %) |
| Timing | post-route **Fmax 20.4 MHz**, zero timing errors; the design runs at 2.08 MHz |

Every number above is from the vendor toolchain (`python syn/build_vendor.py`),
not an estimate. The distinction cost this project a wrong decision once and is
documented in [`syn/VENDOR_VS_ESTIMATE.md`](syn/VENDOR_VS_ESTIMATE.md).

### What "verified on silicon" means here

[`sw/hwcheck.s`](sw/hwcheck.s) runs the instruction set on the FPGA and displays
a verdict it computes **about itself**: `0007`, seven of seven checks passed. It
then cycles the values it actually computed — `0034`, `0132`, `0012`, `0014`,
`0002`, `0049`, `0495` — so a wrong one names the broken operation instead of
merely reporting that something is broken.

That seven covers software multiplication and division, a routine calling
another routine through the stack, a store into one memory bank read back from
the other, shifts, comparisons and register-indirect addressing. The four
decimal digits of every frame are themselves produced by four calls to `__div`,
because this machine has no divide instruction: **the display is a photograph
of its own software arithmetic working.**

Getting there took one defect that no simulation can find. Reset came from a
switch and nothing else, so it was never asserted, and the state machine
started in an encoding that is not a state. The full account, including how it
was isolated, is in [DIAGNOSIS.md §6b](DIAGNOSIS.md).

---

## Architecture

**Modified Harvard.** Separate instruction and data buses, one 512-word address
space, either bank usable for either purpose. This is the arrangement ARM
Cortex-M and most DSPs use. It is not von Neumann — the buses stay separate,
which is the property worth keeping — and it is not classical Harvard either,
because code space is writable and data space is executable. Both are proved by
[`sim/tb_memory.vhd`](sim/tb_memory.vhd).

The two banks are true dual-port block RAM, so an instruction fetch and a data
access complete **in the same cycle even in the same bank**, with no arbitration
and no stalls. That is what dual port buys and what a single-bus machine cannot
do.

**The instruction encoding is MIPS's** — R-type with `shamt` and `funct`,
I-type with a 16-bit immediate, J-type with a 26-bit address. Encoding and
memory organisation are different axes and worth not confusing.

### The structural discipline

[`primitives/PRIMITIVES.md`](primitives/PRIMITIVES.md) declares the irreducible
floor: boolean operators (one gate each), a **D flip-flop** (a latch of
cross-coupled NANDs is a combinational loop that no synthesiser will accept —
Nand2Tetris declares the DFF primitive for the same reason), and **memory**, the
one real concession, because storage cannot be assembled from gates in any
practical sense.

Everything else is built. The rule that governs it:

> Every operand of a multiplexer is produced by a block. The multiplexer selects
> between wires; it does not compute.

The ALU follows this literally. Its output `case` selects among wires and never
contains an operator — an earlier version contained `*` and `/`, which is how a
32×32 multiplier and a 32-bit divider arrived without anyone deciding to build
them.

One measurement that argues for the approach: a 32-bit adder/subtractor is
**64 LUT4 structurally against 257 behaviourally**. The reason is concrete —
`+` in VHDL takes no carry-in, so the behavioural form needs two adders or an
add, a subtract and a multiplexer, while the structural one just seeds
`carry(0)` with the mode bit. *Structural description can express things the
operator level cannot.* The honest counterweight: an open-source mapper ignores
the part's hardened carry chains, and a vendor tool maps `+` onto them.

---

## Instruction set

```
R: opcode(31:26) src(25:21) trg(20:16) des(15:11) shamt(10:6) func(5:0)
I: opcode(31:26) src(25:21) trg(20:16) immediate(15:0)
J: opcode(31:26) address(25:0)
```

| opcode | mnemonic | effect |
|---|---|---|
| `000001` | ALU | R-type, see the function table |
| `000010` | LOAD | `mem[reg[src] + imm] -> trg` |
| `000011` | LOADI | `imm -> trg` |
| `000100` | ADDI | `src + imm -> trg` |
| `000101` | SUBI | `src - imm -> trg` |
| `000110` | STORE | `trg -> mem[reg[src] + imm]` |
| `000111` | MOVE | `src -> trg` |
| `001000` | BEQ | `if src = trg then pc := imm` |
| `001001` | HALT | stop |
| `001010` | BNE | `if src /= trg then pc := imm` |
| `001100` | NOP | |
| `001101` | JUMP | `pc := address` |
| `001110` | **JAL** | `r31 := pc+1; pc := address` |
| `001111` | **JR** | `pc := reg[src]` |

R-type functions: `000000` ADD, `000001` SUB, `000100` AND, `000101` OR,
`000110` XOR, `000111` NOT, `001000` SHL, `001001` SHR, `001010` SLT,
`001011` SLTU.

`000010` and `000011` were MUL and DIV. They are **RESERVED, not reused** — the
hardware returns zero — so an old binary cannot silently mean something new.
Multiplication and division are software routines, which is what RV32I does
without the M extension.

Register 0 reads as zero and cannot be written. Immediates are sign-extended.
`SHL`/`SHR` take their amount from bits 10:6, the `shamt` field the original
design decoded and threw away.

### Two additions that were not new instructions

**The stack needed none.** `LOAD` and `STORE` already decoded a `src` field
they did not use, and r0 reads zero — so making the address `reg[src] + imm`
turned the old absolute form into the special case `addr(r0)` and gave
register-indirect addressing for free, fully backwards compatible. Cost: one
32-bit adder, 64 LUT4. That is all a stack ever needed.

**I/O needed none either.** The top sixteen data addresses (496–511) decode to
peripherals instead of RAM, so `store r4, DIGITS` is an ordinary store whose
address happens to land there.

**`JAL` and `JR` are the enabling pair.** Without saving a return address and
jumping back through a register, a routine cannot be called from two places,
and "build complex operations from simple ones" collapses into pasting the same
code at every call site.

---

## Software

The ROM is not hand-encoded hexadecimal. [`tools/pasm.py`](tools/pasm.py) is a
two-pass assembler with labels, `.bank`/`.org`/`.word`/`.equ`, and pseudo-
instructions (`push`, `pop`, `call`, `ret`, `mul`, `div`, `mod`) that **declare
out loud which registers they destroy** — one that clobbers silently is a trap.

```bash
python tools/pasm.py sw/slots4.s -o memory_image_pkg.vhd
```

`memory_image_pkg.vhd` is **generated**. Edit the `.s` file, never it.

### Calling convention

| registers | role |
|---|---|
| `r4`, `r5` | arguments |
| `r6`, `r7` | return values |
| `r8`–`r15` | scratch — a routine may destroy these |
| `r16`–`r28` | the caller's — a routine must not touch them |
| `r29` (`sp`) | stack pointer, grows downward |
| `r31` (`ra`) | return address, written by `JAL` |

**Routines nest.** `call` saves `ra` on the stack around the `JAL`; inside a
routine that has already done `push ra`, the one-word `jal` is used instead.
That is the MIPS convention — save `ra` once on entry — and using `call`
everywhere overflowed a 256-word bank.

### Multiplication and division are routines, not circuits

`__mul` is shift-and-add; `__div` is restoring division. Both are **bounded at
32 rounds** whatever the operands. Multiplying by repeated addition wins only
up to about `b = 56`; at `b = 2^31` it would take roughly 23 hours against a
constant 2.2 ms.

Note what `__mul` actually needs: `ADD`, `AND` and `BEQ`. `add x, x` *is* a left
shift, so even the shift instructions are a convenience rather than a
requirement.

| | gates | time |
|---|---|---|
| hardware MUL + DIV | 2,613 LUT4 + 1,706 carry cells (vendor) | 1 instruction |
| software MUL + DIV | **0** | 2.2 ms / 4.4 ms |

### Programs

| | |
|---|---|
| [`sw/hwcheck.s`](sw/hwcheck.s) | the instruction set, self-checked on the board |
| [`sw/slots4.s`](sw/slots4.s) | the four-reel slot machine |
| [`sw/demo.s`](sw/demo.s) | the ISA regression the golden model checks |
| [`sw/hello7seg.s`](sw/hello7seg.s) | three instructions; the first thing to flash |
| [`sw/btntest.s`](sw/btntest.s) | puts the raw button register on the display |
| [`sw/jitter.s`](sw/jitter.s) | the two-oscillator entropy experiment |
| [`sw/slots.s`](sw/slots.s) | the earlier three-reel game, kept |

---

## The slot machine

Four reels, each a digit, so a spin fills the display with a four-figure number.

```
C010        idle: the letter C and the credit count
7 3 3 1     the reels
A001        what was won
```

Scoring costs almost nothing. Count, over every ordered pair of reels including
each with itself, how many are equal:

| hand | total | probability | pays |
|---|---|---|---|
| four of a kind | 16 | 0.10 % | 50 |
| three of a kind | 10 | 3.60 % | 8 |
| two pair | 8 | 2.70 % | 4 |
| one pair | 6 | 43.20 % | 1 |
| nothing | 4 | 50.40 % | 0 |

Every hand gives a different total, so **one number names the hand** — a plain
double loop, no sorting, no special cases, and it extends to any number of reels
unchanged. Return to player is **87.8 %**, computed exactly over all 10,000
outcomes. Real machines run 85–98 %.

`sim/check_slots4.py` runs the real `score` routine with **all 10,000 possible
hands**, entering it directly with the reels placed in memory. A normal game
reaches five spins in a million and a half instructions, all of them pairs or
nothing; the ten four-of-a-kinds would take hours of simulated play to meet by
chance.

### Where the randomness comes from

This is the **classic arrangement**, and worth stating precisely rather than
calling it a random number generator:

- A free-running 32-bit maximal-length **LFSR** (taps 32/22/2/1) steps once per
  clock, forever. On its own it is **completely deterministic** — same seed,
  same sequence — and it is not cryptographically anything: thirty-two output
  bits are enough to recover its entire state.
- **The entropy is the player's timing.** Pressing the button samples a counter
  that has advanced a few million steps since the last press, and no one places
  a finger to the microsecond.

That is the standard technique in arcade and embedded hardware, and it is
entirely adequate for a slot machine. It is *not* a true random number
generator, and this repository does not claim one. Making that claim honestly
would need a physical noise source and measurement — which is what
[`sw/jitter.s`](sw/jitter.s), `edge_counter.vhd` and
[`docs/RNG_CONTEXT.md`](docs/RNG_CONTEXT.md) are the beginning of, and that work
is not finished.

One consequence worth recording, because it produced a wrong conclusion once: an
earlier build spun on a timer when no button was detected, and the reels still
looked perfectly random. **Sampling an LFSR at a fixed interval leaves a period
of billions**, so "it looks random" was no evidence the button worked at all.

---

## Running the simulation

Needs GHDL (`winget install ghdl.ghdl.ucrt64.mcode`).

```bash
python sim/run_diag.py
```

That reassembles the program, analyses every source, runs `ghdl --synth` as a
**synthesis gate**, executes the observation bench, and finishes with a
self-check against a golden model built by emulating the program's own image.
It exits non-zero if the RTL and the model disagree.

| Command | What it does |
|---|---|
| `python sim/run_diag.py` | the whole regression |
| `python sim/check_slots4.py` | the slot machine: rule, routine and program |
| `python sim/check_hw.py` | what the RTL writes to the display for `hwcheck.s` |
| `python sim/run_slots.py` | decodes the multiplexed display as an eye would |
| `python sim/decode_ctrl.py` | decodes the control table straight from the VHDL |

**The synthesis gate earns its place.** It found 121 inferred latches that
simulation is structurally incapable of seeing — later confirmed independently
by the vendor tool's own report on the old design.

---

## Building and flashing

```bash
python syn/build_vendor.py
```

Synthesis → EDIF → NGO → NGD → map → place & route → timing → JEDEC, and it
prints the real utilisation and post-route Fmax.

Diamond's usual driver, `pnmainc`, will not run from an automation shell on this
machine — it hangs with no output, as an argument and on stdin, elevated and
not, with a real console allocated. But it is only a *driver*: the tools beneath
it are ordinary executables and work perfectly when called directly with
`FOUNDRY` set. That is the whole trick.

```bash
G:\LatticeDiamond\bin\nt64\pgrcmd.exe -infile syn\pharvard.xcf -cabletype USB2 -portaddress FTUSB-0
```

Two things that cost time and are worth knowing:

- **The build refuses to run if a source file is missing from the project.**
  `power_on_reset.vhd` was once written, instantiated, and left out of the
  Synplify project — the build *succeeded*, producing a bitstream of the
  previous design, and only byte-identical utilisation gave it away. Both
  `build_vendor.py` and `run_diag.py` now cross-check the tree against their
  file lists.
- **An XML comment between the DOCTYPE and the root element breaks the `.xcf`
  parser** with `Opening XCF file... Failed!` and no further explanation.

### Pins

[`syn/PHarvard.lpf`](syn/PHarvard.lpf) marks every line with its provenance:
`[HW]` exercised on this board and confirmed, `[TX]` transcribed from
photographs and never driven. Transcribed outputs are held to the weakest drive
the part offers, so that a wrong pin number fights gently rather than hard.

Validated so far: the seven segment lines, the four digit commons, the reset
switch, one LED, and the middle button (pin 110, **active high**, measured with
`sw/btntest.s` — the board map had recorded the sense of all five buttons as
unknown).

---

## Module map

| File | Role |
|---|---|
| `Board_MachXO2.vhd` | **the only device-specific file**: the MachXO2 oscillator, and nothing else |
| `Top_Level_Unit.vhd` | portable top: power-on reset, CPU, display, LEDs, debug switch |
| `Central_Processing_Unit.vhd` | the multi-cycle FSM and the datapath wiring |
| `Control_Unit.vhd` | instruction decode into control signals |
| `Arithmetic_Logic_Unit.vhd` | structural ALU with flags |
| `Register_File.vhd` | 32 × 32-bit bank, two dual-port RAMs to get three ports |
| `Memory_System.vhd` | the modified-Harvard memory: two banks, one address space |
| `Program_Counter.vhd` | PC, built on `register_n` |
| `Peripherals.vhd` | memory-mapped display, buttons, LFSR, edge counter |
| `Display.vhd` | multiplexed 4-digit 7-segment driver, BCD in |
| `shifter_32.vhd` | barrel shifter, five stages of `mux2_n` and nothing else |
| `lfsr_32.vhd` | free-running 32-bit LFSR |
| `edge_counter.vhd` | measures an external period in local clocks |
| `Full_Adder.vhd`, `Full_Adder_1bit.vhd` | ripple-carry adder/subtractor |
| `primitives/` | the declared floor: `dff`, `mux2`, `mux2_n`, `register_n`, `ram_dp`, `power_on_reset` |
| `Top_Display_Test.vhd` | display bring-up, no processor at all |
| `LCD_Controller.vhd`, `Top_LCD_Test.vhd` | HD44780 driver, unused; kept for when a display is connected |
| `interfaz.vhd` | the original project's testbench; empty entity, kept |
| `legacy/` | the four modules `Memory_System` replaced, with a note on each |

Retargeting means writing a sibling of `Board_MachXO2.vhd`, not touching the
core.

---

## History

The processor was **never dead**, which is where this started. It looked dead
because the shipped program counted down from a hundred million at 24 Hz — about
a year and a half — with the display wired to the top thirteen bits of the
result bus, where a digit would change once every three days.

[DIAGNOSIS.md](DIAGNOSIS.md) documents every defect with measurements: the
`ready` signals that all led their data by one cycle, the three-times-per-pass
`SUB`, the self-locking FSMs, the 121 inferred latches, and the reset that was
never asserted.

Made with my soul - Swately <3
