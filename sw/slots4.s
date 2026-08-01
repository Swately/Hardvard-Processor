; ============================================================================
; slots4.s -- a four-reel slot machine, each reel a digit.
;
;     python tools/pasm.py sw/slots4.s -o memory_image_pkg.vhd
;
; The operator's design. The earlier sw/slots.s spun three fruit symbols and
; left the fourth digit blank, which was a leftover from the character-LCD
; version where symbols were CGRAM glyphs. With digits as the symbols the
; display carries four reels and nothing is wasted -- a spin is a four-figure
; number, which is exactly what four seven-segment digits are for.
;
; Ten symbols instead of eight, so `random mod 10`.
;
;   idle       C010     the letter C and the credit count
;   spinning   7 7 3 1  the four reels
;
; The C is why the hex glyphs earned their place: it makes the idle screen
; unmistakable from a spin result at a glance, with no extra state to read.
;
; ---------------------------------------------------------------------------
; SCORING, WHICH COSTS ALMOST NOTHING
;
; Four reels have five outcomes, and telling them apart usually means sorting
; or a tree of comparisons. It is not needed. Count, over every ORDERED pair of
; reels (i, j) including i = j, how many times the two are equal:
;
;     four of a kind   4+4+4+4 = 16      0.10 %
;     three of a kind  3+3+3+1 = 10      3.60 %
;     two pair         2+2+2+2 =  8      2.70 %
;     one pair         2+2+1+1 =  6     43.20 %
;     nothing          1+1+1+1 =  4     50.40 %
;
; Every hand gives a different total, so ONE number names the hand. It is a
; plain double loop over sixteen comparisons -- no sorting, no special cases,
; and it extends to any number of reels without changing.
;
; Payouts 50 / 8 / 4 / 1 on a bet of 1 give a return to player of 87.8 %,
; computed exactly over all 10,000 outcomes, not estimated. Real machines run
; 85-98 %, so this one is honest about being a slot machine.
;
; ---------------------------------------------------------------------------
; WHERE THE RANDOMNESS COMES FROM
;
; The LFSR is free-running and fully deterministic: same seed, same sequence.
; The entropy is in WHEN the player presses -- the press samples a 32-bit
; counter that has advanced a few million times since the last one.
;
; So the button is not a convenience, it is the entropy source, and this
; program waits for it rather than spinning on a timer. An earlier version
; spun by itself every two seconds because the button pins had never been
; exercised. That version was ALSO the thing that made the reels fake: a fixed
; sampling interval turns the LFSR into a fixed sequence, which is deterministic
; however random it looks. It looks extremely random -- decimating a maximal
; LFSR leaves a period of billions -- and reading that as evidence the button
; worked would have been wrong.
;
; MEASURED 2026-08-01 with sw/btntest.s: the middle button is pin 110, which is
; bit 1, and it is ACTIVE HIGH. Only that bit is tested. The other four pins
; are still transcribed from photographs, and a program that watched all five
; would hand the game over to any one of them that happened to float.
; ============================================================================

        .equ BUTTONS,    499
        .equ RANDOM,     500
        .equ DIGITS,     501

        .equ STACK_TOP,  495        ; below the peripheral block at 496
        .equ REELS,      320        ; bank 1, word 64: the four reels

        .equ NREELS,     4
        .equ SYMBOLS,    10
        .equ START_CREDITS, 10
        .equ BET,        1

        .equ PAY_FOUR,   50
        .equ PAY_THREE,  8
        .equ PAY_TWOPAIR, 4
        .equ PAY_PAIR,   1

        .equ GLYPH_C,    12         ; C for credits
        .equ GLYPH_A,    10         ; A for the amount won

; ----------------------------------------------------------------------------
        .bank 0
        .org 0
; ----------------------------------------------------------------------------
start:
        loadi sp, STACK_TOP
        loadi r24, REELS
        loadi r16, START_CREDITS

