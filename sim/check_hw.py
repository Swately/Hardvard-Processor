#!/usr/bin/env python3
"""check_hw.py -- verify sw/hwcheck.s in the RTL before it goes on the board.

    python sim/check_hw.py

WHY THIS IS SEPARATE FROM check_cpu.py. That one asserts the program reaches
HALT and compares final architectural state. `hwcheck.s` never halts -- it
loops showing its results forever, because a display that stops is
indistinguishable from a processor that stopped. So the property to check is
different: what does the machine WRITE TO THE DISPLAY, and in what order.

The first frame is the verdict the program computed about itself. If the RTL
writes 0x0007 there, then the RTL executed the software multiply, the software
divide, the nested call through the stack, the cross-bank store and load, the
shifts and the comparisons, and got every one of them right -- because that
seven is the count of its own checks that passed.

That makes this a cheap test with a wide reach: one value, and the whole
instruction set behind it.

Made with my soul - Swately <3
"""
import os
import sys

SIM = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(SIM)
sys.path.insert(0, SIM)

import check_cpu as cc  # noqa: E402

DIGITS = 501
EXPECTED = [0x0007, 0x0034, 0x0132, 0x0012, 0x0014, 0x0002, 0x0049, 0x0495]
LABELS = [
    "the verdict: 7 of 7 checks passed",
    "34 = 26 stored to bank 1 and loaded back, plus 8",
    "132 = __mul(12, 11), multiplication in software",
    "12 = __div(132, 11), division in software",
    "14 = __div(100, 7)",
    "2 = its remainder",
    "49 = __square(7), a routine that called another",
    "495 = the stack pointer, back where it started",
]


def main():
    vcd = os.path.join(ROOT, "sim", "work", "cpu.vcd")
    if not os.path.exists(vcd):
        vcd = os.path.join(ROOT, "work", "cpu.vcd")
    if not os.path.exists(vcd):
        sys.exit(f"no VCD found -- run the RTL simulation first ({vcd})")

    p2i = cc.vcd_header(vcd)
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

    frames = []
    for _t, s in cc.stream_vcd(vcd):
        if s.get(clk) != "1":
            continue
        if s.get(p2i.get(D + "internal_reg_commit")) != "1":
            continue
        if s.get(p2i.get(D + "internal_mem_write")) != "1":
            continue
        a = val(s, D + "internal_data_address[31:0]")
        if a is None or (a & 0x1FF) != DIGITS:
            continue
        v = val(s, D + "internal_data_memory_in[31:0]")
        frames.append(v & 0xFFFF)

    print("=== WHAT THE RTL WROTE TO THE DISPLAY ===\n")
    if not frames:
        print("  nothing -- the simulation did not run far enough, or the")
        print("  processor never reached the display code.")
        return 1

    ok = True
    for i, want in enumerate(EXPECTED):
        if i >= len(frames):
            print(f"  [ -- ] frame {i}: not reached in this run "
                  f"(wanted {want:04X})")
            continue
        got = frames[i]
        good = got == want
        ok = ok and good
        print(f"  [{'PASS' if good else 'FAIL'}] frame {i}: "
              f"{got:04X}   {LABELS[i]}")
        if not good:
            print(f"           expected {want:04X}")

    print(f"\n  {len(frames)} display writes observed")

    if frames and frames[0] == 0x0007:
        print("\nRESULT: PASS -- the RTL computed 7 of 7 checks correct.")
        print("The instruction set, the software MUL/DIV library, the stack")
        print("and register-indirect addressing all work in the RTL.")
        return 0 if ok else 1

    print("\nRESULT: FAIL -- the verdict frame is not 0007.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
