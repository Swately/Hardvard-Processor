library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Central_Processing_Unit_tb is
end Central_Processing_Unit_tb;

architecture A_Central_Processing_Unit_tb of Central_Processing_Unit_tb is

	--Inputs
	signal clk				: std_logic := '0';
	signal reset			: std_logic := '0';
	--Outputs
	
	-- Clock period definition
    constant clk_period : time := 5 ns;
	
	--Control Signals
	
	
begin
		
	Central_Processing_Unit_inst: entity work.Central_Processing_Unit(A_Central_Processing_Unit)
    port map(
        clk => clk,
		reset => reset
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
        
        wait for 20 ns;
		report("----------End of initialize inputs----------");
		
		report("----------Release reset----------");
		reset <= '0';
        wait for 10 ns;
		report("----------End of release reset----------");
		
		report("----------Test 1: ----------");
		
		
		report("----------End of Test 1----------");
		
		report("----------End of simulation----------");
		
		wait;
	end process;

end A_Central_Processing_Unit_tb;