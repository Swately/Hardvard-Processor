#!/usr/bin/env python3
"""diag_vcd.py -- instruction-level trace extractor for the PHarvard CPU.

Reads the VCD produced by tb_cpu_diag and reports what the processor
ACTUALLY did: the retired-instruction sequence, the steady-state loop period,
the register writes it performed, and what the 7-segment display would show.
Used to MEASURE the failure instead of inferring it from the source.

Time handling: the VCD $timescale is read from the header (GHDL emits 1 fs by
default), never assumed -- an earlier version of this script hard-coded the
unit and produced figures 1000x too large.

Usage:
    python sim/diag_vcd.py [sim/work/cpu.vcd]

Made with my soul - Swately <3
"""
import sys

VCD = sys.argv[1] if len(sys.argv) > 1 else r"sim/work/cpu.vcd"

TB_CLK_PERIOD_NS = 10.0     # tb_cpu_diag drives clk with a 10 ns period
HW_CLK_HZ = 24.0            # Top_Level_Unit feeds the CPU Clock's CLK_24Hz

OPCODES = {
    "000001": "ALU", "000010": "LOAD", "000011": "LOADI", "000100": "ADDI",
    "000101": "SUBI", "000111": "MOVE", "001000": "BEQ", "001001": "HALT",
    "001010": "BNE", "001011": "STORE_IO", "001100": "NOP",
}
FUNCS = {
    "000000": "ADD", "000001": "SUB", "000010": "MUL", "000011": "DIV",
    "000100": "AND", "000101": "OR", "000110": "XOR", "000111": "NOT",
}
UNIT_NS = {"s": 1e9, "ms": 1e6, "us": 1e3, "ns": 1.0,
           "ps": 1e-3, "fs": 1e-6}


def parse(path):
    """Return (path->id map, [(time_ns, snapshot)], timescale_ns)."""
    scope, id2path, ts_ns = [], {}, 1e-6
    lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    end = 0
    for i, line in enumerate(lines):
        s = line.strip()
        if s.startswith("$timescale"):
            # the magnitude+unit may sit on this line or the next
            blob = " ".join(lines[i:i + 3]).replace("$timescale", "")
            blob = blob.replace("$end", "").split()
            mag = float(blob[0]) if blob and blob[0][0].isdigit() else 1.0
            unit = next((u for u in blob if u in UNIT_NS), "fs")
            ts_ns = mag * UNIT_NS[unit]
        elif s.startswith("$scope"):
            scope.append(s.split()[2])
        elif s.startswith("$upscope"):
            if scope:
                scope.pop()
        elif s.startswith("$var"):
            p = s.split()
            id2path[p[3]] = ".".join(scope + [p[4]])
        elif s.startswith("$enddefinitions"):
            end = i
            break
    path2id = {v: k for k, v in id2path.items()}

    timeline, cur, t = [], {}, 0
    for line in lines[end + 1:]:
        s = line.strip()
        if not s or s.startswith("$"):
            continue
        if s[0] == "#":
            timeline.append((t * ts_ns, dict(cur)))
            t = int(s[1:])
        elif s[0] == "b":
            val, ident = s[1:].split(None, 1)
            cur[ident.strip()] = val
        else:
            cur[s[1:].strip()] = s[0]
    timeline.append((t * ts_ns, dict(cur)))
    return path2id, timeline, ts_ns


path2id, timeline, ts_ns = parse(VCD)
D = "tb_cpu_diag.dut."


def sig(snap, name):
    ident = path2id.get(name)
    return snap.get(ident) if ident else None


def num(snap, name):
    try:
        return int(sig(snap, name), 2)
    except (TypeError, ValueError):
        return None


clk = path2id["tb_cpu_diag.clk"]
edges = [(t, s) for t, s in timeline if s.get(clk) == "1"]
print(f"VCD timescale: {ts_ns} ns per tick")
print(f"rising edges observed: {len(edges)}   window: "
      f"{edges[0][0]:.0f}..{edges[-1][0]:.0f} ns "
      f"({(edges[-1][0]-edges[0][0])/TB_CLK_PERIOD_NS:.0f} clock cycles)\n")

# --- retired-instruction trace -------------------------------------------
print("INSTRUCTION-LEVEL TRACE")
print(f"{'ns':>8} {'pc':>4} {'instr':>9} {'op':>9} {'func':>5} "
      f"{'wreg':>5} {'result':>9} {'rd1':>9} {'rd2':>9}")
print("-" * 76)

