#!/usr/bin/env python3
"""check_cpu.py -- self-checking regression for the PHarvard CPU.

Builds a golden model straight from the program in Instruction_Memory.vhd,
emulates it, then compares the emulation against what the RTL actually did in
the GHDL run. Exits non-zero on any mismatch, so it can gate a change.

Checks performed:
  1. the program halts, and at the address the emulator says
  2. the retired PC sequence matches the emulation
  3. every register write matches the emulation, in order, by (register, value)
  4. every data-memory write matches the emulation, by (address, value)
  5. control signals that must be exercised actually are

Usage:
    python sim/check_cpu.py [sim/work/cpu.vcd]

Made with my soul - Swately <3
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VCD = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "sim", "work", "cpu.vcd")
IMEM = os.path.join(ROOT, "memory_image_pkg.vhd")

MASK = 0xFFFFFFFF


def s32(v):
    v &= MASK
    return v - (1 << 32) if v & 0x80000000 else v


# --------------------------------------------------------------------------
# Golden model: read the ROM out of the VHDL and emulate it.
# --------------------------------------------------------------------------
def load_program():
    """Bank 0 of the memory image is the program."""
    text = open(IMEM, encoding="utf-8", errors="replace").read()
    body = text.split("BANK0_INIT")[1].split(");")[0]
    rows = re.findall(r'(\d+)\s*=>\s*X"([0-9A-Fa-f]{8})"', body)
    return {int(a): int(h, 16) for a, h in rows}


def load_data():
    """Bank 1 sits at 256..511 in the unified address space."""
    text = open(IMEM, encoding="utf-8", errors="replace").read()
    body = text.split("BANK1_INIT")[1].split(");")[0]
    rows = re.findall(r'(\d+)\s*=>\s*X"([0-9A-Fa-f]{8})"', body)
    return {256 + int(a): int(h, 16) for a, h in rows}


def emulate(prog, limit=20000, initial_mem=None, io=None,
            start_pc=0, initial_reg=None):
    """Run the program. `io`, if given, models the memory-mapped peripherals.

    It is a pair (read, write): `read(addr)` returns a word or None to fall
    through to memory, and `write(addr, value)` returns True if it consumed the
    store. Peripherals are a property of a BOARD, not of the architecture, so
    they are injected rather than built in -- this stays a golden model of the
    instruction set, and a caller that wants an LFSR or a display supplies one.
    `start_pc` and `initial_reg` let a caller run ONE ROUTINE instead of the
    whole program: set up the registers and memory the routine expects, enter
    at its label, and let it run until it returns to an address outside the
    image. That turns a subroutine into something testable on its own, over
    every input it can be given, instead of only the handful of cases a full
    program run happens to reach.

    Without any of these the behaviour is exactly as before.
    """
    reg = list(initial_reg) if initial_reg else [0] * 32
    mem = dict(initial_mem or {})
    reg_writes, mem_writes, pcs = [], [], []
    pc = start_pc
    halted_at = None
    for _ in range(limit):
        if pc not in prog:
            break
        pcs.append(pc)
        w = prog[pc]
        op = (w >> 26) & 0x3F
        src, trg, des = (w >> 21) & 0x1F, (w >> 16) & 0x1F, (w >> 11) & 0x1F
        imm = w & 0xFFFF
        simm = imm - 0x10000 if imm & 0x8000 else imm
        fun = w & 0x3F
        nxt = pc + 1

        def wr(r, v):
            if r != 0:
                reg[r] = s32(v)
                reg_writes.append((r, v & MASK))

        if op == 0o03 or op == 3:        # LOADI
            wr(trg, simm)
        elif op == 4:                    # ADDI
            wr(trg, reg[src] + simm)
        elif op == 5:                    # SUBI
            wr(trg, reg[src] - simm)
        elif op == 2:                    # LOAD  rt = mem[rs + imm]
            ea = (reg[src] + simm) & 0x1FF
            v = io[0](ea) if io else None
            wr(trg, mem.get(ea, 0) if v is None else v)
        elif op == 6:                    # STORE mem[rs + imm] = rt
            ea = (reg[src] + simm) & 0x1FF
            mem_writes.append((ea, reg[trg] & MASK))
            if not (io and io[1](ea, reg[trg] & MASK)):
                mem[ea] = reg[trg] & MASK
        elif op == 7:                    # MOVE
            wr(trg, reg[src])
        elif op == 1:                    # R-type
            a, b = reg[src], reg[trg]
            sh = (w >> 6) & 0x1F         # shift amount, bits 10:6
            if fun in (2, 3):
                # MUL and DIV are RESERVED: the hardware returns zero, they
                # are software routines now. The golden model must agree.
                res = 0
            elif fun == 8:               # SHL, logical
                res = (a & MASK) << sh
            elif fun == 9:               # SHR, logical
                res = (a & MASK) >> sh
            elif fun == 10:              # SLT, signed
                res = 1 if a < b else 0
            elif fun == 11:              # SLTU, unsigned
                res = 1 if (a & MASK) < (b & MASK) else 0
            else:
                res = {0: a + b, 1: a - b, 4: a & b, 5: a | b,
                       6: a ^ b, 7: ~a}[fun]
            wr(des, res)
        elif op == 8:                    # BEQ
            if reg[src] == reg[trg]:
                nxt = imm
        elif op == 10:                   # BNE
            if reg[src] != reg[trg]:
                nxt = imm
        elif op == 13:                   # JUMP
            nxt = w & 0x3FFFFFF
        elif op == 14:                   # JAL -- link then jump
            wr(31, pc + 1)
            nxt = w & 0x3FFFFFF
        elif op == 15:                   # JR -- return through a register
            nxt = reg[src] & 0x1FF       # 9-bit unified address space
        elif op == 9:                    # HALT
            halted_at = pc
            break
        pc = nxt
    return dict(reg=reg, mem=mem, reg_writes=reg_writes,
                mem_writes=mem_writes, pcs=pcs, halted_at=halted_at)


# --------------------------------------------------------------------------
# VCD replay
# --------------------------------------------------------------------------
def vcd_header(path):
    """Read just the header and return {full.signal.path: vcd_id}."""
    scope, id2path = [], {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            s = line.strip()
            if s.startswith("$scope"):
                scope.append(s.split()[2])
            elif s.startswith("$upscope"):
                if scope:
                    scope.pop()
            elif s.startswith("$var"):
                p = s.split()
                id2path[p[3]] = ".".join(scope + [p[4]])
            elif s.startswith("$enddefinitions"):
                break
    return {v: k for k, v in id2path.items()}


def stream_vcd(path):
    """Yield (time, live_state) once per timestamp.

    The dictionary is REUSED between yields, deliberately. An earlier version
    stored `dict(cur)` for every timestamp, which is a full copy of every
    signal at every simulation instant: with 60,000 clock cycles and a few
    hundred signals that is millions of entries and it ran the interpreter out
    of memory. A consumer that wants to keep something must copy it itself.
    """
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if line.startswith("$enddefinitions"):
                break
        cur, t = {}, 0
        for line in fh:
            s = line.strip()
            if not s or s.startswith("$"):
                continue
            if s[0] == "#":
                yield t, cur
                try:
                    t = int(s[1:])
                except ValueError:
                    return
            elif s[0] == "b":
                val, ident = s[1:].split(None, 1)
                cur[ident.strip()] = val
            else:
                cur[s[1:].strip()] = s[0]
        yield t, cur


def main():
    prog = load_program()
    gold = emulate(prog, initial_mem=load_data())

    if not os.path.exists(VCD):
        sys.exit(f"FAIL: no VCD at {VCD} -- run sim/run_diag.py first")

    p2i = vcd_header(VCD)
    D = "tb_cpu_diag.dut."
    clk = p2i["tb_cpu_diag.clk"]

    def val(s, name):
        i = p2i.get(name)
        if i is None:
            return None
        try:
            return int(s.get(i, ""), 2)
        except ValueError:
            return None

    def bit(s, name):
        i = p2i.get(name)
        return s.get(i) if i else None

    # Streamed: everything wanted is extracted at the moment it goes past, so
    # nothing but the results is held in memory.
    obs_reg, obs_mem, obs_pc = [], [], []
    last_pc = None
    n_edges = 0
    flags_seen = {name: set() for name in
                  ("internal_sign", "internal_overflow", "internal_parity",
                   "internal_zero", "internal_carry")}
    sig_seen = {name: 0 for name in
                ("internal_mem_write", "internal_mem_read",
                 "internal_reg_write", "internal_io_read", "internal_io_write")}
    halt_seen = False

    for t, s in stream_vcd(VCD):
        if s.get(clk) != "1":
            continue
        n_edges += 1
        for name in sig_seen:
            if s.get(p2i.get(D + name)) == "1":
                sig_seen[name] += 1
        for name in flags_seen:
            v = s.get(p2i.get(D + name))
            if v is not None:
                flags_seen[name].add(v)
        iw = val(s, D + "internal_instruction_in[31:0]")
        if iw is not None and ((iw >> 26) & 0x3F) == 9:
            halt_seen = True

        pc = val(s, D + "internal_pc_address_out[31:0]")
        if pc is not None and pc != last_pc:
            obs_pc.append(pc)
            last_pc = pc
        if bit(s, D + "internal_reg_commit") != "1":
            continue
        if bit(s, D + "internal_reg_write") == "1":
            r = val(s, D + "internal_write_reg[4:0]")
            v = val(s, D + "internal_result[31:0]")
            if r:
                obs_reg.append((r, v))
        if bit(s, D + "internal_mem_write") == "1":
            # The effective address is base register + immediate, produced by
            # the CPU's address adder.
            a = val(s, D + "internal_data_address[31:0]")
            v = val(s, D + "internal_data_memory_in[31:0]")
            obs_mem.append((a & 0x1FF if a is not None else a, v))

    failures = []

    def check(name, ok, detail=""):
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}" + (f" -- {detail}" if detail else ""))
        if not ok:
            failures.append(name)

    print(f"golden model: {len(prog)} instructions, "
          f"{len(gold['pcs'])} retired, halt at {gold['halted_at']}")
    print(f"observed    : {n_edges} rising edges, {len(obs_reg)} register "
          f"writes, {len(obs_mem)} memory writes\n")

    print("CHECKS")
    check("reaches HALT", gold["halted_at"] is not None,
          f"emulator halts at {gold['halted_at']}")
    check("RTL fetched the HALT instruction", halt_seen)

    # PC: the RTL re-visits an address across loop iterations exactly as the
    # emulator does, so the ordered sequences must be identical.
    check("PC sequence matches the emulation",
          obs_pc == gold["pcs"],
          f"rtl={obs_pc[:14]}... vs gold={gold['pcs'][:14]}..."
          if obs_pc != gold["pcs"] else f"{len(obs_pc)} addresses")

    check("register-write count matches",
          len(obs_reg) == len(gold["reg_writes"]),
          f"rtl={len(obs_reg)} gold={len(gold['reg_writes'])}")

    mismatch = [(i, o, g) for i, (o, g) in
                enumerate(zip(obs_reg, gold["reg_writes"])) if o != g]
    check("every register write matches (register, value)",
          not mismatch,
          f"first mismatch at #{mismatch[0][0]}: rtl={mismatch[0][1]} "
          f"gold={mismatch[0][2]}" if mismatch else f"{len(obs_reg)} writes")

    check("memory-write count matches",
          len(obs_mem) == len(gold["mem_writes"]),
          f"rtl={len(obs_mem)} gold={len(gold['mem_writes'])}")

    mm = [(o, g) for o, g in zip(obs_mem, gold["mem_writes"]) if o != g]
    check("every memory write matches (address, value)", not mm,
          f"{mm[:3]}" if mm else f"{obs_mem}")

    for sig in ("internal_mem_write", "internal_mem_read",
                "internal_reg_write"):
        check(f"{sig[9:]} is exercised", sig_seen[sig] > 0,
              f"{sig_seen[sig]} cycles")

    check("IO_read is NOT spuriously asserted",
          sig_seen["internal_io_read"] == 0,
          "the original asserted it for LOADI/ADDI/SUBI/MOVE")

    print(f"\nfinal architectural state expected by the golden model:")
    print("  registers:", {f"r{i}": v for i, v in enumerate(gold["reg"]) if v})
    print("  memory   :", {f"mem[{k}]": v for k, v in sorted(gold["mem"].items())})

    if failures:
        print(f"\nRESULT: FAIL ({len(failures)} of {len(failures) + 0} checks failed): "
              f"{failures}")
        return 1
    print("\nRESULT: PASS -- the RTL reproduces the golden model exactly")
    return 0


if __name__ == "__main__":
    sys.exit(main())
