# Context brief: the PHarvard randomness engine

> **Purpose.** Hand-off for an external session analysing a proposed replacement
> randomness engine for this processor. It assumes no access to the
> conversation this project was built in.
> **Status:** `measured` where numbers are given, and every unmeasured claim is
> labelled. **Date:** 2026-08-01.
> **Read this first, then `../README.md` and `../primitives/PRIMITIVES.md`.**

---

## §1. What the machine is

PHarvard is a 32-bit **modified-Harvard** processor written in VHDL, running in
simulation and targeted at a **Lattice MachXO2-7000HE** FPGA (TQFP-144). It is
an academic rebuild: the operator wrote the original for a university course,
had to abandon it at the deadline, and is now finishing it properly.

- **Instruction encoding is MIPS's** — R-type with `shamt`/`funct`, I-type with
  a 16-bit immediate, J-type with a 26-bit address.
- **Memory organisation is modified Harvard** — separate instruction and data
  buses over ONE unified 512-word address space, two banks of 256, each a true
  dual-port RAM. Either bank holds code or data; code space is writable.
- Peripherals are **memory-mapped** at the top 16 words (`0x1F0`–`0x1FF`);
  there is no I/O instruction.

## §2. The design philosophy, which constrains any proposal

This is the part an outside proposal most often violates, so it comes early.

**The VHDL is meant to read as a schematic, not as a request to the
synthesiser.** The processor is built structurally from a declared floor of
primitives, and blocks are composed upward. The operator's explicit goal is to
design the architecture "without VHDL's help" — writing `a * b` and letting the
tool invent a multiplier is precisely what this project does not do.

**The irreducible floor** (`primitives/PRIMITIVES.md`):

| Primitive | Why it cannot go lower |
|---|---|
| boolean operators on `std_logic` | one operator is one gate |
| `dff` (D flip-flop) | cross-coupled NANDs are a combinational loop; a synthesiser rejects it |
| memory arrays | must reach block RAM to be usable; block RAM is a vendor macro |

Consequences for a randomness proposal:

- A block described behaviourally, or one that leans on a vendor IP core, will
  not be accepted as it stands.
- **Anything relying on analogue behaviour, uninitialised state, glitches,
  metastability or combinational loops is outside what this flow can describe
  or verify.** A synthesiser will optimise a combinational loop away or refuse
  it; simulation cannot model jitter at all. This does not make such designs
  wrong — it means they cannot be evaluated by the evidence this project
  produces, and would need real silicon.

## §3. Hard constraints, measured

**REVISED 2026-08-01, and the revision matters.** An earlier version of this
document put the headroom at "~370 LUT4, about 5%" and called it the binding
constraint. That figure came from an open-source estimator. The real Lattice
toolchain has since been run on the same design, and the estimator was **about
2.2x pessimistic** — worse on arithmetic-heavy versions. Anyone who designed
against the old number was designing against a phantom.

Vendor flow, `Synplify + Lattice map/par/trce`, `Board_MachXO2` at 2.08 MHz:

| Quantity | Value | How obtained |
|---|---|---|
| LUT4 | **1,092 of 6,864 (16 %)** | vendor map report |
| SLICEs | 695 of 3,432 (20 %) | vendor map report |
| Registers | 443 of 7,209 (6 %) | vendor map report |
| **Block RAM** | **12 of 26 (46 %)** | vendor map report |
| I/O | 37 + 4 JTAG of 115 (36 %) | vendor map report |
| **Post-route Fmax** | **21.137 MHz, 0 timing errors** | vendor `trce` |
| Clock in use | 2.08 MHz | MachXO2 internal oscillator |
| Cycles per instruction | **20.3** | measured over a full program run |
| Instruction throughput | ~102,000 /s | derived |

**The binding resource is BLOCK RAM, not logic.** ~5,700 LUT4 are free; only
14 of 26 EBR blocks are. A proposal that needs memory is the one that runs into
a wall here, and a proposal that needs a few hundred LUT4 has room to spare.

Reproduce with `python syn/build_vendor.py`. Do **not** quote
`syn/estimate_area.py`; see `syn/VENDOR_VS_ESTIMATE.md` for why.

**Also now measured:** timing. The design closes at 21 MHz and runs at 2.08,
so there is roughly 10x of timing margin. A proposal is not going to fail here
for being one gate deeper.

**Still not measured:** anything on real silicon. A flashable `.jed` now exists
(`syn/vendor/PHarvard_current.jed`) but nothing has been flashed, and several
pin assignments are transcribed from photographs and never exercised.

## §4. What is there now

Three layers.

### 4.1 Hardware — `lfsr_32.vhd`

A free-running 32-bit Fibonacci LFSR. The entire generator:

```vhdl
feedback <= state(31) xor state(21) xor state(1) xor state(0);
next_val <= state(30 downto 0) & feedback;
```

plus one `register_n` (32 `dff` cells), clock-enabled permanently on. Taps
32/22/2/1 give a maximal-length sequence over the 2^32 − 1 non-zero states; the
all-zero state is an absorbing fixed point, so reset seeds it with all ones.

Cost by construction: 32 flip-flops and 3 XOR gates. (This was not isolated in
a synthesis run of its own — the measured 420 LUT4 that the peripheral block
added covers the LCD controller and this together.)

### 4.2 Bus — `Peripherals.vhd`

Exposed read-only at address **500**, alongside `LCD_CMD` (496), `LCD_DATA`
(497), `LCD_STATUS` (498) and `BUTTONS` (499). Reads are registered to match
the memory's one-cycle latency.

### 4.3 Software — `sw/slots.s`, routine `next_symbol`

