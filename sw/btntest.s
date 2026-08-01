; ============================================================================
; btntest.s -- what does the button actually do?
;
;     python tools/pasm.py sw/btntest.s -o memory_image_pkg.vhd
;
; Three instructions: read the button register, put it on the display, repeat.
; No game, no timing, no interpretation -- just the five bits as they arrive at
; the processor.
;
; WHY THIS IS NEEDED. projects/holith/boards/BOARD_PINMAP.md lists the five
; tactile buttons and says "sense TBD": nobody ever established whether a press
; drives the pin high or pulls it to ground. That is not a detail. A program
; that guesses wrong either never sees a press, or thinks the button is held
; down forever.
;
; It also cannot be settled by watching the slot machine. The reels changing
; does NOT prove the button works -- sampling a free-running LFSR at a fixed
; interval produces a sequence whose period is billions of spins long, so it
; looks perfectly random with nobody touching anything. Reading randomness as
; evidence of input was a wrong call; this program is what actually answers it.
;
; The middle button is pin 110, which is buttons(1), so bit 1 is the one to
; watch. It is constrained PULLMODE=UP for this test, which is the arrangement
; a tactile switch usually wants: the resistor holds the pin high and pressing
; shorts it to ground.
;
;     resting  0002    bit 1 high -- the pull-up is holding it
;     pressed  0000    the button pulls it down: ACTIVE LOW, and it works
;
; If instead the display sits at 0000 and pressing gives 0002, the button
; drives the pin high and the sense is active high. If nothing changes at all,
; pin 110 is not reaching the processor and the number came from a photograph.
;
; Any of those three is an answer. Only the last one is bad news, and even then
; it is four remaining candidates rather than a mystery.
; ============================================================================

        .equ BUTTONS,  499
        .equ DIGITS,   501

        .bank 0
        .org 0

loop:
        load  r4, BUTTONS
        store r4, DIGITS
        jump  loop

; Made with my soul - Swately <3
