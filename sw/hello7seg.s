; ============================================================================
; hello7seg.s -- the first thing to put on the board.
;
;     python tools/pasm.py sw/hello7seg.s -o memory_image_pkg.vhd
;
; Shows 1234 and stops. That is the whole program, and the number is chosen so
; that one glance settles four separate questions:
;
;   reads "1234"  -> segments, digit order and the multiplexed sweep are all
;                    correct, and the processor is fetching and executing
;   reads "4321"  -> the digit commons are reversed; swap the four
;                    DISPLAY_SELECTOR sites in syn/PHarvard.lpf
;   digits jumbled-> the digit order is some other permutation, same fix
;   wrong glyphs  -> the segment lines are permuted; re-order the DISPLAY sites
;   one digit lit -> the sweep is not running; suspect the clock
;   blank         -> nothing is reaching the display at all
;
; Four different digits, all distinct, none symmetric: 1234 cannot be misread
; under reflection or reordering the way 1111 or 8888 could.
;
; The display latch holds its value, so the program has nothing to do after
; writing it. It halts rather than looping, which also proves HALT works on
; silicon.
; ============================================================================

        .equ DIGITS, 501

        .bank 0
        .org 0

start:
        ; 0x1234 = the four BCD nibbles, most significant first.
        loadi r4, 0x1234
        store r4, DIGITS
        halt