main_loop:
        jal   show_credits
        jal   wait_for_button

        ; Can the player afford it? Out of credits, the press starts a new game
        ; rather than leaving the machine dead.
        loadi r8, BET
        sltu  r9, r16, r8
        bne   r9, r0, out_of_credit
        sub   r16, r16, r8

        jal   spin
        jal   show_reels
        jal   score                 ; r6 = the payout
        move  r17, r6               ; keep it; hold and show_win use r6

        jal   hold
        jal   hold

        ; Show what was won, so the credit arithmetic is auditable by eye
        ; instead of having to be trusted. A win frame appears exactly when
        ; the balance is about to go up, and by exactly how much -- if a credit
        ; ever appears from nowhere, the missing frame says so.
        beq   r17, r0, no_win
        jal   show_win
        jal   hold
no_win:
        add   r16, r16, r17

        ; The display holds three digits of credit, so the count must not grow
        ; past what can be shown truthfully.
        loadi r8, 1000
        sltu  r9, r16, r8
        bne   r9, r0, no_cap
        loadi r16, 999
no_cap:
        jump  main_loop

out_of_credit:
        loadi r16, START_CREDITS
        jump  main_loop

; ============================================================================
; spin -- four reels, each an independent sample of the free-running LFSR.
;
; `random mod 10` is a call to __div, because this machine has no divide
; instruction. Four spins are four divisions.
; ============================================================================
spin:
        push  ra
        loadi r13, 0
spin_loop:
        loadi r8, NREELS
        beq   r13, r8, spin_done
        load  r4, RANDOM
        loadi r5, SYMBOLS
        jal   __div                 ; r7 = the remainder, 0..9
        add   r9, r24, r13
        store r7, 0(r9)
        addi  r13, r13, 1
        jump  spin_loop
spin_done:
        pop   ra
        ret

; ============================================================================
; show_reels -- the four reels, one per digit.
; ============================================================================
show_reels:
        load  r8, 0(r24)
        shl   r8, r8, 12
        load  r9, 1(r24)
        shl   r9, r9, 8
        or    r8, r8, r9
        load  r9, 2(r24)
        shl   r9, r9, 4
        or    r8, r8, r9
        load  r9, 3(r24)
        or    r8, r8, r9
        store r8, DIGITS
        jr    ra

; ============================================================================
; score -- r6 = the payout for the reels currently in memory.
;
; Sixteen comparisons and a lookup. See the header for why one sum is enough.
; ============================================================================
score:
        loadi r6, 0                 ; the running total
        loadi r13, 0                ; i
sc_outer:
        loadi r8, NREELS
        beq   r13, r8, sc_total
        add   r9, r24, r13
        load  r10, 0(r9)            ; reel[i]
        loadi r14, 0                ; j
sc_inner:
        loadi r8, NREELS
        beq   r14, r8, sc_inner_done
        add   r9, r24, r14
        load  r11, 0(r9)            ; reel[j]
        bne   r10, r11, sc_next
        addi  r6, r6, 1
sc_next:
        addi  r14, r14, 1
        jump  sc_inner
sc_inner_done:
        addi  r13, r13, 1
        jump  sc_outer

sc_total:
        loadi r8, 16
        bne   r6, r8, sc_three
        loadi r6, PAY_FOUR
        jr    ra
sc_three:
        loadi r8, 10
        bne   r6, r8, sc_twopair
        loadi r6, PAY_THREE
        jr    ra
sc_twopair:
        loadi r8, 8
        bne   r6, r8, sc_pair
        loadi r6, PAY_TWOPAIR
        jr    ra
sc_pair:
        loadi r8, 6
        bne   r6, r8, sc_nothing
        loadi r6, PAY_PAIR
        jr    ra
sc_nothing:
        loadi r6, 0
        jr    ra

; ============================================================================
; show_credits / show_win -- a glyph and three decimal digits.
;
; Both are one line and a tail call. `jump show_val` rather than `jal` leaves
; the return address alone, so show_val returns straight to whoever called
; these -- one routine, two labels, no duplicated arithmetic.
; ============================================================================
show_credits:
        loadi r15, GLYPH_C
        move  r4, r16
        jump  show_val

show_win:
        loadi r15, GLYPH_A
        move  r4, r17
        jump  show_val