```asm
next_symbol:
        push  ra
        load  r4, RANDOM      ; sample the free-running LFSR
        loadi r5, 8
        jal   __div           ; r7 = remainder
        move  r6, r7          ; the remainder IS the symbol
```

`random mod 8`, where the modulo is a subroutine call because the machine has
no divide instruction — multiplication and division were removed from hardware
and rebuilt as software routines, because building complex operations from
simple ones is this project's purpose. (An area figure quoted here earlier came
from an open-source estimator and was about 8x too large; it is corrected in
syn/VENDOR_VS_ESTIMATE.md and was never the reason for the decision.)

### 4.4 Where the entropy actually comes from

**Not from the LFSR.** The LFSR is fully deterministic: same seed, same
sequence, and it is reset to the same value at every power-up.

The entropy is the **arrival time of a human button press** against a counter
advancing at 2.08 MHz. The CPU spins in `wait_button`; whatever state the LFSR
happens to be in when the press is observed becomes the sample. A millisecond
of variation in a finger is about 2,000 distinct states.

This is the classic slot-machine construction and it is honest about its source
— but it means:

- with the button driven at exactly reproducible times from reset, the machine
  is fully deterministic;
- press timing is quantised to the polling loop (~100 cycles), a negligible
  loss against 2^32 states;
- an LFSR is **not cryptographic**: 32 bits of output reveal the entire state
  and all future output.

## §5. Statistical behaviour, measured

A concern was raised and then tested rather than assumed. **The three reels are
read back to back at a deterministic interval** (~7,550 cycles, the time
`__div` takes), so reels 2 and 3 are a deterministic function of reel 1. That
should have made the joint distribution degenerate.

Measured, by simulating the exact tap polynomial in Python (20,000 trials):

| | measured | fair dice |
|---|---|---|
| distinct triples observed | **512 of 512** | 512 |
| three of a kind | 1.37 % | 1.56 % |
| exactly a pair | 32.27 % | 32.81 % |

Robust across read gaps of 137, 1,000, 7,000, 7,550 and 8,000 cycles. Per-cell
spread (22..59 against an ideal 39) is consistent with multinomial sampling
noise at n = 20,000 over 512 cells, not with bias.

The LFSR alone, sampled every cycle and taken mod 8 over 200,000 samples,
deviates 2 %.

**Why the concern did not materialise:** advancing an LFSR is a bijective
linear map over GF(2), so the low three bits at three different offsets are
three independent linear forms of the state.

**What was NOT done:** no NIST STS, no Dieharder, no TestU01. The tests above
are the specific ones that matter for this application, not a general
randomness qualification.

## §6. Prior art, so it is not re-derived

Offered as orientation, **not as verified citations** — any specific reference
must be checked first-hand before being relied on.

- **LFSRs and maximal-length sequences** are textbook material (Golomb;
  Fibonacci and Galois forms are equivalent up to state relabelling). A new tap
  set or a new LFSR arrangement is essentially certain not to be novel.
- **FPGA true-RNG** is a mature field with several established families: ring
  oscillators harvesting jitter, TERO (transition-effect ring oscillator),
  PLL-based sampling, and metastability harvesting. All are well published.
- **Entropy-source validation** has formal standards: **NIST SP 800-90B** and
  the BSI **AIS-31** methodology. A claim about entropy quality that does not
  engage with one of these will not be taken seriously.
- **Statistical test batteries**: NIST STS, Dieharder, and TestU01 (BigCrush is
  the demanding one). Passing STS alone is a weak result; failing BigCrush is a
  strong negative.

**The honest bar.** Novelty in this area is not "a generator that produces
random-looking numbers" — it is a measured entropy claim under a recognised
methodology, or a demonstrated advantage (area, throughput, entropy per bit,
robustness to temperature/voltage) against a named published baseline on
comparable hardware. Building a working RNG is a fine engineering and teaching
result on its own; that is a different claim from a publishable one, and
conflating them is the failure mode to avoid.

## §7. What this project can and cannot prove about a proposal

**Can:**

- that it is synthesisable and latch-free (`ghdl --synth` runs as a gate in
  `sim/run_diag.py`);
- what it costs in LUT4 and flip-flops (`syn/estimate_area.py`);
- its statistical behaviour under a deterministic simulation model;
- that the processor can consume it, end to end, in a real program.

**Cannot:**

- anything about physical entropy, jitter, metastability or temperature —
  simulation is deterministic by construction;
- Fmax or timing closure — never measured here;
- behaviour on silicon — nothing has been flashed.

A proposal whose value rests on physical randomness therefore **cannot be
evaluated by this project's evidence at all**, and would need hardware plus an
SP 800-90B-style entropy assessment. That is worth knowing before effort is
spent.

## §8. Verification infrastructure available

| Command | What it proves |
|---|---|
| `python sim/run_diag.py` | assembles, analyses 23 files, runs the synthesis gate, and checks the RTL against a golden model built from the program itself |
| `python sim/run_slots.py` | plays the slot machine and prints the 16x2 screen the processor drove |
| `python syn/estimate_area.py` | LUT4/FF estimate via GHDL + yosys |
| `python tools/pasm.py` | assembler, so test programs are writable |

Tooling: GHDL 6.0.0 (mcode), yosys 0.66 (yowasp), Lattice Diamond installed but
its headless TCL console would not run from the automation environment.

## §9. Questions worth answering about any proposal

1. What is the entropy source, physically, and can this flow observe it?
2. What does it cost in LUT4 against the **~370 available**?
3. What does it need that the primitive floor does not provide?
4. What is the named baseline it claims to beat, and on what axis?
5. What test battery, at what sample size, and what were the failures?
6. Does it survive being wrong — i.e. what does the machine do if the source
   degrades or stops?

Made with my soul - Swately <3
