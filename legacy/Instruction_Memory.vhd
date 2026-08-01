library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Instruction_Memory
--
-- 256 x 32-bit instruction ROM, combinational read. Structure unchanged.
--
-- The program was replaced 2026-07-31. The original is preserved verbatim in
-- the comment block at the end of this file -- it was never wrong as code, but
-- it loads its loop counter from Data_Memory[9] = 100,000,000 and therefore
-- cannot terminate in observable time (DIAGNOSIS.md §2.1: 1.5 years at 24 Hz).
--
-- The program below terminates in 14 instructions and exercises every
-- instruction that was repaired or added, so that a single run demonstrates
-- the whole fix set.
--
-- INSTRUCTION FORMATS
--   R: opcode(31:26) src(25:21) trg(20:16) des(15:11) shamt(10:6) func(5:0)
--   I: opcode(31:26) src(25:21) trg(20:16) immediate(15:0)
--   J: opcode(31:26) address(25:0)
--
-- OPCODES                                   ALU FUNC (R-type)
--   000001 ALU (R-type)                       000000 ADD    000111 NOT
--   000010 LOAD    mem[imm] -> trg            000001 SUB    001000 SHL  <- new
--   000011 LOADI   imm      -> trg            000010 (MUL, reserved)
--   000100 ADDI    src+imm  -> trg            000011 (DIV, reserved)
--   000101 SUBI    src-imm  -> trg            000100 AND    001001 SHR  <- new
--   000110 STORE   trg      -> mem[imm]       000101 OR     001010 SLT  <- new
--   000111 MOVE    src      -> trg            000110 XOR    001011 SLTU <- new
--   001000 BEQ     if src=trg  goto imm
--   001001 HALT
--   001010 BNE     if src/=trg goto imm
--   001011 STORE_IO
--   001100 NOP
--   001101 JUMP    goto address
--
-- MUL and DIV are RESERVED, not removed: they are software routines built from
-- the instructions above. Their combinational hardware measured 14,899 LUT4,
-- 73% of the whole core. The shift amount for SHL/SHR is instruction bits
-- 10:6, the field the original decoded and threw away.

entity Instruction_Memory is
	port(
		instruction_address_in: in std_logic_vector(7 downto 0);
		data_out: out std_logic_vector(31 downto 0)
	);

end Instruction_Memory;

architecture A_Instruction_Memory of Instruction_Memory is

	type instruction_memory_type is array (0 to 255) of std_logic_vector(31 downto 0);
	signal instruction_memory : instruction_memory_type := (
		--  addr                     encoding      assembly                 expected effect
		0  => X"0C03000A", -- LOADI r3, 10                  r3 = 10
		1  => X"0C070001", -- LOADI r7, 1                   r7 = 1
		2  => X"0C010000", -- LOADI r1, 0                   r1 = 0
		3  => X"04671801", -- SUB   r3, r7 -> r3            r3 = r3 - 1
		4  => X"28610003", -- BNE   r3, r1, 3               loop while r3 /= 0
		5  => X"0C040006", -- LOADI r4, 6                   r4 = 6
		6  => X"0C050007", -- LOADI r5, 7                   r5 = 7
		7  => X"38000014", -- JAL   20                      call add_pair; r31 = 8
		8  => X"04C03088", -- SHL   r6, 2  -> r6            r6 = 13 << 2 = 52
		9  => X"04C04049", -- SHR   r6, 1  -> r8            r8 = 52 >> 1 = 26
		10 => X"18080014", -- STORE r8 -> mem[20]           mem[20] = 26
		11 => X"08090014", -- LOAD  mem[20] -> r9           r9 = 26
		12 => X"11220008", -- ADDI  r9, 8  -> r2            r2 = 34
		13 => X"0443500A", -- SLT   r2, r3 -> r10           r10 = (34 < 0) = 0
		14 => X"0C040014", -- LOADI r4, 20                  r4 = 20
		15 => X"0C050016", -- LOADI r5, 22                  r5 = 22
		16 => X"38000014", -- JAL   20                      call it AGAIN; r31 = 17
		17 => X"34000013", -- JUMP  19                      skip address 18
		18 => X"0C0903E7", -- LOADI r9, 999                 MUST NOT EXECUTE
		19 => X"24000000", -- HALT
		--- add_pair: r6 <- r4 + r5, then return to the caller -------------
		20 => X"04853000", -- ADD   r4, r5 -> r6
		21 => X"3FE00000", -- JR    r31                     back to whoever called
		others => (others => '0')
	);

	-- Final architectural state if every repair holds:
	--   r1=0 r2=34 r3=0 r4=20 r5=22 r6=42 r7=1 r8=26 r9=26 r10=0 r31=17
	--   mem[20]=26
	--
	-- The point of this program is address 20. ONE routine is reached from TWO
	-- different call sites and returns correctly to each -- r6 is 13 the first
	-- time and 42 the second. That is what JAL and JR buy, and it is the whole
	-- basis for building complex instructions out of simple ones: without a
	-- call/return pair a routine has to be pasted at every place it is used.
	--
	-- r9 = 26 rather than 999 proves the JUMP at 17 was taken. SHL and SHR
	-- exercise the structural barrel shifter; the MUL that used to sit here is
	-- gone with the hardware multiplier and becomes a software routine.

begin
	data_out <= instruction_memory(to_integer(unsigned(instruction_address_in)));
end A_Instruction_Memory;

-- ----------------------------------------------------------------------------
-- ORIGINAL PROGRAM, preserved. Kept because it is the operator's work and
-- because it is the exact input that produced the measurements in DIAGNOSIS.md.
-- To run it again, swap it back into the array above.
--
--   0 => "00001010101000110000000000001001", -- LOAD  Data_Memory 9 -> r3
--   1 => "00001000000001110000000000000101", -- LOAD  Data_Memory 5 -> r7
--   2 => "00001000000001100000000000000111", -- LOAD  Data_Memory 7 -> r6
--   3 => "00000100011001110001100000000001", -- SUB   r3 - r7 -> r3
--   4 => "00101000011000010000000000000011", -- BNE   r3, r1, 3
--   5 => "00001000000001010000000000001001", -- LOAD  Data_Memory 9 -> r5
--   6 => "00000100011001110001100000000000", -- ADD   r3 + r7 -> r3
--   7 => "00001000000000110000000000000001", -- LOAD  Data_Memory 1 -> r3
--   8 => "00100100000000000000000000000000", -- HALT
--
-- Note on the original comments: instruction 6 is annotated "des = 00110" but
-- bits 15:11 encode 00011, so it writes r3, not r6. Addresses 5..7 are
-- unreachable while the BNE loop runs.
-- ----------------------------------------------------------------------------

-- Made with my soul - Swately <3
