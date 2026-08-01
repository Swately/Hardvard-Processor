#!/usr/bin/env python3
"""pasm.py -- assembler for the PHarvard instruction set.

Turns readable assembly into the VHDL memory image the processor boots from.
Until now the ROM was hand-encoded hexadecimal with the assembly written in a
comment beside it, which is fine for twenty instructions and hopeless for a
library.

    python tools/pasm.py sw/demo.s -o memory_image_pkg.vhd

Two passes: the first records where every label lands, the second emits words.

SYNTAX
    label:                  defines a label at the current address
    ; comment               to end of line (# also works)
    .bank 0|1               select which bank the following code assembles into
    .org N                  set the address within the current bank
    .word v, v, ...         emit literal words
    .equ NAME, value        define a constant usable anywhere a number is

REGISTERS
    r0 .. r31, and r0 always reads zero. The link register r31 has the alias
    `ra`, matching the MIPS convention this encoding comes from.

INSTRUCTIONS                                            format
    add  rd, rs, rt         rd = rs + rt                R
    sub  rd, rs, rt         rd = rs - rt                R
    and/or/xor rd, rs, rt                               R
    not  rd, rs             rd = ~rs                    R
    shl  rd, rs, n          rd = rs << n   (n = 0..31)  R, uses shamt
    shr  rd, rs, n          rd = rs >> n   (logical)    R, uses shamt
    slt  rd, rs, rt         rd = (rs < rt)  signed      R
    sltu rd, rs, rt         rd = (rs < rt)  unsigned    R
    load  rt, addr          rt = mem[addr]              I
    load  rt, off(rs)       rt = mem[rs + off]          I
    store rt, addr          mem[addr] = rt              I
    store rt, off(rs)       mem[rs + off] = rt          I

    The address is always BASE + OFFSET; writing it without a base means base
    r0, which reads zero, so the absolute form is a special case of the
    indirect one rather than a separate instruction.

    push rs / pop rd        stack through sp (r29), grows downward
    call label              jal, but saves ra so routines can NEST
    ret                     the matching return
    loadi rt, imm           rt = imm                    I
    addi  rt, rs, imm       rt = rs + imm               I
    subi  rt, rs, imm       rt = rs - imm               I
    move  rt, rs            rt = rs                     I
    beq  rs, rt, label      branch if equal             I
    bne  rs, rt, label      branch if not equal         I
    jump label                                          J
    jal  label              r31 = pc+1, then jump       J
    jr   rs                 pc = rs                     R-ish
    nop / halt

PSEUDO-INSTRUCTIONS
    mul rd, rs, rt          call __mul
    div rd, rs, rt          call __div   (quotient)
    mod rd, rs, rt          call __div   (remainder)

    These expand to a calling sequence, they are not hardware. They CLOBBER
    r4, r5, r6, r7 and r31, and they need the routine to be linked in. That is
    stated loudly because a pseudo-instruction that silently destroys registers
    is a trap; RISC-V toolchains do exactly this expansion for RV32I without
    the M extension.

Made with my soul - Swately <3
"""
import argparse
import os
import re
import sys

MASK32 = 0xFFFFFFFF

OPC = {
    "alu": 0o01, "load": 0o02, "loadi": 0o03, "addi": 0o04, "subi": 0o05,
    "store": 0o06, "move": 0o07, "beq": 0o10, "halt": 0o11, "bne": 0o12,
    "store_io": 0o13, "nop": 0o14, "jump": 0o15, "jal": 0o16, "jr": 0o17,
}
FUNC = {
    "add": 0, "sub": 1, "and": 4, "or": 5, "xor": 6, "not": 7,
    "shl": 8, "shr": 9, "slt": 10, "sltu": 11,
}
# Calling convention for the software routines.
ARG0, ARG1, RET0, RET1, LINK = 4, 5, 6, 7, 31

# How many words each pseudo-instruction expands to. Keep in step with
# Assembler.encode -- a mismatch here silently shifts every later label.
PSEUDO_SIZE = {"push": 2, "pop": 2, "call": 5, "ret": 1,
               "mul": 4, "div": 4, "mod": 4}


