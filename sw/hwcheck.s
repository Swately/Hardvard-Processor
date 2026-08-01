; ============================================================================
; hwcheck.s -- the whole instruction set, checked ON THE BOARD.
;
;     python tools/pasm.py sw/hwcheck.s -o memory_image_pkg.vhd
;
; sw/hello7seg.s proved three instructions on silicon. This proves the rest:
; software multiplication and division, a routine that calls another routine
; through the stack, a store into one memory bank read back from the other,
; shifts, comparisons, and register-indirect addressing.
;
; It is the same arithmetic sim/run_diag.py verifies against the golden model,
; which is the point -- the machine is being asked the questions whose answers
; are already known exactly.
;
; WHAT THE DISPLAY DOES. It shows eight frames, about a second and a quarter
; each, and repeats forever:
;
;     0007      <- the verdict: how many of the seven checks passed
;     0034         34 = 26 + 8, where 26 was STORED to bank 1 and LOADED back
;     0132        132 = __mul(12, 11)          multiplication in software
;     0012         12 = __div(132, 11)         division in software
;     0014         14 = __div(100, 7)
;     0002          2 = the remainder of it
;     0049         49 = __square(7), which CALLED __mul -- a nested routine
;     0495        495 = the stack pointer, back exactly where it started
;
; The first frame is the one to read. Anything other than 0007 means a check
; failed, and the six frames after it say which: they are the values the
; machine actually computed, so a wrong one names the broken operation instead
; of merely reporting that something is broken.
;
; The results are written to a table in memory and read back through
; `load r4, 0(r24)` with a moving base register. That is not decoration -- it
; exercises register-indirect addressing, which is the mechanism the stack is
; built on, and it does it separately from the stack itself.
;
; Every value is displayed with its leading zeros. 0049 cannot be mistaken for
; a half-lit 49, and blanking logic is one more thing that could be wrong.
; ============================================================================

        .equ DIGITS,     501
        .equ STACK_TOP,  495        ; must stay below the peripherals at 496
        .equ DATA_SLOT,  276        ; bank 1, word 20
        .equ RESULTS,    300        ; bank 1, words 44..50: the result table
        .equ NRESULTS,   7

; ----------------------------------------------------------------------------
        .bank 0
        .org 0
; ----------------------------------------------------------------------------
start:
        loadi sp, STACK_TOP
        loadi r24, RESULTS          ; base of the result table

; ---- a store into the OTHER bank, and back out of it -----------------------
        loadi r4, 6
        loadi r5, 7
        jal   add_pair              ; r6 = 13
        shl   r6, r6, 2             ; 52
        shr   r8, r6, 1             ; 26
        store r8, DATA_SLOT         ; written to bank 1
        load  r9, DATA_SLOT         ; read back from bank 1
        addi  r2, r9, 8             ; 34
        store r2, 0(r24)

; ---- multiplication, built from ADD and shifts -----------------------------
        loadi r4, 12
        loadi r5, 11
        jal   __mul                 ; 132
        store r6, 1(r24)

; ---- division, built from SUB, shifts and SLTU -----------------------------
        loadi r4, 132
        loadi r5, 11
        jal   __div                 ; 12 remainder 0
        store r6, 2(r24)

        loadi r4, 100
        loadi r5, 7
        jal   __div                 ; 14 remainder 2
        store r6, 3(r24)
        store r7, 4(r24)

; ---- a NESTED call: __square calls __mul -----------------------------------
; Impossible before the stack existed: __square has a return address of its
; own, and calling __mul would have destroyed it.
        loadi r4, 7
        call  __square              ; 49
        store r6, 5(r24)

; ---- and the stack came back to exactly where it started -------------------
        move  r8, sp
        store r8, 6(r24)

; ============================================================================
; Check every result against the value it must have.
; ============================================================================
        loadi r25, 0                ; passes

        load  r9, 0(r24)
        loadi r8, 34
        bne   r9, r8, chk1
        addi  r25, r25, 1
chk1:
        load  r9, 1(r24)
        loadi r8, 132
        bne   r9, r8, chk2
        addi  r25, r25, 1
