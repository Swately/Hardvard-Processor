library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Data_Memory_tb is
end Data_Memory_tb;

architecture A_Data_Memory_tb of Data_Memory_tb is

	--Inputs
	
	signal clk 					: std_logic := '0';
	signal reset				: std_logic := '0';
	signal write_data_enable	: std_logic := '0';
	signal data_address_in		: std_logic_vector(31 downto 0) := (others => '0');
	signal data_in				: std_logic_vector(31 downto 0) := (others => '0');
	
	--Outputs
	
	signal data_address_out		: std_logic_vector(31 downto 0) := (others => '0');
	signal data_out				: std_logic_vector(31 downto 0) := (others => '0');
	
	-- Clock period definition
    constant clk_period : time := 5 ns;
	
	--Control Signal
	signal data_memory_ready    : std_logic := '0';
	signal data_register_ready  : std_logic := '0';
	
begin

	Data_Memory_Address_Register_inst: entity work.Data_Memory_Address_Register(A_Data_Memory_Address_Register)
    port map(
        clk => clk,
		ready => data_register_ready,
		reset => reset,
		data_address_in => data_address_in,
		data_address_out => data_address_out
    );
		
	Data_Memory_inst: entity work.Data_Memory(A_Data_Memory)
    port map(
        clk => clk,
		reset => reset,
		ready => data_memory_ready,
		data_register_ready => data_register_ready,
		write_data_enable => write_data_enable,
		data_address_in => data_address_out,
		data_in => data_in,
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
		write_data_enable <= '0';
		data_address_in <= (others => '0');
		data_in <= (others => '0');
        wait for 20 ns;
		
		report("----------End of initialize inputs----------");
		
		report("----------Release reset----------");
		reset <= '0';
        wait for 10 ns;
		report("----------End of release reset----------");
		
		report("----------Test 2: store data----------");
		write_data_enable <= '1';
		data_address_in <= X"00000009";
		data_in <= X"0000000F";
		wait for clk_period;
		report "data out = " & integer'image(to_integer(unsigned(data_out)));
		wait for 10 ns;
		report("----------End of Test 2----------");
		
		report("----------Test 1: read data----------");
		write_data_enable <= '0';
		data_address_in <= X"0000000A";
		wait for clk_period;
		report "data out = " & integer'image(to_integer(unsigned(data_out)));
		wait for 10 ns;
		report("----------End of Test 1----------");
		
		
		
		report("----------Test 3: read data----------");
		write_data_enable <= '0';
		data_address_in <= X"00000001";
		wait for clk_period;
		report "data out = " & integer'image(to_integer(unsigned(data_out)));
		wait for 10 ns;
		report("----------End of Test 3----------");
		
		report("----------Test 4: store data----------");
		write_data_enable <= '1';
		data_address_in <= X"00000001";
		data_in <= X"00000014";
		wait for clk_period;
		report "data out = " & integer'image(to_integer(unsigned(data_out)));
		wait for 10 ns;
		report("----------End of Test 4----------");
		
		report("----------End of simulation----------");
		
		wait;
	end process;

end A_Data_Memory_tb;