class AsmError(Exception):
    pass


SP = 29         # stack pointer, MIPS's $sp number

REG_ALIAS = {"ra": LINK, "sp": SP, "zero": 0}


def reg(tok, where):
    t = tok.strip().lower()
    if t in REG_ALIAS:
        return REG_ALIAS[t]
    m = re.fullmatch(r"r(\d+)", t)
    if not m or int(m.group(1)) > 31:
        raise AsmError(f"{where}: '{tok}' is not a register")
    return int(m.group(1))


class Assembler:
    def __init__(self):
        self.labels = {}
        self.equs = {}
        self.words = {0: {}, 1: {}}     # bank -> {addr_in_bank: word}

    # -- expression evaluation --------------------------------------------
    def value(self, tok, where, allow_label=True):
        t = tok.strip()
        if t in self.equs:
            return self.equs[t]
        if allow_label and t in self.labels:
            return self.labels[t]
        try:
            return int(t, 0)
        except ValueError:
            pass
        if allow_label:
            raise AsmError(f"{where}: unknown label or number '{t}'")
        raise AsmError(f"{where}: '{t}' is not a number")

    def address(self, tok, where):
        """Parse `off(rs)` or a bare address. Returns (base_reg, offset).

        A bare address is the same thing with base r0, because r0 reads zero.
        """
        m = re.fullmatch(r"(.*)\(\s*(\w+)\s*\)", tok.strip())
        if m:
            off = self.value(m.group(1), where) if m.group(1).strip() else 0
            return reg(m.group(2), where), off
        return 0, self.value(tok, where)

    # -- encoders ---------------------------------------------------------
    @staticmethod
    def r_type(func, src, trg, des, shamt=0):
        return ((OPC["alu"] << 26) | (src << 21) | (trg << 16)
                | (des << 11) | (shamt << 6) | func)

    @staticmethod
    def i_type(op, src, trg, imm):
        return (op << 26) | (src << 21) | (trg << 16) | (imm & 0xFFFF)

    @staticmethod
    def j_type(op, addr):
        return (op << 26) | (addr & 0x3FFFFFF)

    # -- one source line --------------------------------------------------
    def encode(self, mnem, args, where):
        """Return a list of words for this instruction."""
        a = [x.strip() for x in args.split(",")] if args.strip() else []

        def need(n):
            if len(a) != n:
                raise AsmError(f"{where}: {mnem} takes {n} operand(s), got {len(a)}")

        if mnem in ("add", "sub", "and", "or", "xor", "slt", "sltu"):
            need(3)
            return [self.r_type(FUNC[mnem], reg(a[1], where), reg(a[2], where),
                                reg(a[0], where))]
        if mnem == "not":
            need(2)
            return [self.r_type(FUNC["not"], reg(a[1], where), 0,
                                reg(a[0], where))]
        if mnem in ("shl", "shr"):
            need(3)
            n = self.value(a[2], where, allow_label=False)
            if not 0 <= n <= 31:
                raise AsmError(f"{where}: shift amount {n} out of range 0..31")
            return [self.r_type(FUNC[mnem], reg(a[1], where), 0,
                                reg(a[0], where), n)]
        if mnem in ("load", "store"):
            need(2)
            base, off = self.address(a[1], where)
            return [self.i_type(OPC[mnem], base, reg(a[0], where), off)]
        if mnem == "loadi":
            need(2)
            return [self.i_type(OPC["loadi"], 0, reg(a[0], where),
                                self.value(a[1], where))]
        if mnem in ("addi", "subi"):
            need(3)
            return [self.i_type(OPC[mnem], reg(a[1], where), reg(a[0], where),
                                self.value(a[2], where))]
        if mnem == "move":
            need(2)
            return [self.i_type(OPC["move"], reg(a[1], where),
                                reg(a[0], where), 0)]
        if mnem in ("beq", "bne"):
            need(3)
            return [self.i_type(OPC[mnem], reg(a[0], where), reg(a[1], where),
                                self.value(a[2], where))]
        if mnem in ("jump", "jal"):
            need(1)
            return [self.j_type(OPC[mnem], self.value(a[0], where))]
        if mnem == "jr":
            need(1)
            return [self.i_type(OPC["jr"], reg(a[0], where), 0, 0)]
        if mnem in ("halt", "nop"):
            need(0)
            return [self.j_type(OPC[mnem], 0)]

        # ---- pseudo-instructions -------------------------------------
        # The stack grows DOWNWARD, so a push decrements sp first and a pop
        # reads before incrementing. Nothing here is a new instruction: it is
        # SUBI/STORE and LOAD/ADDI, made possible by base+offset addressing.
        if mnem == "push":
            need(1)
            return [
                self.i_type(OPC["subi"], SP, SP, 1),
                self.i_type(OPC["store"], SP, reg(a[0], where), 0),
            ]
        if mnem == "pop":
            need(1)
            return [
                self.i_type(OPC["load"], SP, reg(a[0], where), 0),
                self.i_type(OPC["addi"], SP, SP, 1),
            ]
        # `call` is JAL with ra saved around it, so a routine can call another
        # without losing its own return address. `ret` is the matching half.
        if mnem == "call":
            need(1)
            return [
                self.i_type(OPC["subi"], SP, SP, 1),
                self.i_type(OPC["store"], SP, LINK, 0),
                self.j_type(OPC["jal"], self.value(a[0], where)),
                self.i_type(OPC["load"], SP, LINK, 0),
                self.i_type(OPC["addi"], SP, SP, 1),
            ]
        if mnem == "ret":
            need(0)
            return [self.i_type(OPC["jr"], LINK, 0, 0)]

        if mnem in ("mul", "div", "mod"):
            need(3)
            rd, rs, rt = (reg(a[0], where), reg(a[1], where), reg(a[2], where))
            routine = "__mul" if mnem == "mul" else "__div"
            target = RET0 if mnem in ("mul", "div") else RET1
            return [
                self.i_type(OPC["move"], rs, ARG0, 0),
                self.i_type(OPC["move"], rt, ARG1, 0),
                self.j_type(OPC["jal"], self.value(routine, where)),
                self.i_type(OPC["move"], target, rd, 0),
            ]

        raise AsmError(f"{where}: unknown instruction '{mnem}'")

    # -- passes -----------------------------------------------------------
    def parse(self, text, path):
        """Strip comments and split into (where, label, mnem, args) items."""
        items = []
        for n, raw in enumerate(text.splitlines(), 1):
            line = re.split(r"[;#]", raw, maxsplit=1)[0].strip()
            if not line:
                continue
            where = f"{os.path.basename(path)}:{n}"
            while True:
                m = re.match(r"^([A-Za-z_.$][\w.$]*)\s*:\s*(.*)$", line)
                if not m:
                    break
                items.append((where, m.group(1), None, None))
                line = m.group(2).strip()
            if not line:
                continue
            m = re.match(r"^(\S+)\s*(.*)$", line)
            items.append((where, None, m.group(1).lower(), m.group(2)))
        return items

    def assemble(self, text, path):
        items = self.parse(text, path)

        # ---- pass 1: sizes and labels --------------------------------
        bank, addr = 0, 0
        for where, label, mnem, args in items:
            if label is not None:
                self.labels[label] = bank * 256 + addr
                continue
            if mnem == ".equ":
                name, val = [x.strip() for x in args.split(",", 1)]
                self.equs[name] = self.value(val, where, allow_label=False)
            elif mnem == ".bank":
                bank = self.value(args, where, allow_label=False)
                addr = 0
            elif mnem == ".org":
                addr = self.value(args, where, allow_label=False)
            elif mnem == ".word":
                addr += len([x for x in args.split(",") if x.strip()])
            else:
                # Pseudo-instructions expand to several words. Sizes come from
                # a table rather than from trial encoding, because in pass 1 a
                # forward label is not known yet and encoding would fail for a
                # reason that has nothing to do with the size.
                addr += PSEUDO_SIZE.get(mnem, 1)

        # ---- pass 2: emit --------------------------------------------
        bank, addr = 0, 0
        for where, label, mnem, args in items:
            if label is not None:
                continue
            if mnem == ".equ":
                continue
            if mnem == ".bank":
                bank = self.value(args, where, allow_label=False)
                addr = 0
                continue
            if mnem == ".org":
                addr = self.value(args, where, allow_label=False)
                continue
            if mnem == ".word":
                for tok in [x for x in args.split(",") if x.strip()]:
                    self.emit(bank, addr, self.value(tok, where), where)
                    addr += 1
                continue
            for w in self.encode(mnem, args or "", where):
                self.emit(bank, addr, w, where)
                addr += 1

    def emit(self, bank, addr, word, where):
        if bank not in (0, 1):
            raise AsmError(f"{where}: bank {bank} does not exist (0 or 1)")
        if not 0 <= addr <= 255:
            raise AsmError(f"{where}: address {addr} outside the 256-word bank")
        if addr in self.words[bank]:
            raise AsmError(f"{where}: address {bank * 256 + addr} written twice")
        self.words[bank][addr] = word & MASK32


