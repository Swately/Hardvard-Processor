; ============================================================================
; demo.s -- exercises the instruction set and the software MUL/DIV library.
;
; Assemble with:
;     python tools/pasm.py sw/demo.s -o memory_image_pkg.vhd
;
; CALLING CONVENTION
;     r4, r5      arguments
;     r6, r7      return values
;     r8 .. r15   scratch; a routine may destroy these
;     r16 .. r28  the caller's, a routine must not touch them
;     r29 (sp)    stack pointer, grows DOWNWARD
;     r31 (ra)    return address, written by JAL
;
; ROUTINES NEST. `call` saves ra on the stack around the JAL and `ret` returns
; through it, so a routine can call another without losing its own return
; address. __square below does exactly that.
;
; None of this needed a new instruction. LOAD and STORE already decoded a `src`
; field they did not use, and r0 reads zero, so making the address BASE +
; OFFSET turned the old absolute form into the special case `addr(r0)` and gave
; register-indirect addressing for free -- which is all a stack ever needed.
; ============================================================================

        .equ DATA_SLOT, 276         ; bank 1, word 20
        ; The stack must stay BELOW the peripheral block, which occupies the
        ; top sixteen words of the address space (0x1F0..0x1FF = 496..511).
        ; It was at 511 before the peripherals existed, which sent every push
        ; to an I/O register instead of to RAM: the pops came back as garbage
        ; and the program never reached HALT. The regression caught it.
        .equ STACK_TOP, 495

; ----------------------------------------------------------------------------
        .bank 0
        .org 0
; ----------------------------------------------------------------------------
start:
        loadi sp, STACK_TOP         ; the stack lives at the top of bank 1
        loadi r3, 10
        loadi r7, 1
        loadi r1, 0
countdown:
        sub   r3, r3, r7            ; r3 -= 1
        bne   r3, r1, countdown     ; loop ten times

        ; ---- one routine, two call sites -----------------------------------
        loadi r4, 6
        loadi r5, 7
        jal   add_pair              ; r6 = 13
        shl   r6, r6, 2             ; r6 = 52
        shr   r8, r6, 1             ; r8 = 26
        store r8, DATA_SLOT         ; a store into the OTHER bank
        load  r9, DATA_SLOT         ; and straight back out of it
        addi  r2, r9, 8             ; r2 = 34
        slt   r10, r2, r3           ; r10 = (34 < 0) = 0
        loadi r4, 20
        loadi r5, 22
        jal   add_pair              ; r6 = 42, from the same routine

        ; ---- multiplication, in software -----------------------------------
        loadi r4, 12
        loadi r5, 11
        jal   __mul                 ; r6 = 132
        move  r16, r6

        ; ---- division, in software -----------------------------------------
        loadi r4, 132
        loadi r5, 11
        jal   __div                 ; r6 = 12, r7 = 0
        move  r17, r6
        move  r18, r7

        loadi r4, 100
        loadi r5, 7
        jal   __div                 ; r6 = 14, r7 = 2
        move  r19, r6
        move  r20, r7

        ; ---- a NESTED call: __square calls __mul ---------------------------
        ; This is the thing that was impossible before the stack. __square has
        ; a return address of its own, and calling __mul would have destroyed
        ; it; `call` pushes it out of the way and pops it back.
        loadi r4, 7
        call  __square              ; r6 = 49
        move  r21, r6

        ; ---- the stack really did unwind -----------------------------------
        move  r22, sp               ; must be back at STACK_TOP

        halt

; ----------------------------------------------------------------------------
add_pair:
        add   r6, r4, r5
        jr    ra

; ============================================================================
; __square -- r6 = r4 * r4, by calling __mul rather than repeating it.
; Uses `call`/`ret`, so it may be called from anywhere and may itself call.
; ============================================================================
__square:
        move  r5, r4
        call  __mul
        ret

