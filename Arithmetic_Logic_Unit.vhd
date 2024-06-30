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
	signal internal_result 				: std_logic_vector(31 downto 0) := (others => 'X');
	signal internal_result_low 			: std_logic_vector(31 downto 0) := (others => 'X');
	signal internal_result_high 		: std_logic_vector(31 downto 0) := (others => 'X');
	signal internal_alu_source_a 		: std_logic_vector(31 downto 0) := (others => 'X');
	signal internal_alu_source_b 		: std_logic_vector(31 downto 0) := (others => 'X');
	signal internal_alu_opcode 			: std_logic_vector(3 downto 0) := (others => 'X');

	signal internal_zero 			: std_logic := '0';
	signal internal_sign_flag 		: std_logic := '0';
	signal internal_carry 			: std_logic := '0';
	signal internal_overflow 		: std_logic := '0';
	signal internal_parity 			: std_logic := '0';

begin
	
	internal_alu_source_a <= alu_source_a;
	internal_alu_source_b <= alu_source_b;
	internal_alu_opcode <= alu_opcode;
	
	process(internal_alu_source_a, internal_alu_source_b, internal_alu_opcode)
		variable temp_result		: signed(32 downto 0) := (others => '0');
		variable temp_result_mul	: signed(63 downto 0) := (others => '0');
	begin
		case internal_alu_opcode is
			when "0000" =>
				temp_result := signed('0' & internal_alu_source_a) + signed('0' & internal_alu_source_b);
				internal_result <= std_logic_vector(temp_result(31 downto 0));
				internal_sign_flag <= temp_result(31);
				internal_carry <= temp_result(32);

				if (internal_alu_source_a(31) = internal_alu_source_b(31)) and (internal_alu_source_a(31) /= temp_result(31)) then
					internal_overflow <= '1';
				else
					internal_overflow <= '0';
				end if;

			when "0001" =>
				temp_result := signed('0' & internal_alu_source_a) - signed('0' & internal_alu_source_b);
				internal_result <= std_logic_vector(temp_result(31 downto 0));
				internal_sign_flag <= temp_result(31);
				internal_carry <= temp_result(32);

				if (internal_alu_source_a(31) = internal_alu_source_b(31)) and (internal_alu_source_a(31) /= temp_result(31)) then
					internal_overflow <= '1';
				else
					internal_overflow <= '0';
				end if;

			when "0010" =>
				temp_result_mul := signed(internal_alu_source_a) * signed(internal_alu_source_b);
				internal_result <= std_logic_vector(temp_result_mul(31 downto 0));
				internal_result_low <= std_logic_vector(temp_result_mul(31 downto 0));
				internal_result_high <= std_logic_vector(temp_result_mul(63 downto 32));
				internal_carry <= '0';
				internal_sign_flag <= temp_result_mul(31);

				if temp_result_mul(63 downto 32) /= "00000000000000000000000000000000" then
					internal_overflow <= '1';
				else
					internal_overflow <= '0';
				end if;

				--when "0011" =>
				--	if internal_alu_source_b /= "00000000000000000000000000000000" then
				--		temp_result := signed(internal_alu_source_a) / signed(internal_alu_source_b);
				--		internal_result <= std_logic_vector(temp_result(31 downto 0));
				--		internal_sign_flag <= temp_result(31);

				--		if internal_alu_source_a = X"80000000" and internal_alu_source_b = X"FFFFFFFF" then
				--			internal_overflow <= '1';
				--		else
				--			internal_overflow <= '0';
				--		end if;
				--	else
				--		internal_result <= (others => '0');
				--			internal_overflow <= '0';
				--	end if;
				--	internal_carry <= '0';
				
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
