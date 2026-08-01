#!/usr/bin/env python3
"""decode_ctrl.py -- decode the ISA tables straight out of the VHDL.

The control word is an 8-bit literal whose bit meaning is defined by the
concurrent assignments at the bottom of Control_Unit's architecture. Reading
those literals by eye is exactly how the LOADI/ADDI/SUBI/MOVE defect survived:
this script decodes each literal against the ACTUAL assignments and computes
the counts, so a claim like "no opcode asserts mem_write" comes from a command
rather than from looking at a listing.

It also cross-checks the two halves of the ALU contract: the opcodes the
control unit emits against the opcodes the ALU implements. A mismatch there is
how MUL and DIV were decoded for months into an ALU that did not have them.

Usage:
    python sim/decode_ctrl.py

Made with my soul - Swately <3
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CU = os.path.join(ROOT, "Control_Unit.vhd")
ALU = os.path.join(ROOT, "Arithmetic_Logic_Unit.vhd")

cu_text = open(CU, encoding="utf-8", errors="replace").read()
alu_text = open(ALU, encoding="utf-8", errors="replace").read()

# ---- bit map, from the concurrent assignments (the authority) -------------
assign = dict(re.findall(r"^\s*(\w+)\s*<=\s*internal_control_signals\((\d)\);",
                         cu_text, re.M))
bitmap = {int(b): sig for sig, b in assign.items()}
width = max(bitmap) + 1 if bitmap else 0

print("CONTROL WORD BIT MAP (from the concurrent assignments):")
for b in sorted(bitmap, reverse=True):
    print(f"  bit {b} -> {bitmap[b]}")

# ---- opcode -> control word ---------------------------------------------
body = cu_text.split("when decode2 =>")[1].split("when decode3 =>")[0]
rows = re.findall(
    r'when "(\d{6})"\s*=>\s*internal_control_signals\s*<=\s*"([01]+)";\s*(?:--\s*([^\n]*))?',
    body)

print(f"\nDECODED CONTROL TABLE ({len(rows)} opcodes):")
counts = {name: 0 for name in bitmap.values()}
for op, lit, comment in rows:
    active = [bitmap[len(lit) - 1 - i] for i, ch in enumerate(lit)
              if ch == "1" and (len(lit) - 1 - i) in bitmap]
    for a in active:
        counts[a] += 1
    name = (comment or "").split(":")[0].strip()
    print(f"  {op}  {name:<14} {lit} -> "
          f"{', '.join(active) if active else '(none)'}")

print("\nCOMPUTED counts over all opcodes:")
for name in sorted(counts):
    print(f"  {name:<12} asserted by {counts[name]} of {len(rows)}")

# ---- ALU contract: emitted vs implemented --------------------------------
# The ALU names its opcodes as constants and selects on them.
alu_consts = dict(re.findall(
    r'constant\s+(OP_\w+)\s*:\s*std_logic_vector\(3 downto 0\)\s*:=\s*"(\d{4})";',
    alu_text))
implemented = set(alu_consts.values())
name_of = {v: k for k, v in alu_consts.items()}

emitted = set(re.findall(r'internal_alu_opcode <= "(\d{4})";', cu_text))
reserved = set(re.findall(
    r'internal_alu_opcode <= "(\d{4})";\s*--[^\n]*reserved', cu_text, re.I))

print(f"\nALU OPCODES")
print(f"  implemented by the ALU ({len(implemented)}): "
      + ", ".join(f"{c}={name_of[c][3:]}" for c in sorted(implemented)))
print(f"  emitted by the CU      ({len(emitted)}): {sorted(emitted)}")
gap = sorted(emitted - implemented - reserved)
print(f"  EMITTED BUT NOT IMPLEMENTED: {gap if gap else 'none'}")
if reserved:
    print(f"  deliberately reserved (hardware returns zero): {sorted(reserved)}")

# ---- R-type function codes ----------------------------------------------
fn_body = cu_text.split("when decode_alu =>")[1].split("when others =>\n\t\t\t\t\tnull;")[0]
fns = re.findall(r'when "(\d{6})" => internal_alu_opcode <= "(\d{4})";\s*--\s*([^\n]*)',
                 fn_body)
print(f"\nR-TYPE FUNCTION CODES ({len(fns)}):")
for f, aop, cmt in fns:
    print(f"  func {f} -> alu {aop}  {cmt.strip()}")
