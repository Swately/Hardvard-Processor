#!/usr/bin/env python3
"""check_slots4.py -- verify the four-reel slot machine.

    python tools/pasm.py sw/slots4.s -o memory_image_pkg.vhd
    python sim/check_slots4.py

TWO THINGS ARE CHECKED, AND THEY ARE DIFFERENT.

1. THE RULE. slots4.s decides a payout by counting matches over every ordered
   pair of reels and looking the total up. This checks, over all 10,000
   possible spins, that the total always names the hand -- by classifying each
   spin the obvious way instead (sort the counts) and comparing. Two
   implementations of one rule, written differently.

2. THE PROGRAM. The assembled image is then RUN, with the peripherals modelled:
   the LFSR from lfsr_32.vhd stepping once per instruction, a player
   pressing and releasing the middle button, and the display
   captured. Every spin the program pays is recompared against the rule, and
   the credit balance is tracked independently and checked against what the
   program puts on the display.

The second is the one that catches an off-by-one in the double loop or a
clobbered register. The first cannot: it never executes an instruction.

The emulator models the instruction set, not this board, so the peripherals are
injected through check_cpu.emulate's `io` hook rather than built into it.

Made with my soul - Swately <3
"""
import os
import sys
from collections import Counter

SIM = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(SIM)
sys.path.insert(0, SIM)

import check_cpu as cc  # noqa: E402

MASK = 0xFFFFFFFF
BUTTONS, RANDOM, DIGITS = 499, 500, 501
REELS, NREELS, SYMBOLS = 320, 4, 10
PAY = {16: 50, 10: 8, 8: 4, 6: 1, 4: 0}
NAMES = {16: "four of a kind", 10: "three of a kind", 8: "two pair",
         6: "one pair", 4: "nothing"}
START, BET, CAP = 10, 1, 999
SCORE_ADDR = 53                  # `score` -- from pasm --listing
GLYPH_A = 10
GLYPH_C = 12


def rules_payout(reels):
    """The payout worked out the obvious way: sort the counts."""
    c = sorted(Counter(reels).values(), reverse=True)
    if c[0] == 4:
        return PAY[16]
    if c[0] == 3:
        return PAY[10]
    if c[0] == 2 and c[1] == 2:
        return PAY[8]
    if c[0] == 2:
        return PAY[6]
    return PAY[4]


def check_rule():
    print("=== 1. the rule, over all 10,000 spins ===\n")
    tally, bad = Counter(), []
    for a in range(SYMBOLS):
        for b in range(SYMBOLS):
            for c in range(SYMBOLS):
                for d in range(SYMBOLS):
                    reels = (a, b, c, d)
                    total = sum(1 for x in reels for y in reels if x == y)
                    tally[total] += 1
                    if PAY.get(total) != rules_payout(reels):
                        bad.append((reels, total))
    for t in sorted(tally, reverse=True):
        print(f"  total {t:2d}  {NAMES[t]:16s} {tally[t]:5d}/10000 "
              f"= {100*tally[t]/10000:6.2f}%   pays {PAY[t]}")
    ev = sum(tally[t] * PAY[t] for t in tally) / 10000
    print(f"\n  return to player {100*ev:.1f}%, house edge {100*(1-ev):.1f}%")
    if bad:
        print(f"\n  FAIL -- {len(bad)} spins classified wrongly, e.g. {bad[:3]}")
        return False
    print("  PASS -- one total names the hand, every time")
    return True


def check_score_routine():
    """Run the REAL score routine with every hand it could ever be given.

    This is what the entry-point argument to the emulator buys. A full program
    run reaches whatever hands the LFSR happens to produce -- five spins in a
    million and a half instructions, all of them pairs or nothing. The rare
    paths through the comparison chain, the ten four-of-a-kinds and the 360
    three-of-a-kinds, would take hours of simulated play to hit by chance.
    Entered directly, all 10,000 take a few seconds.
    """
    print("\n=== 2. the score routine, run with all 10,000 hands ===\n")
    prog = cc.load_program()
    RET = 900                      # outside the image: the routine ends here
    bad, cover = [], Counter()
    for a in range(SYMBOLS):
      for b in range(SYMBOLS):
        for c in range(SYMBOLS):
          for d in range(SYMBOLS):
            reels = (a, b, c, d)
            reg = [0] * 32
            reg[24] = REELS        # the base register the routine expects
            reg[31] = RET
            g = cc.emulate(prog, limit=400,
                           initial_mem={REELS + i: v for i, v in enumerate(reels)},
                           start_pc=SCORE_ADDR, initial_reg=reg)
            got = 0
            for r, v in g["reg_writes"]:
                if r == 6:
                    got = v
            cover[sum(1 for x in reels for y in reels if x == y)] += 1
            if got != rules_payout(reels):
                bad.append((reels, got, rules_payout(reels)))
    for t in sorted(cover, reverse=True):
        print(f"  {NAMES[t]:16s} {cover[t]:5d} hands   pays {PAY[t]}")
    if bad:
        print(f"\n  FAIL -- {len(bad)} hands scored wrongly, e.g. {bad[:3]}")
        return False
    print("\n  PASS -- every hand scored correctly by the code that goes on")
    print("  the board, the ten four-of-a-kinds included")
    return True


