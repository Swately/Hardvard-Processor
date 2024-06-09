library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Arithmetic_Logic_Unit_tb is
end Arithmetic_Logic_Unit_tb;

architecture A_Arithmetic_Logic_Unit_tb of Arithmetic_Logic_Unit_tb is

	--Inputs
	signal clk				: std_logic := '0';
	signal reset			: std_logic := '0';
	signal alu_source_a 	: std_logic_vector(31 downto 0) := (others => '0');
	signal alu_source_b 	: std_logic_vector(31 downto 0) := (others => '0');
	signal alu_opcode		: std_logic_vector(3 downto 0) := (others => '0');
	--Outputs
	signal result			: std_logic_vector(31 downto 0) := (others => '0');
	signal result_low		: std_logic_vector(31 downto 0) := (others => '0');
	signal result_high		: std_logic_vector(31 downto 0) := (others => '0');
	signal zero				: std_logic := '0';
	signal sign				: std_logic := '0';
	signal carry			: std_logic := '0';
	signal overflow			: std_logic := '0';
	signal parity			: std_logic := '0';

	-- Clock period definition
    constant clk_period : time := 5 ns;
	
begin
		
	Arithmetic_Logic_Unit_inst: entity work.Arithmetic_Logic_Unit(A_Arithmetic_Logic_Unit)
    port map(
        alu_source_a 	=> alu_source_a,
		alu_source_b 	=> alu_source_b,
		alu_opcode 		=> alu_opcode,
		result 			=> result,
		result_low 		=> result_low,
		result_high 	=> result_high,
		zero 			=> zero,
		sign 			=> sign,
		carry 			=> carry,
		overflow 		=> overflow,
		parity			=> parity
    );
	
	-- Clock process:
    clk_process : process
    begin
        clk <= '0';
        wait for clk_period/2;
        clk <= '1';
        wait for clk_period/2;
    end process;
	
	-- Stimulus process:
	stim_proc:process
	begin
		report("----------Starting simulation----------");
		
		report("----------Initialize inputs----------");
		reset <= '1';
		alu_source_a <= (others => '0');
		alu_source_b <= (others => '0');
		alu_opcode <= (others => '0');
        wait for 20 ns;
		report("----------End of initialize inputs----------");
		
		report("----------Release reset----------");
		reset <= '0';
        wait for 10 ns;
		report("----------End of release reset----------");
		
		report("----------Test 1: Addition----------");
		alu_source_a <= X"000003EB";
		alu_source_b <= X"00000007";
		alu_opcode <= "0000";
		wait for clk_period;
		report "a = " & integer'image(to_integer(unsigned(alu_source_a)));
		report "b = " & integer'image(to_integer(unsigned(alu_source_b)));
		report "result = " & integer'image(to_integer(unsigned(result)));
		report "zero = " & std_logic'image(zero);
		report "carry = " & std_logic'image(carry);
		report "sign = " & std_logic'image(sign);
		report "overflow = " & std_logic'image(overflow);
		wait for 10 ns;
		report("----------End of Test 1----------");
		
		report("----------Test 2: Substraction----------");
		alu_source_a <= X"000003EB";
		alu_source_b <= X"00000007";
		alu_opcode <= "0001";
		wait for clk_period;
		report "a = " & integer'image(to_integer(unsigned(alu_source_a)));
		report "b = " & integer'image(to_integer(unsigned(alu_source_b)));
		report "result = " & integer'image(to_integer(unsigned(result)));
		report "zero = " & std_logic'image(zero);
		report "carry = " & std_logic'image(carry);
		report "sign = " & std_logic'image(sign);
		report "overflow = " & std_logic'image(overflow);
		wait for 10 ns;
		report("----------End of Test 2----------");
		
		report("----------Test 3: Multiplication----------");
		alu_source_a <= X"000003EB";
		alu_source_b <= X"00000007";
		alu_opcode <= "0010";
		wait for clk_period;
		report "a = " & integer'image(to_integer(unsigned(alu_source_a)));
		report "b = " & integer'image(to_integer(unsigned(alu_source_b)));
		report "result = " & integer'image(to_integer(unsigned(result)));
		report "zero = " & std_logic'image(zero);
		report "carry = " & std_logic'image(carry);
		report "sign = " & std_logic'image(sign);
		report "overflow = " & std_logic'image(overflow);
		wait for 10 ns;
		report("----------End of Test 3----------");
		
		report("----------Test 4: Division----------");
		alu_source_a <= X"000003EB";
		alu_source_b <= X"00000007";
		alu_opcode <= "0011";
		wait for clk_period;
		report "a = " & integer'image(to_integer(unsigned(alu_source_a)));
		report "b = " & integer'image(to_integer(unsigned(alu_source_b)));
		report "result = " & integer'image(to_integer(unsigned(result)));
		report "zero = " & std_logic'image(zero);
		report "carry = " & std_logic'image(carry);
		report "sign = " & std_logic'image(sign);
		report "overflow = " & std_logic'image(overflow);
		wait for 10 ns;
		report("----------End of Test 4----------");
		
		report("----------Test 5: and----------");
		alu_source_a <= "10001000001111001000100000010110";
		alu_source_b <= "00001000000111001000100100000000";
		alu_opcode <= "0100";
		wait for clk_period;
		report "a =  " & to_string(alu_source_a);
		report "b =  " & to_string(alu_source_b);
		report "result = " & to_string(result);
		report "zero = " & std_logic'image(zero);
		report "carry = " & std_logic'image(carry);
		report "sign = " & std_logic'image(sign);
		report "overflow = " & std_logic'image(overflow);
		wait for 10 ns;
		report("----------End of Test 5----------");
		
		report("----------Test 6: or----------");
		alu_source_a <= "10001000001111001000100000010110";
		alu_source_b <= "00001000000111001000100100000000";
		alu_opcode <= "0101";
		wait for clk_period;
		report "a =  " & to_string(alu_source_a);
		report "b =  " & to_string(alu_source_b);
		report "result = " & to_string(result);
		report "zero = " & std_logic'image(zero);
		report "carry = " & std_logic'image(carry);
		report "sign = " & std_logic'image(sign);
		report "overflow = " & std_logic'image(overflow);
		wait for 10 ns;
		report("----------End of Test 6----------");
		
		report("----------Test 7: xor----------");
		alu_source_a <= "10001000001111001000100000010110";
		alu_source_b <= "00001000000111001000100100000000";
		alu_opcode <= "0110";
		wait for clk_period;
		report "a =  " & to_string(alu_source_a);
		report "b =  " & to_string(alu_source_b);
		report "result = " & to_string(result);
		report "zero = " & std_logic'image(zero);
		report "carry = " & std_logic'image(carry);
		report "sign = " & std_logic'image(sign);
		report "overflow = " & std_logic'image(overflow);
		wait for 10 ns;
		report("----------End of Test 7----------");
		
		report("----------Test 8: not----------");
		alu_source_a <= "10001000001111001000100000010110";
		alu_opcode <= "0111";
		wait for clk_period;
		report "a =  " & to_string(alu_source_a);
		report "result = " & to_string(result);
		wait for 10 ns;
		report("----------End of Test 8----------");
		
		report("----------Test 9: Substraction to 0----------");
		alu_source_a <= X"00000005";
		alu_source_b <= X"00000005";
		alu_opcode <= "0001";
		wait for clk_period;
		report "a = " & integer'image(to_integer(unsigned(alu_source_a)));
		report "b = " & integer'image(to_integer(unsigned(alu_source_b)));
		report "result = " & integer'image(to_integer(unsigned(result)));
		report "zero = " & std_logic'image(zero);
		report "carry = " & std_logic'image(carry);
		report "sign = " & std_logic'image(sign);
		report "overflow = " & std_logic'image(overflow);
		wait for 10 ns;
		report("----------End of Test 9----------");
		
		report("----------Test 10: Substraction to negative----------");
		alu_source_a <= X"00000001";
		alu_source_b <= X"00000005";
		alu_opcode <= "0001";
		wait for clk_period;
		report "a = " & integer'image(to_integer(unsigned(alu_source_a)));
		report "b = " & integer'image(to_integer(unsigned(alu_source_b)));
		report "result = " & integer'image(to_integer(unsigned(result)));
		report "zero = " & std_logic'image(zero);
		report "carry = " & std_logic'image(carry);
		report "sign = " & std_logic'image(sign);
		report "overflow = " & std_logic'image(overflow);
		wait for 10 ns;
		report("----------End of Test 10----------");
		
		report("----------Test 11: Multiplication to overflow----------");
		alu_source_a <= X"40000000"; -- 1,073,741,824 in decimal
		alu_source_b <= X"00000004"; -- 4 in decimal
		alu_opcode <= "0010";
		wait for clk_period;
		report "a = " & integer'image(to_integer(unsigned(alu_source_a)));
		report "b = " & integer'image(to_integer(unsigned(alu_source_b)));
		report "result = " & integer'image(to_integer(unsigned(result)));
		report "zero = " & std_logic'image(zero);
		report "carry = " & std_logic'image(carry);
		report "sign = " & std_logic'image(sign);
		report "overflow = " & std_logic'image(overflow);
		wait for 10 ns;
		report("----------End of Test 11----------");
		
		report("----------Test 12: Division by zero----------");
		alu_source_a <= X"00000001";
		alu_source_b <= X"00000000";
		alu_opcode <= "0011";
		wait for clk_period;
		report "a = " & integer'image(to_integer(unsigned(alu_source_a)));
		report "b = " & integer'image(to_integer(unsigned(alu_source_b)));
		report "result = " & integer'image(to_integer(unsigned(result)));
		report "zero = " & std_logic'image(zero);
		report "carry = " & std_logic'image(carry);
		report "sign = " & std_logic'image(sign);
		report "overflow = " & std_logic'image(overflow);
		wait for 10 ns;
		report("----------End of Test 12----------");
		
		report("----------Test 13: Multiplication to high and low----------");
		alu_source_a <= X"00010000"; -- 65536 in decimal
        alu_source_b <= X"00010001"; -- 65536 in decimal
		alu_opcode <= "0010";
		wait for clk_period;
		report "a = " & integer'image(to_integer(unsigned(alu_source_a)));
		report "b = " & integer'image(to_integer(unsigned(alu_source_b)));
		report "result = " & integer'image(to_integer(unsigned(result)));
		report "zero = " & std_logic'image(zero);
		report "carry = " & std_logic'image(carry);
		report "sign = " & std_logic'image(sign);
		report "overflow = " & std_logic'image(overflow);
		wait for 10 ns;
		report("----------End of Test 13----------");
		
		report("----------End of simulation----------");
		
		wait;
	end process;

end A_Arithmetic_Logic_Unit_tb;