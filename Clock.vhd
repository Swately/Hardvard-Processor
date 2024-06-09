library ieee;
use ieee.std_logic_1164.all;

entity Clock_Generator is
	port(
		clk_out: out std_logic	
	);
end Clock_Generator;

architecture A_Clock_Generator of Clock_Generator is
	constant clk_period: time := 10 ns;
begin
	process
	begin
		clk_out <= '0';
        wait for clk_period / 2;
        clk_out <= '1';
        wait for clk_period / 2;
	end process;
	
end A_Clock_Generator;