; ============================================================================
; slots.s -- a slot machine, running as a program on PHarvard.
;
;     python tools/pasm.py sw/slots.s -o memory_image_pkg.vhd
;
; Output is the board's 4-digit multiplexed 7-segment display, which was
; already wired and validated on hardware. The character LCD it used to drive
; was dropped: it cost 302 LUT4 (measured) on a part the design did not fit.
;
;     idle       ->  the credit count, right aligned
;     after spin ->  the three reel symbols, rightmost digit blank
;
; The display takes four BCD nibbles and nothing else. Turning a number into
; decimal digits is done HERE, with __div, because the hardware converter cost
; 2,184 cells -- the same decision that made MUL and DIV software routines.
;
; Everything the game needs that the hardware does not have is a subroutine:
; the symbol is `random mod 8`, and the modulo is a call.
; ============================================================================

; ---- memory-mapped peripherals (the top 16 words of the address space) -----
        .equ BUTTONS,    499
        .equ RANDOM,     500
        .equ DIGITS,     501

        .equ STACK_TOP,  495        ; below the peripheral block
        .equ BLANK,      15         ; a nibble of 15 lights no segments

        .equ START_CREDITS, 10
        .equ BET,           1
        .equ WIN_THREE,     20
        .equ WIN_TWO,       3

; ============================================================================
        .bank 0
        .org 0
; ============================================================================
start:
        loadi sp, STACK_TOP
        loadi r16, START_CREDITS     ; r16 = credits, kept for the whole game

main_loop:
        jal   show_credits
        jal   wait_button            ; blocks until a button goes down

        subi  r16, r16, BET          ; pay for the spin

        jal   next_symbol            ; three reels
        move  r17, r6
        jal   next_symbol
        move  r18, r6
        jal   next_symbol
        move  r19, r6

        jal   show_reels

        ; ---- score ---------------------------------------------------------
        ; three equal pays WIN_THREE, any two equal pays WIN_TWO
        bne   r17, r18, check_pair
        bne   r18, r19, check_pair
        addi  r16, r16, WIN_THREE
        jump  spin_done
check_pair:
        beq   r17, r18, pay_two
        beq   r18, r19, pay_two
        beq   r17, r19, pay_two
        jump  spin_done
pay_two:
        addi  r16, r16, WIN_TWO
spin_done:
        jal   wait_release
        jal   hold                   ; leave the reels up to be read
        jump  main_loop

; ============================================================================
; next_symbol -- r6 = a fresh symbol index in 0..7.
;
; `random mod 8` -- and the modulo is a CALL, because this processor has no
; divide instruction any more. r7 comes back holding the remainder.
; ============================================================================
next_symbol:
        push  ra
        load  r4, RANDOM             ; the free-running LFSR
        loadi r5, 8
        jal   __div                  ; r6 = quotient, r7 = remainder
        move  r6, r7                 ; the remainder is the symbol
        pop   ra
        ret

; ============================================================================
; show_reels -- the three symbols across the display, rightmost digit blank.
;
; The display wants four nibbles packed into one word, so this is three shifts
; and three ORs. `shl` exists because the shift amount field was already being
; decoded and thrown away.
; ============================================================================
show_reels:
        shl   r8, r17, 12
        shl   r9, r18, 8
        or    r8, r8, r9
        shl   r9, r19, 4
        or    r8, r8, r9
        loadi r9, BLANK
        or    r8, r8, r9
        store r8, DIGITS
        ret

; ============================================================================
; show_credits -- the credit count in decimal, right aligned, leading blanks.
;
; Two divisions by ten. A machine with a divide instruction would do this in
; two instructions; this one does it in two subroutine calls, and that is the
; point of the whole exercise.
; ============================================================================
show_credits:
        push  ra
        push  r20
        push  r21

        loadi r5, 10
        move  r4, r16
        jal   __div                  ; r6 = credits/10, r7 = units
        move  r20, r7                ; units
        move  r4, r6
        loadi r5, 10
        jal   __div                  ; r6 = credits/100, r7 = tens
        move  r21, r7                ; tens

        ; hundreds digit, blanked when zero
        loadi r8, BLANK
        shl   r8, r8, 12
        beq   r6, r0, no_hundreds
        shl   r8, r6, 12
no_hundreds:
        ; tens, blanked only when there are no hundreds either
        loadi r9, BLANK
        shl   r9, r9, 8
        bne   r6, r0, tens_shown
        beq   r21, r0, tens_done
tens_shown:
        shl   r9, r21, 8
tens_done:
        or    r8, r8, r9
        shl   r9, r20, 4             ; units, always shown
        or    r8, r8, r9
        loadi r9, BLANK
        or    r8, r8, r9
        store r8, DIGITS

        pop   r21
        pop   r20
        pop   ra
        ret

; ============================================================================
; wait_button / wait_release / hold
; ============================================================================
wait_button:
        load  r8, BUTTONS
        beq   r8, r0, wait_button
        ret

wait_release:
        load  r8, BUTTONS
        bne   r8, r0, wait_release
        ret

; A visible pause so the reels can be read before the credits come back.
; HOLD_OUTER x HOLD_INNER iterations of about 4 instructions at 20.3 cycles
; each: 6,000 x 4 x 20.3 = ~487,000 cycles, about 0.23 s at 2.08 MHz. Long
; enough to read, short enough that a testbench can simulate three of them.
hold:
        loadi r8, 60
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
        ret

; ============================================================================
; __div -- r6 = r4 / r5, r7 = r4 mod r5, unsigned. Restoring division, 32
; rounds, bounded whatever the operands are.
; clobbers r8, r9, r10, r12, r13
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
        sltu  r13, r7, r5
        bne   r13, r0, __div_next
        sub   r7, r7, r5
        add   r6, r6, r12
__div_next:
        subi  r8, r8, 1
        jump  __div_loop
__div_done:
        ret
__div_zero:
        loadi r6, -1
        move  r7, r4
        ret