prev_key, rows = None, []
for t, s in edges:
    instr = sig(s, D + "internal_instruction_in[31:0]")
    pc = num(s, D + "internal_pc_address_out[31:0]")
    if instr is None or pc is None:
        continue
    key = (pc, instr)
    if key == prev_key:
        continue
    prev_key = key
    iw = int(instr, 2)
    op, fn = format(iw >> 26, "06b"), format(iw & 0x3F, "06b")
    rows.append((t, pc, iw, op))
    if len(rows) <= 30:
        print(f"{t:>8.0f} {pc:>4} {iw:>9x} {OPCODES.get(op, op):>9} "
              f"{FUNCS.get(fn, '') if op == '000001' else '':>5} "
              f"{num(s, D+'internal_write_reg[4:0]'):>5} "
              f"{num(s, D+'internal_result[31:0]'):>9x} "
              f"{num(s, D+'internal_reg_data1[31:0]'):>9x} "
              f"{num(s, D+'internal_reg_data2[31:0]'):>9x}")
if len(rows) > 30:
    print(f"... ({len(rows) - 30} more transitions)")

print(f"\nPC sequence: {[r[1] for r in rows]}")

# --- control signals actually exercised -----------------------------------
print()
for name in ("internal_mem_write", "internal_mem_read", "internal_reg_write",
             "internal_io_read", "internal_io_write"):
    n = sum(1 for _, s in edges if sig(s, D + name) == "1")
    print(f"edges with {name[9:]:<12}=1 : {n:>4} / {len(edges)}")

for f in ("internal_sign", "internal_overflow", "internal_parity",
          "internal_zero", "internal_carry"):
    vals = sorted({sig(s, D + f) for _, s in edges} - {None})
    print(f"{f:<20} distinct values: {vals}")

# --- steady-state loop measurement ---------------------------------------
SUB_WORD = 0x4671801          # instruction 3 of the ROM: SUB r3,r7 -> r3
marks, prev_pc = [], None
for t, s in edges:
    pc = num(s, D + "internal_pc_address_out[31:0]")
    if pc == 4 and num(s, D + "internal_instruction_in[31:0]") == SUB_WORD \
            and pc != prev_pc:
        marks.append((t, num(s, D + "internal_result[31:0]")))
    prev_pc = pc

if len(marks) >= 3:
    periods = [round((marks[i+1][0] - marks[i][0]) / TB_CLK_PERIOD_NS)
               for i in range(len(marks) - 1)]
    drops = [marks[i][1] - marks[i+1][1] for i in range(len(marks) - 1)]
    P, DEC = periods[0], drops[0]
    print(f"\nSTEADY-STATE LOOP (n={len(periods)} passes)")
    print(f"  period in clock cycles : {periods} constant={len(set(periods))==1}")
    print(f"  r3 decrement per pass  : {drops} constant={len(set(drops))==1}")
    print(f"  => {P} cycles per pass, {DEC} decrements per pass "
          f"({P/DEC:.2f} cycles per unit)")
    if DEC == 1:
        print("  1 decrement per pass is what the program intends: the "
              "re-execution defect is gone")
    else:
        print(f"  the program intends 1 decrement per pass; the extra "
              f"{DEC-1} are a defect")

    # The wall-clock arithmetic below only means anything for the ORIGINAL
    # program, whose loop counter starts at Data_Memory[9] = 0x05F5E100. The
    # repaired demo program counts down from 10 and reaching that figure takes
    # no time at all, so printing 100-million-based numbers against it would be
    # a stale, misleading result rather than a measurement.
    START = max(v for _, v in marks) if marks else 0
    ORIGINAL_START = 0x05F5E100
    if START >= ORIGINAL_START - 16:
        total_cyc = ORIGINAL_START * (P / DEC)
        secs = total_cyc / HW_CLK_HZ
        print(f"\nWALL-CLOCK ON HARDWARE (CPU clocked at {HW_CLK_HZ:.0f} Hz, "
              f"r3 starts at {ORIGINAL_START:,})")
        print(f"  cycles to drain the loop : {total_cyc:,.0f}")
        print(f"  = {secs:,.0f} s = {secs/86400:,.0f} days "
              f"= {secs/31557600:,.1f} years")

        step = 2 ** 19
        s_dig = step * (P / DEC) / HW_CLK_HZ
        print(f"\nDISPLAY -- if Top_Level_Unit still wired "
              f"alu_result(31 downto 19)")
        print(f"  it would show {(ORIGINAL_START >> 19) & 0x1FFF} and need r3 to "
              f"fall {step:,} before ANY digit moves")
        print(f"  = one visible change every {s_dig:,.0f} s "
              f"= {s_dig/3600:,.1f} h = {s_dig/86400:,.1f} days")
        print(f"  wired to bits (12 downto 0) it changes every "
              f"{(P/DEC)/HW_CLK_HZ:,.2f} s")
    else:
        secs = START * (P / DEC) / HW_CLK_HZ
        print(f"\nWALL-CLOCK ON HARDWARE (CPU clocked at {HW_CLK_HZ:.0f} Hz)")
        print(f"  loop counter starts at {START} -> drains in "
              f"{START * (P/DEC):,.0f} cycles = {secs:,.2f} s")
        print("  (the 100-million-iteration figures in DIAGNOSIS.md apply to "
              "the ORIGINAL program, not this one)")
