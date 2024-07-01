library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Arithmetic_Logic_Unit is
	port(
		alu_source_a, alu_source_b: in std_logic_vector(31 downto 0);
		alu_opcode: in std_logic_vector(3 downto 0);
		result, result_low, result_high: out std_logic_vector(31 downto 0) := (others => '0');
		zero, sign_flag, carry, overflow, parity, ready: out std_logic := '0'
	);
end Arithmetic_Logic_Unit;

architecture A_Arithmetic_Logic_Unit of Arithmetic_Logic_Unit is
	signal internal_result 				: std_logic_vector(31 downto 0);
	signal internal_result_add			: std_logic_vector(32 downto 0) := (others => '0');
	signal internal_result_sub			: std_logic_vector(32 downto 0) := (others => '0');
	signal internal_result_low 			: std_logic_vector(31 downto 0) := (others => '0');
	signal internal_result_high 		: std_logic_vector(31 downto 0) := (others => '0');
	signal internal_result_add_r		: std_logic_vector(31 downto 0) := (others => '0');
	signal internal_result_sub_r		: std_logic_vector(31 downto 0) := (others => '0');
	signal internal_alu_source_a 		: std_logic_vector(31 downto 0) := (others => '0');
	signal internal_alu_source_b 		: std_logic_vector(31 downto 0) := (others => '0');
	signal internal_alu_opcode 			: std_logic_vector(3 downto 0) := (others => '0');

	signal internal_zero 			: std_logic := '0';
	signal internal_sign_flag 		: std_logic := '0';
	signal internal_carry_add 		: std_logic := '0';
	signal internal_carry_sub 		: std_logic := '0';
	signal internal_carry			: std_logic := '0';
	signal internal_overflow 		: std_logic := '0';
	signal internal_parity 			: std_logic := '0';

	component Full_Adder_32bits
		port(
			entry_a, entry_b: in std_logic_vector(31 downto 0);
			mode: in std_logic;
			result: out std_logic_vector(32 downto 0);
			carry_out : out std_logic
		);
	end component;

begin
	
	internal_alu_source_a <= alu_source_a;
	internal_alu_source_b <= alu_source_b;
	internal_alu_opcode <= alu_opcode;
	internal_result_add_r <= internal_result_add(31 downto 0);
	internal_result_sub_r <= internal_result_sub(31 downto 0);


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
	
	
	process(all)
	begin
		case internal_alu_opcode is
			when "0000" =>
				internal_result <= internal_result_add_r;
				internal_carry <= internal_carry_add;

			when "0001" =>
				internal_result <= internal_result_sub_r;
				internal_carry <= internal_carry_sub;
				
			when "0100" =>
				internal_result <= internal_alu_source_a and internal_alu_source_b;
			
			when "0101" =>
				internal_result <= internal_alu_source_a or internal_alu_source_b;

			when "0110" =>
				internal_result <= internal_alu_source_a xor internal_alu_source_b;

			when "0111" =>
				internal_result <= not internal_alu_source_a;

			when "1000" =>
				internal_result <= internal_alu_source_a;

			when others =>
				internal_result <= (others => '0');
				internal_carry <= '0';
		end case;

		if internal_result = "00000000000000000000000000000000" then
			internal_zero <= '1';
		else
			internal_zero <= '0';
		end if;

	end process;

	result <= internal_result;
	result_low <= internal_result_low;
	result_high <= internal_result_high;
	zero <= internal_zero;
	sign_flag <= internal_sign_flag;
	carry <= internal_carry;
	overflow <= internal_overflow;
	parity <= internal_parity;

	
end A_Arithmetic_Logic_Unit;