; show_val -- glyph in r15, value in r4. Two divisions by ten, both software
; routines, so every frame on this display is also a demonstration that the
; arithmetic library works.
show_val:
        push  ra

        loadi r5, 10
        jal   __div                 ; r6 = value/10, r7 = units
        move  r13, r7
        loadi r5, 10
        move  r4, r6
        jal   __div                 ; r6 = value/100, r7 = tens
        move  r14, r7

        shl   r8, r15, 12           ; the glyph
        shl   r9, r6, 8             ; hundreds
        or    r8, r8, r9
        shl   r9, r14, 4            ; tens
        or    r8, r8, r9
        or    r8, r8, r13           ; units
        store r8, DIGITS

        pop   ra
        ret

; ============================================================================
; wait_for_button -- one press, one spin.
;
; Masked to bit 1 so only the button whose pin was actually measured can start
; a game.
;
; DEBOUNCED, because a tactile switch does not close once. Its contacts bounce
; for a few milliseconds, and this loop reads the pin about a hundred thousand
; times a second: without the settle delays a single press would be seen as a
; press, a release and another press, and the player would lose several credits
; for one push. Twenty milliseconds after each edge is longer than any switch
; of this kind bounces and far shorter than a finger notices.
; ============================================================================
wait_for_button:
        push  ra
        loadi r15, 2                ; the middle button, bit 1
wfb_idle:
        load  r8, BUTTONS
        and   r8, r8, r15
        beq   r8, r0, wfb_idle
        jal   settle                ; let the contact stop chattering

        ; CONFIRM. A delay after the first edge absorbs contact bounce, but it
        ; does nothing about a glitch on the wire: a single stray sample reads
        ; as a press, the pin is clear again by the time the release is looked
        ; for, and the machine spins for nobody. On a bare button line with no
        ; shielding that is a real way to lose a credit to nothing.
        ;
        ; So the press has to still be there twenty milliseconds later. A
        ; finger easily lasts that long; a glitch does not.
        load  r8, BUTTONS
        and   r8, r8, r15
        beq   r8, r0, wfb_idle
wfb_held:
        load  r8, BUTTONS
        and   r8, r8, r15
        bne   r8, r0, wfb_held
        jal   settle                ; and again on the way up
        pop   ra
        ret

; About 20 ms at 2.08 MHz.
settle:
        loadi r8, 700
settle_loop:
        beq   r8, r0, settle_done
        subi  r8, r8, 1
        jump  settle_loop
settle_done:
        jr    ra

; ============================================================================
; hold -- about 0.6 s, called twice so the reels can be read.
; ============================================================================
hold:
        loadi r8, 150
hold_outer:
        beq   r8, r0, hold_done
        loadi r9, 100
hold_inner:
        beq   r9, r0, hold_next
        subi  r9, r9, 1
        jump  hold_inner
hold_next:
        subi  r8, r8, 1
        jump  hold_outer
hold_done:
        jr    ra

; ============================================================================
; __div -- r6 = r4 / r5, r7 = r4 mod r5, unsigned. Restoring division.
; clobbers r8, r9, r10, r11, r12
; ============================================================================
__div:
        loadi r6, 0
        loadi r7, 0
        beq   r5, r0, __div_zero
        loadi r8, 32
        move  r9, r4
        loadi r12, 1
__div_loop:
        beq   r8, r0, __div_done
        shl   r7, r7, 1
        shr   r10, r9, 31
        add   r7, r7, r10
        shl   r9, r9, 1
        shl   r6, r6, 1
        sltu  r11, r7, r5
        bne   r11, r0, __div_next
        sub   r7, r7, r5
        add   r6, r6, r12
__div_next:
        subi  r8, r8, 1
        jump  __div_loop
__div_done:
        jr    ra
__div_zero:
        loadi r6, -1
        move  r7, r4
        jr    ra

; ----------------------------------------------------------------------------
        .bank 1
        .org 0
; ----------------------------------------------------------------------------
; Bank 1 is ordinary data memory. Word 64 (address 320) onward holds the four
; reels; the program writes them, so nothing needs to be placed here.
        .word 0x00000000

; Made with my soul - Swately <3