; ============================================================================
; __mul -- r6 = r4 * r5, low 32 bits.
;
; Shift and add, the binary long multiplication. It runs once per SET bit of
; the multiplier and at most 32 times, whatever the operands are. The obvious
; alternative -- add the multiplicand r5 times -- runs r5 times, which is fine
; up to about 56 and then degrades without limit: at r5 = 2^31 it would take
; roughly 23 hours on this machine against 2.2 ms here.
;
; Note what this needs: ADD, AND, BEQ and a shift. `add x, x` alone IS a left
; shift, so even the shifts are a convenience rather than a requirement.
;
; clobbers r8, r9, r10, r11
; ============================================================================
__mul:
        loadi r6, 0                 ; product
        loadi r11, 1                ; a register holding one, to test bit 0
        move  r8, r4                ; multiplicand, doubles each round
        move  r9, r5                ; multiplier, halves each round
__mul_loop:
        beq   r9, r0, __mul_done    ; nothing left to add
        and   r10, r9, r11          ; is the low bit set?
        beq   r10, r0, __mul_skip
        add   r6, r6, r8            ; yes: add this power of two
__mul_skip:
        shl   r8, r8, 1
        shr   r9, r9, 1
        jump  __mul_loop
__mul_done:
        jr    ra

; ============================================================================
; __div -- r6 = r4 / r5 and r7 = r4 mod r5, unsigned.
;
; Restoring division: walk the dividend from the top bit down, shifting each
; bit into a remainder and subtracting the divisor whenever it fits. Exactly
; 32 rounds. Repeated subtraction would instead run once per unit of quotient.
;
; A zero divisor returns all ones with the dividend as remainder, the same
; convention the hardware divider used before it was removed. It does not trap,
; because there is no trap mechanism.
;
; clobbers r8, r9, r10, r11, r12
; ============================================================================
__div:
        loadi r6, 0                 ; quotient
        loadi r7, 0                 ; remainder
        beq   r5, r0, __div_zero
        loadi r8, 32                ; rounds remaining
        move  r9, r4                ; dividend, shifts left each round
        loadi r12, 1
__div_loop:
        beq   r8, r0, __div_done
        shl   r7, r7, 1             ; remainder <<= 1
        shr   r10, r9, 31           ; take the dividend's top bit
        add   r7, r7, r10           ; and bring it into the remainder
        shl   r9, r9, 1
        shl   r6, r6, 1             ; quotient <<= 1
        sltu  r11, r7, r5           ; does the divisor fit?
        bne   r11, r0, __div_next   ; no -- this quotient bit stays 0
        sub   r7, r7, r5            ; yes: subtract it
        add   r6, r6, r12           ; and set the quotient bit
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
; The data image. Ordinary memory in the same address space as the code above:
; these words sit at addresses 256..269 and could just as well hold
; instructions.
        .word 0x00000000            ; 0
        .word 0x00000019            ; 25
        .word 0x00000004            ; 4
        .word 0x0000000A            ; 10
        .word 0x0000001E            ; 30
        .word 0x00000001            ; 1
        .word 0x00000002            ; 2
        .word 0xFFFFFFFF            ; -1
        .word 0x000003E8            ; 1000
        .word 0x05F5E100            ; 100,000,000 -- the constant that made the
                                    ; ORIGINAL program run for 1.5 years
        .word 0x0000048D
        .word 0xFFFFF863
        .word 0xFFFFF7EA
        .word 0x000017FC

; Expected final state:
;   r2=34 r3=0 r16=132 r17=12 r18=0 r19=14 r20=2 r21=49 r22=511  mem[276]=26
;
;   r16 = __mul(12, 11)        multiplication, in software
;   r17 = __div(132, 11)       division, in software
;   r19 = __div(100, 7) = 14, r20 = remainder 2
;   r21 = __square(7) = 49     a routine that CALLED another routine
;   r22 = sp back at 495       the stack unwound exactly