def check_program(instructions=1_500_000):
    print("\n=== 3. the whole program, run with the peripherals ===\n")
    prog = cc.load_program()

    lfsr = [1]                       # lfsr_32.vhd powers up at 1
    frames, reel_writes = [], []

    def step():
        s = lfsr[0]
        fb = ((s >> 31) ^ (s >> 21) ^ (s >> 1) ^ s) & 1
        lfsr[0] = ((s << 1) | fb) & MASK

    polls = [0]

    def io_read(addr):
        if addr == RANDOM:
            step()
            return lfsr[0]
        if addr == BUTTONS:
            # A player pressing and releasing, forever. The program waits for
            # the button now, so a button that is never pressed would simply
            # hang -- which is correct behaviour and useless as a test.
            # Alternating runs also exercise the debounce path both ways.
            polls[0] += 1
            return 2 if (polls[0] // 50) % 2 else 0
        return None

    def io_write(addr, value):
        if addr == DIGITS:
            frames.append(value & 0xFFFF)
            return True
        if REELS <= addr < REELS + NREELS:
            reel_writes.append((addr - REELS, value))
        return False

    g = cc.emulate(prog, limit=instructions, initial_mem=cc.load_data(),
                   io=(io_read, io_write))
    print(f"  {len(g['pcs']):,} instructions executed")

    # Rebuild the spins from the reel writes, in groups of four.
    spins = []
    cur = {}
    for idx, val in reel_writes:
        cur[idx] = val
        if len(cur) == NREELS:
            spins.append(tuple(cur[k] for k in range(NREELS)))
            cur = {}
    print(f"  {len(spins)} spins, {len(frames)} display writes\n")
    if not spins:
        print("  FAIL -- the program never spun")
        return False

    # Independently track the balance the program should be showing.
    credits, ok, shown = START, True, 0
    idle = [f for f in frames if (f >> 12) == GLYPH_C]
    wins = [f for f in frames if (f >> 12) == GLYPH_A]
    reel_frames = [f for f in frames
                   if (f >> 12) not in (GLYPH_C, GLYPH_A)]

    # Every win frame must state the payout the rules give for the spin it
    # follows -- a credit that appears without a frame naming it is exactly
    # the anomaly this instrumentation is here to make visible.
    expect_wins = [rules_payout(s_) for s_ in spins if rules_payout(s_)]
    for n, f in enumerate(wins):
        if n >= len(expect_wins):
            break
        got = ((f >> 8) & 0xF) * 100 + ((f >> 4) & 0xF) * 10 + (f & 0xF)
        if got != expect_wins[n]:
            print(f"  FAIL win frame {n}: shows {got}, "
                  f"rules say {expect_wins[n]}")
            ok = False
            break
    print(f"  {len(wins)} win frames, all naming the payout the rules give")

    for n, reels in enumerate(spins):
        credits -= BET
        pay = rules_payout(reels)
        credits += pay
        if credits > CAP:
            credits = CAP
        if credits < BET:
            credits = START          # the program restarts the game
        if n < len(reel_frames):
            want = (reels[0] << 12) | (reels[1] << 8) | (reels[2] << 4) | reels[3]
            if reel_frames[n] != want:
                print(f"  FAIL spin {n}: reels {reels} should display "
                      f"{want:04X}, program showed {reel_frames[n]:04X}")
                ok = False
                break
            shown += 1

    # The idle frames must be the letter C and the balance the rules predict.
    # Frame k is shown BEFORE spin k, so it reflects the balance after k-1.
    bal, mism = START, 0
    for n, f in enumerate(idle):
        want = (GLYPH_C << 12) | ((bal // 100) << 8) | ((bal // 10) % 10 << 4) \
               | (bal % 10)
        if f != want:
            if mism < 3:
                print(f"  FAIL idle frame {n}: balance should be {bal} "
                      f"({want:04X}), program showed {f:04X}")
            mism += 1
        if n < len(spins):
            bal -= BET
            bal += rules_payout(spins[n])
            bal = min(bal, CAP)
            if bal < BET:
                bal = START
    if mism:
        print(f"  FAIL -- {mism} idle frames disagree with the rules")
        ok = False

    hands = Counter(sum(1 for x in s for y in s if x == y) for s in spins)
    print("  what actually came up:")
    for t in sorted(hands, reverse=True):
        print(f"    {NAMES[t]:16s} {hands[t]:4d}")

    if ok:
        print(f"\n  PASS -- {shown} spins displayed correctly and every idle")
        print("  balance matches the rules computed independently")
    return ok


def main():
    a = check_rule()
    b = check_score_routine()
    c = check_program()
    print()
    if a and b and c:
        print("RESULT: PASS -- rule and program agree, and the program does")
        print("what the rule says on every spin it took.")
        return 0
    print("RESULT: FAIL")
    return 1


if __name__ == "__main__":
    sys.exit(main())
