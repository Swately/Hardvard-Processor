# The open-source estimate against the vendor flow

> **Status:** `measured` (2026-08-01). Both columns are real runs on this
> machine, on the same source.
> **Why this file exists:** the estimate was quoted as if it were a fitting
> result. It is not, and the gap is large enough to have changed decisions.

---

## The numbers

Same design, same day, `Board_MachXO2` at 2.08 MHz.

| | `syn/estimate_area.py` (GHDL + yosys) | **`syn/build_vendor.py` (Synplify + Lattice map)** |
|---|---|---|
| LUT4 | 2,354 | **1,092** |
| as a fraction of a MachXO2-7000HE | 34 % | **16 %** |
| registers | ~443 | 443 |
| block RAM | not modelled | **12 of 26 (46 %)** |
| post-route Fmax | not measurable | **21.137 MHz, 0 timing errors** |

**Current design, measured 2026-08-01 after the silicon bring-up** (the same
flow, now including the power-on reset and the debug readout): **1,402 LUT4
(20 %)**, 625 registers (9 %), 12 of 26 block RAMs (46 %), post-route Fmax
**21.744 MHz**, zero timing errors. This is the configuration that executes on
the board.

**The estimate is about 2.2x pessimistic here.** On the older design — the one
that still had a combinational 32x32 multiplier and 32-bit divider in the ALU —
it was worse: the estimate said 20,442 LUT4 where Synplify's own report showed
2,613 LUT4 plus 1,706 carry cells. Roughly **8x** on that design.

## Why the gap, and why it is not constant

Two things the open-source mapping cannot do:

1. **Hardened carry chains.** `flowmap -maxlut 4` builds adders out of LUTs.
   The part has dedicated carry logic (`CCU2D`), and Synplify uses it. Anything
   arithmetic-heavy is therefore over-counted by the estimate, which is exactly
   why the multiplier and divider looked catastrophic and were not.
2. **Memory inference.** yosys left the register file as logic — 5,313 cells.
   Synplify put the memories in EBR block RAM (`DP8KC`, `PDPW8KC`) and the
   register file in distributed RAM, which is why block RAM shows up as the
   binding resource in the real report and does not appear in the estimate at
   all.

So the error is **not a fixed factor**. It scales with how much of the design
is arithmetic and storage. Multiplying an estimate by a constant to "correct"
it would be a worse mistake than quoting it raw.

## What this changed

The area argument for removing the hardware multiplier and divider was
**overstated**. "14,899 LUT4, 73 % of the core" was true under one mapper and
is not a vendor figure; the same blocks cost far less on the real part.

The decisions themselves still stand, for reasons that were never about area:

- **MUL and DIV as software routines** — the point was building complex
  instructions from simple ones, which is the project's whole purpose. That
  argument is untouched.
- **The register file in RAM** — a vendor tool infers this anyway, but stating
  it explicitly means the design does not depend on a particular tool guessing
  right. It is also what `primitives/PRIMITIVES.md` already declared.
- **BCD conversion in software** — same reasoning as MUL/DIV, and it removed
  four combinational dividers whose cost was real even if smaller than
  estimated.

What genuinely was wrong: the claim that the design **did not fit**. It did.
`Top_Level_Unit` was reported at 132 % of the part by the estimate; the vendor
flow puts the whole board design at **16 %**.

## The other thing the vendor flow confirmed

The old design's Synplify report carries a line the new one does not:

```
Latch bits: 121
```

121 inferred latches, independently confirmed by the vendor tool — the same
defect `ghdl --synth` reported and that was fixed across the control unit and
all three address registers. The current report has no such line at all.

That part of the work needed no correction. The synthesis gate found something
real, and a second, unrelated tool agrees.

## A build can also measure the wrong design entirely

Worth more than the estimator gap, and found the same week. `power_on_reset.vhd`
was written and instantiated, and the rebuild reported **byte-identical**
utilisation to the run before it — 1,377 LUT4, 608 registers. Adding a 16-bit
counter cannot leave area unchanged.

The file was missing from `syn/synplify_current.tcl`. Synplify never saw it,
and the build **succeeded**, producing a bitstream of the previous design. The
only thing that caught it was reading the numbers.

`build_vendor.py` and `sim/run_diag.py` now both cross-check the sources on
disk against their file lists and refuse to run when one is unaccounted for.
An area figure from a build that can silently skip a file is attached to an
unknown design, which makes it worse than no figure at all.

## How to use each

- **`build_vendor.py`** for any number that will be written down, quoted, or
  put in a paper. It is the actual toolchain for the actual part.
- **`estimate_area.py`** to compare two configurations of the same design
  against each other, quickly, without a vendor licence. Its output is a
  ranking, not a measurement.

Made with my soul - Swately <3
