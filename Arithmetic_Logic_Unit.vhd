library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Arithmetic_Logic_Unit is
	port(
		alu_source_a, alu_source_b: in std_logic_vector(31 downto 0);
		alu_opcode: in std_logic_vector(3 downto 0);
		result, result_low, result_high: out std_logic_vector(31 downto 0) := (others => '0');
		zero, sign, carry, overflow, parity, ready: out std_logic := '0'
	);
end Arithmetic_Logic_Unit;

architecture A_Arithmetic_Logic_Unit of Arithmetic_Logic_Unit is
	signal internal_a, internal_b : std_logic_vector(31 downto 0) := (others => '0');
begin

	process(alu_source_a, alu_source_b, alu_opcode)
		variable temp_result		: signed(32 downto 0) := (others => '0');
		variable temp_result_mul	: signed(63 downto 0) := (others => '0');
		variable parity_count 		: integer;
	begin
	
		if alu_source_a /= internal_a or alu_source_b /= internal_b then
			temp_result := (others => '0');
			temp_result_mul := (others => '0');
		end if;
		
		case alu_opcode is
			when "0000" => --Addition
				temp_result := signed('0' & alu_source_a) + signed('0' & alu_source_b);
				result <= std_logic_vector(temp_result(31 downto 0));
				sign <= temp_result(31);
				carry <= temp_result(32);
				if (alu_source_a(31) = alu_source_b(31)) and (alu_source_a(31) /= temp_result(31)) then
					overflow <= '1';
				else
					overflow <= '0';
				end if;
	
			when "0001" => --Substraction
				temp_result := signed('0' & alu_source_a) - signed('0' & alu_source_b);
				result <= std_logic_vector(temp_result(31 downto 0));
				sign <= temp_result(31);
				carry <= temp_result(32);
				if (alu_source_a(31) /= alu_source_b(31)) and (alu_source_a(31) = temp_result(31)) then
					overflow <= '1';
				else
					overflow <= '0';
				end if;
			
			when "0010" => -- Multiplication
				temp_result_mul := signed(alu_source_a) * signed(alu_source_b);
				result <= std_logic_vector(temp_result_mul(31 downto 0));
				carry <= '0'; 
				sign <= temp_result_mul(31);
				result_low <= std_logic_vector(temp_result_mul(31 downto 0));
				result_high <= std_logic_vector(temp_result_mul(63 downto 32));
				if temp_result_mul(63 downto 32) /= "00000000000000000000000000000000" then
					overflow <= '1';
				else
					overflow <= '0';
				end if;
				
			when "0011" => -- Division
				if alu_source_b /= "00000000000000000000000000000000" then
					result <= std_logic_vector(signed(alu_source_a) / signed(alu_source_b));
					sign <= temp_result(31);
					if alu_source_a = x"80000000" and alu_source_b = x"FFFFFFFF" then
						overflow <= '1';
					else
						overflow <= '0';
					end if;
				else
					result <= (others => 'X');
					overflow <= '0';
				end if;
				carry <= '0';
				
			when "0100" => --and
				result <= alu_source_a and alu_source_b;
				
			when "0101" => --or
				result <= alu_source_a or alu_source_b;
				
			when "0110" => --xor
				result <= alu_source_a xor alu_source_b;
				
			when "0111" => --not
				result <= not alu_source_a;
				
			when "1000" => --pass-trough
				result <= alu_source_a;
			when others =>
				result <= (others => '0');
				carry <= '0';
		end case;
		
		if temp_result(31 downto 0) = 0 then
			zero <= '1';
		else
			zero <= '0';
		end if;
		
	end process;
	internal_a <= alu_source_a;
	internal_b <= alu_source_b;
end A_Arithmetic_Logic_Unit;