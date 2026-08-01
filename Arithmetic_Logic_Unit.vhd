library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Arithmetic_Logic_Unit -- structural.
--
-- Every operand of the output multiplexer is produced by a block built from
-- primitives; the multiplexer itself only SELECTS BETWEEN WIRES. That is the
-- rule this file now follows and the previous version did not: the old case
-- statement contained `*` and `/`, so the "ALU" was partly a request to the
-- synthesiser rather than a description of a circuit.
--
-- What each result comes from:
--   add / sub   Full_Adder_32bits, 32 ripple-carry full adders (Full_Adder.vhd)
--   shl / shr   shifter_32, a five-stage barrel shifter of mux2 cells
--   and/or/xor/not   one gate per bit, which is what the vector operators are
--   slt / sltu  the subtractor's carry and sign, plus three gates
--   pass a / b  wiring
--
-- MUL AND DIV ARE NO LONGER HARDWARE. The reason is the project's purpose, not
-- area: complex operations are meant to be built from simple ones here.
--
-- An earlier version of this comment claimed they cost 14,899 LUT4, 73% of the
-- core. That was an OPEN-SOURCE ESTIMATE, not a fitting result, and the vendor
-- flow later put the same blocks at 2,613 LUT4 plus 1,706 carry cells --
-- roughly 8x smaller, because the estimator cannot use the part's hardened
-- carry chains. The area argument was wrong; the design argument was never
-- about area. See syn/VENDOR_VS_ESTIMATE.md. They are
-- now software routines built from the instructions below, which is what
-- RISC-V's RV32I does without the M extension (`__mulsi3`, `__divsi3`). Their
-- ALU opcodes are kept RESERVED rather than reused, so the original design
-- intent stays visible and an old program cannot silently mean something new.
--
-- Shift-and-add multiply needs no right shift at all: `ADD x,x` IS a left
-- shift by one, and a mask that doubles each iteration replaces testing bits
-- with a right shift. So MUL is expressible with ADD, AND and BEQ alone.

entity Arithmetic_Logic_Unit is
	port(
		alu_source_a, alu_source_b: in std_logic_vector(31 downto 0);
		alu_opcode: in std_logic_vector(3 downto 0);
		shamt: in std_logic_vector(4 downto 0) := (others => '0');
		result, result_low, result_high: out std_logic_vector(31 downto 0) := (others => '0');
		zero, sign_flag, carry, overflow, parity, ready: out std_logic := '0'
	);
end Arithmetic_Logic_Unit;

architecture A_Arithmetic_Logic_Unit of Arithmetic_Logic_Unit is

	-- ------------------------------------------------------------------
	-- ALU opcode map
	-- ------------------------------------------------------------------
	constant OP_ADD   : std_logic_vector(3 downto 0) := "0000";
	constant OP_SUB   : std_logic_vector(3 downto 0) := "0001";
	-- "0010" and "0011" were MUL and DIV. RESERVED: software routines now.
	constant OP_AND   : std_logic_vector(3 downto 0) := "0100";
	constant OP_OR    : std_logic_vector(3 downto 0) := "0101";
	constant OP_XOR   : std_logic_vector(3 downto 0) := "0110";
	constant OP_NOT   : std_logic_vector(3 downto 0) := "0111";
	constant OP_PASSA : std_logic_vector(3 downto 0) := "1000";
	constant OP_PASSB : std_logic_vector(3 downto 0) := "1001";
	constant OP_SHL   : std_logic_vector(3 downto 0) := "1010";
	constant OP_SHR   : std_logic_vector(3 downto 0) := "1011";
	constant OP_SLT   : std_logic_vector(3 downto 0) := "1100";
	constant OP_SLTU  : std_logic_vector(3 downto 0) := "1101";

	signal internal_result 				: std_logic_vector(31 downto 0) := (others => '0');
	signal internal_result_add			: std_logic_vector(32 downto 0) := (others => '0');
	signal internal_result_sub			: std_logic_vector(32 downto 0) := (others => '0');
	signal internal_result_add_r		: std_logic_vector(31 downto 0) := (others => '0');
	signal internal_result_sub_r		: std_logic_vector(31 downto 0) := (others => '0');
	signal internal_alu_source_a 		: std_logic_vector(31 downto 0) := (others => '0');
	signal internal_alu_source_b 		: std_logic_vector(31 downto 0) := (others => '0');
	signal internal_alu_opcode 			: std_logic_vector(3 downto 0) := (others => '0');

	signal internal_carry_add 		: std_logic := '0';
	signal internal_carry_sub 		: std_logic := '0';
	signal internal_carry			: std_logic := '0';
	signal internal_overflow 		: std_logic := '0';
	signal internal_ovf_add			: std_logic := '0';
	signal internal_ovf_sub			: std_logic := '0';

	-- Shifter
	signal shift_dir    : std_logic := '0';
	signal shift_result : std_logic_vector(31 downto 0) := (others => '0');

	-- Comparison results, one bit widened to a word
	signal lt_signed, lt_unsigned : std_logic := '0';
	signal slt_word, sltu_word    : std_logic_vector(31 downto 0) := (others => '0');

	constant ZEROS : std_logic_vector(31 downto 0) := (others => '0');

	component Full_Adder_32bits
		port(
			entry_a, entry_b: in std_logic_vector(31 downto 0);
			mode: in std_logic;
			result: out std_logic_vector(32 downto 0);
			carry_out : out std_logic
		);
	end component;

	component shifter_32
		port (
			data   : in  std_logic_vector(31 downto 0);
			shamt  : in  std_logic_vector(4 downto 0);
			dir    : in  std_logic;
			result : out std_logic_vector(31 downto 0)
		);
	end component;