VHDL_TEMPLATE = '''library ieee;
use ieee.std_logic_1164.all;

library work;
use work.mem_pkg.all;

-- memory_image_pkg -- GENERATED FILE. Do not edit by hand.
--
--   source:   {src}
--   assembler: tools/pasm.py
--
-- Regenerate with:
--   python tools/pasm.py {src} -o memory_image_pkg.vhd
--
-- On an FPGA, block RAM is initialised from the configuration bitstream, so
-- "RAM with initial contents" is not a contradiction: the image arrives when
-- the chip is configured and can be overwritten afterwards through the data
-- bus. The split between banks is a CONVENTION, not a constraint -- both are
-- ordinary read/write memory in one address space.
--
--   bank 0 -> addresses   0..255
--   bank 1 -> addresses 256..511

package memory_image_pkg is

{bank0}

{bank1}

end package memory_image_pkg;

-- Made with my soul - Swately <3
'''


def render_bank(name, words, comments):
    if not words:
        return (f"    constant {name} : word_array(0 to 0) := "
                f"(0 => X\"00000000\");")
    top = max(words)
    lines = [f"    constant {name} : word_array(0 to {top}) := ("]
    for i in range(top + 1):
        w = words.get(i, 0)
        sep = "," if i < top else ""
        c = comments.get(i, "")
        pad = " " * max(1, 22 - len(f'{i:<4}=> X"{w:08X}"{sep}'))
        lines.append(f'        {i:<4}=> X"{w:08X}"{sep}{pad}-- {c}' if c
                     else f'        {i:<4}=> X"{w:08X}"{sep}')
    lines.append("    );")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description="PHarvard assembler")
    ap.add_argument("source")
    ap.add_argument("-o", "--output", default="memory_image_pkg.vhd")
    ap.add_argument("--listing", action="store_true",
                    help="print an address/word/source listing")
    args = ap.parse_args()

    text = open(args.source, encoding="utf-8").read()
    asm = Assembler()
    try:
        asm.assemble(text, args.source)
    except AsmError as e:
        sys.exit(f"pasm: {e}")

    n0, n1 = len(asm.words[0]), len(asm.words[1])
    src = args.source.replace("\\", "/")
    out = VHDL_TEMPLATE.format(
        src=src,
        bank0=render_bank("BANK0_INIT", asm.words[0], {}),
        bank1=render_bank("BANK1_INIT", asm.words[1], {}),
    )
    with open(args.output, "w", encoding="utf-8") as fh:
        fh.write(out)

    print(f"pasm: {src} -> {args.output}")
    print(f"  bank 0 (code)  : {n0} words")
    print(f"  bank 1 (data)  : {n1} words")
    print(f"  labels         : {len(asm.labels)}")
    if args.listing:
        print("\nLABELS")
        for k in sorted(asm.labels, key=lambda x: asm.labels[x]):
            print(f"  {asm.labels[k]:>4}  {k}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
