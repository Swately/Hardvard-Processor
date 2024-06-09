library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Register_File_tb is
end Register_File_tb;

architecture A_Register_File_tb of Register_File_tb is

	--Inputs
	signal clk			: std_logic := '0';
	signal reset		: std_logic := '0';
	signal reg_write	: std_logic := '0';
	signal read_reg1	: std_logic_vector(4 downto 0);
	signal read_reg2	: std_logic_vector(4 downto 0);
	signal write_reg	: std_logic_vector(4 downto 0);
	signal write_data	: std_logic_vector(31 downto 0);
	--Outputs
	signal reg_data1	: std_logic_vector(31 downto 0);
	signal reg_data2	: std_logic_vector(31 downto 0);
	-- Clock period definition
    constant clk_period 		: time := 5 ns;
	--Control signal
	signal regfile_ready    	: std_logic := '0';
	
begin
	
	register_file_inst: entity work.Register_File(A_Register_File)
    port map(
        clk         => clk,
        reset       => reset,
        reg_write   => reg_write,
        read_reg1   => read_reg1,
        read_reg2   => read_reg2,
        write_reg   => write_reg,
        write_data  => write_data,
        reg_data1   => reg_data1,
        reg_data2   => reg_data2,
		ready 		=> regfile_ready 
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
        reg_write <= '0';
        read_reg1 <= (others => '0');
        read_reg2 <= (others => '0');
        write_reg <= (others => '0');
        write_data <= (others => '0');
        wait for 20 ns;
		report("----------End of initialize inputs----------");
		
		report("----------Release reset----------");
		reset <= '0';
        wait for 10 ns;
		report("----------End of release reset----------");
		
		report("----------Test 4: Read data out from registers----------");
		read_reg1 <= "00001";
        read_reg2 <= "00010";
		wait for clk_period;
		report("----------Test 1: Write to a register 1(00001)----------");
		
		report("----------Test 1: Write to a register 1(00001)----------");
		reg_write <= '1';
		write_reg <= "00001";
		write_data <= X"000003EB"; -- 1003 en decimal
		wait for clk_period;
		
		reg_write <= '0';
        wait for clk_period;
		report("----------End of Test 1----------");
		
		report("----------Test 2: Write to a register 2(00010)----------");
		reg_write <= '1';
		write_reg <= "00010";
		write_data <= X"00000065"; -- 101 en decimal
		wait for clk_period;
		
		reg_write <= '0';
        wait for clk_period;
		report("----------End of Test 2----------");
		
		report("----------Test 3: Read data out from registers----------");
		read_reg1 <= "00001";
        read_reg2 <= "00010";
		wait for clk_period;
		
		--Assert the expected values
		assert reg_data1 = X"000003EB" report "Mismatch on read_data1" severity error;
        assert reg_data2 = X"00000065" report "Mismatch on read_data2" severity error;
		report("----------End of Test 3----------");
		
		report("----------End of simulation----------");
		
		wait;
	end process;

end A_Register_File_tb;