chk2:
        load  r9, 2(r24)
        loadi r8, 12
        bne   r9, r8, chk3
        addi  r25, r25, 1
chk3:
        load  r9, 3(r24)
        loadi r8, 14
        bne   r9, r8, chk4
        addi  r25, r25, 1
chk4:
        load  r9, 4(r24)
        loadi r8, 2
        bne   r9, r8, chk5
        addi  r25, r25, 1
chk5:
        load  r9, 5(r24)
        loadi r8, 49
        bne   r9, r8, chk6
        addi  r25, r25, 1
chk6:
        load  r9, 6(r24)
        loadi r8, STACK_TOP
        bne   r9, r8, chk7
        addi  r25, r25, 1
chk7:

; ============================================================================
; Show the verdict, then every value behind it, forever.
; ============================================================================
show_loop:
        move  r4, r25               ; the verdict frame
        jal   show_dec4
        jal   hold

        loadi r26, 0                ; index into the table
frame_loop:
        add   r27, r24, r26
        load  r4, 0(r27)
        jal   show_dec4
        jal   hold
        addi  r26, r26, 1
        loadi r8, NRESULTS
        bne   r26, r8, frame_loop

        jump  show_loop

; ============================================================================
; show_dec4 -- put r4 on the display as four decimal digits.
;
; Four divisions by ten. The processor has no divide instruction, so each one
; is a call to __div: the display of this program's results is itself a
; demonstration of the thing being tested.
;
; `push ra` once at entry is what makes the inner `jal`s safe -- they overwrite
; r31 freely, and the entry copy is what `ret` returns through.
; ============================================================================
show_dec4:
        push  ra
        push  r16
        push  r17

        move  r16, r4               ; the value, divided down each round
        loadi r17, 0                ; the four nibbles, assembled

        loadi r5, 10
        move  r4, r16
        jal   __div                 ; r7 = units
        or    r17, r17, r7
        move  r16, r6

        loadi r5, 10
        move  r4, r16
        jal   __div                 ; r7 = tens
        shl   r8, r7, 4
        or    r17, r17, r8
        move  r16, r6

        loadi r5, 10
        move  r4, r16
        jal   __div                 ; r7 = hundreds
        shl   r8, r7, 8
        or    r17, r17, r8
        move  r16, r6

        loadi r5, 10
        move  r4, r16
        jal   __div                 ; r7 = thousands
        shl   r8, r7, 12
        or    r17, r17, r8

        store r17, DIGITS

        pop   r17
        pop   r16
        pop   ra
        ret

; ============================================================================
; hold -- about 1.2 s at 2.08 MHz, long enough to read a number.
;
; 300 x 100 iterations of roughly four instructions at 20.3 cycles each.
; ============================================================================
hold:
        loadi r8, 300
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

; ----------------------------------------------------------------------------
add_pair:
        add   r6, r4, r5
        jr    ra

; ============================================================================
; __square -- r6 = r4 * r4, by calling __mul rather than repeating it.
; ============================================================================
__square:
        move  r5, r4
        call  __mul
        ret

; ============================================================================
; __mul -- r6 = r4 * r5. Shift and add: once per set bit, at most 32 rounds.
; clobbers r8, r9, r10, r11
; ============================================================================
__mul:
        loadi r6, 0
        loadi r11, 1
        move  r8, r4
        move  r9, r5
__mul_loop:
        beq   r9, r0, __mul_done
        and   r10, r9, r11
        beq   r10, r0, __mul_skip
        add   r6, r6, r8
__mul_skip:
        shl   r8, r8, 1
        shr   r9, r9, 1
        jump  __mul_loop
__mul_done:
        jr    ra

; ============================================================================
; __div -- r6 = r4 / r5, r7 = r4 mod r5, unsigned. Restoring division, 32
; rounds exactly.
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
; Bank 1 is ordinary memory in the same address space as the code above. Word
; 20 (address 276) is the store/load target; words 44..50 (300..306) are the
; result table. Nothing needs to be placed here -- the program writes it -- but
; the space is reserved by being described.
        .word 0x00000000

; Made with my soul - Swately <3
