; ============================================================================
; jitter.s -- reads the edge counter and shows the result on the 7-segment.
;
;     python tools/pasm.py sw/jitter.s -o memory_image_pkg.vhd
;
; This is the experiment that decides whether a two-oscillator entropy source
; is viable on this hardware, BEFORE any generator is built.
;
; THE NUMBER THAT MATTERS IS THE SPREAD, max - min, in local clock cycles.
;
;     0000  ->  the two oscillators do not drift by even one 480 ns cycle over
;               a whole period of the external signal. No usable entropy at
;               this rate: lower OUT_HZ in arduino/jitter_source and reflash.
;               1000 -> 100 -> 10 Hz; each step multiplies the accumulated
;               jitter by sqrt(10), because jitter accumulates as a random walk.
;
;     k > 0 ->  they drift by k cycles, and k is the raw material a generator
;               would harvest. Roughly log2(k) bits are available per edge
;               before any conditioning.
;
; Press a button to cycle what is shown:
;
;     mode 0   SPREAD  max - min          <- the answer
;     mode 1   MIN     shortest period
;     mode 2   MAX     longest period
;     mode 3   COUNT   periods measured   (blank leading digit if over 9999)
;
; A blank display means no samples yet: nothing is arriving on the external
; oscillator pin. Check the wiring before concluding anything about jitter.
; ============================================================================

        .equ BUTTONS,    499
        .equ DIGITS,     501
        .equ EXT_PERIOD, 502
        .equ EXT_MIN,    503
        .equ EXT_MAX,    504
        .equ EXT_COUNT,  505

        .equ STACK_TOP,  495
        .equ BLANK,      15
        .equ ALL_BLANK,  0xFFFF

; ============================================================================
        .bank 0
        .org 0
; ============================================================================
start:
        loadi sp, STACK_TOP
        loadi r16, 0                 ; r16 = display mode
        store r0, EXT_COUNT          ; any write clears min/max/count

main_loop:
        ; ---- nothing measured yet? say so instead of showing nonsense ------
        load  r17, EXT_COUNT
        bne   r17, r0, have_samples
        loadi r4, ALL_BLANK
        store r4, DIGITS
        jump  check_button

have_samples:
        beq   r16, r0, mode_spread
        loadi r8, 1
        beq   r16, r8, mode_min
        loadi r8, 2
        beq   r16, r8, mode_max
        jump  mode_count

mode_spread:
        load  r18, EXT_MAX
        load  r19, EXT_MIN
        sub   r4, r18, r19           ; THE number
        jump  render

mode_min:
        load  r4, EXT_MIN
        jump  render

mode_max:
        load  r4, EXT_MAX
        jump  render

mode_count:
        load  r4, EXT_COUNT

render:
        jal   to_bcd4
        store r6, DIGITS

check_button:
        load  r8, BUTTONS
        beq   r8, r0, main_loop      ; nothing pressed, keep refreshing

        ; ---- a press advances the mode, 0..3 -------------------------------
        addi  r16, r16, 1
        loadi r8, 4
        sltu  r9, r16, r8
        bne   r9, r0, mode_ok
        loadi r16, 0
mode_ok:
        jal   wait_release
        jump  main_loop

wait_release:
        load  r8, BUTTONS
        bne   r8, r0, wait_release
        ret

; ============================================================================
; to_bcd4 -- r6 = four BCD nibbles of r4, most significant first.
;
; Three divisions by ten, each one a call into __div, because this processor
; has no divide instruction. A value above 9999 leaves a nibble of 10..15 in
; the thousands position, which the display shows as blank -- so an
; out-of-range reading looks out of range instead of looking like a number.
;
; clobbers r8, r9, r10, r12, r13 (through __div) and r20, r21, r22
; ============================================================================
to_bcd4:
        push  ra
        push  r20
        push  r21
        push  r22

        loadi r5, 10
        jal   __div
        move  r20, r7                ; units
        move  r4, r6

        loadi r5, 10
        jal   __div
        move  r21, r7                ; tens
        move  r4, r6

        loadi r5, 10
        jal   __div
        move  r22, r7                ; hundreds
                                     ; r6 = thousands

        shl   r8, r6, 12
        shl   r9, r22, 8
        or    r8, r8, r9
        shl   r9, r21, 4
        or    r8, r8, r9
        or    r8, r8, r20
        move  r6, r8

        pop   r22
        pop   r21
        pop   r20
        pop   ra
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
