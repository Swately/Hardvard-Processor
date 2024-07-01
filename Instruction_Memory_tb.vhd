library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Instruction_Memory_tb is
end Instruction_Memory_tb;

architecture A_Instruction_Memory_tb of Instruction_Memory_tb is

	--Inputs
	signal clk						: std_logic := '0';
	signal reset					: std_logic := '0';
	signal instruction_address_in	: std_logic_vector(7 downto 0) := (others => '0');
	
	--Outputs
	signal data_out					: std_logic_vector(31 downto 0) := (others => '0');
	signal instruction_address_out	: std_logic_vector(7 downto 0) := (others => '0');
	
	-- Clock period definition
    constant clk_period : time := 5 ns;
	-- Control signals
	signal ins_memory_ready			: std_logic := '0';
begin

	Instruction_Memory_Address_Register_inst: entity work.Instruction_Memory_Address_Register(A_Instruction_Memory_Address_Register)
    port map(
        clk => clk,
		reset => reset,
		ready => ins_memory_ready,
		instruction_address_in => instruction_address_in,
		instruction_address_out => instruction_address_out
    );
		
	Instruction_Memory_inst: entity work.Instruction_Memory(A_Instruction_Memory)
    port map(
        instruction_address_in => instruction_address_out,
		data_out => data_out
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
		instruction_address_in <= (others => '0');
        wait for 20 ns;
		
		report("----------End of initialize inputs----------");
		
		report("----------Release reset----------");
		reset <= '0';
        wait for 10 ns;
		report("----------End of release reset----------");
		
		report("----------Test 1: Read instrction memory----------");
		instruction_address_in <= "00000001";
		wait for 10 ns;
		report "data_out = " & to_string(data_out);
		instruction_address_in <= "00000011";
		wait for 10 ns;
		report "data_out = " & to_string(data_out);
		instruction_address_in <= "00001010";
		wait for 10 ns;
		report "data_out = " & to_string(data_out);
		report("----------End of Test 1----------");
		
		report("----------End of simulation----------");
		
		wait;
	end process;

end A_Instruction_Memory_tb;