begin

	internal_alu_source_a <= alu_source_a;
	internal_alu_source_b <= alu_source_b;
	internal_alu_opcode <= alu_opcode;
	internal_result_add_r <= internal_result_add(31 downto 0);
	internal_result_sub_r <= internal_result_sub(31 downto 0);

	-- ------------------------------------------------------------------
	-- Arithmetic: two ripple-carry adders, one adding and one subtracting.
	-- ------------------------------------------------------------------
	Full_Adder_Add: Full_Adder_32bits
		port map(
			entry_a => internal_alu_source_a,
			entry_b => internal_alu_source_b,
			mode => '0',
			result => internal_result_add,
			carry_out => internal_carry_add
		);

	Full_Adder_Sub: Full_Adder_32bits
		port map(
			entry_a => internal_alu_source_a,
			entry_b => internal_alu_source_b,
			mode => '1',
			result => internal_result_sub,
			carry_out => internal_carry_sub
		);

	-- ------------------------------------------------------------------
	-- Shift: one barrel shifter serves both directions.
	-- ------------------------------------------------------------------
	shift_dir <= '1' when internal_alu_opcode = OP_SHR else '0';

	Shifter: shifter_32
		port map (
			data   => internal_alu_source_a,
			shamt  => shamt,
			dir    => shift_dir,
			result => shift_result
		);

	-- ------------------------------------------------------------------
	-- Flags, from gates rather than from a comparison operator.
	-- ------------------------------------------------------------------
	-- Signed overflow: the operands agree in sign and the result disagrees
	-- (add), or they differ in sign and the result takes the subtrahend's
	-- (sub).
	internal_ovf_add <= (not (internal_alu_source_a(31) xor internal_alu_source_b(31)))
	                    and (internal_result_add_r(31) xor internal_alu_source_a(31));
	internal_ovf_sub <= (internal_alu_source_a(31) xor internal_alu_source_b(31))
	                    and (internal_result_sub_r(31) xor internal_alu_source_a(31));

	-- a < b, signed: the sign of a-b, corrected for overflow.
	lt_signed   <= internal_result_sub_r(31) xor internal_ovf_sub;
	-- a < b, unsigned: a borrow came out of a-b, i.e. no carry.
	lt_unsigned <= not internal_carry_sub;

	slt_word  <= ZEROS(31 downto 1) & lt_signed;
	sltu_word <= ZEROS(31 downto 1) & lt_unsigned;

	-- ------------------------------------------------------------------
	-- Output multiplexer. It SELECTS, it does not compute: every arm below
	-- is a wire coming from a block above.
	-- ------------------------------------------------------------------
	with internal_alu_opcode select internal_result <=
		internal_result_add_r                                  when OP_ADD,
		internal_result_sub_r                                  when OP_SUB,
		(internal_alu_source_a and internal_alu_source_b)      when OP_AND,
		(internal_alu_source_a or  internal_alu_source_b)      when OP_OR,
		(internal_alu_source_a xor internal_alu_source_b)      when OP_XOR,
		(not internal_alu_source_a)                            when OP_NOT,
		internal_alu_source_a                                  when OP_PASSA,
		internal_alu_source_b                                  when OP_PASSB,
		shift_result                                           when OP_SHL,
		shift_result                                           when OP_SHR,
		slt_word                                               when OP_SLT,
		sltu_word                                              when OP_SLTU,
		ZEROS                                                  when others;

	with internal_alu_opcode select internal_carry <=
		internal_carry_add when OP_ADD,
		internal_carry_sub when OP_SUB,
		'0'                when others;

	with internal_alu_opcode select internal_overflow <=
		internal_ovf_add when OP_ADD,
		internal_ovf_sub when OP_SUB,
		'0'              when others;

	result <= internal_result;

	-- MUL and DIV published these; with those gone they carry nothing. Kept as
	-- ports so the interface does not churn, parked at zero.
	result_low  <= (others => '0');
	result_high <= (others => '0');

	-- Reduction operators are gate trees: `or` over a vector is a 32-input OR
	-- built from 2-input gates, which is exactly the zero-detect circuit.
	zero      <= not (or internal_result);
	parity    <= not (xor internal_result);
	sign_flag <= internal_result(31);
	carry     <= internal_carry;
	overflow  <= internal_overflow;
	ready     <= '1';

end A_Arithmetic_Logic_Unit;

-- Made with my soul - Swately <3
