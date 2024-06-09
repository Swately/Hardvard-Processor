library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Program_Counter_tb is
end Program_Counter_tb;

architecture A_Program_Counter_tb of Program_Counter_tb is

    -- Inputs
    signal clk               : std_logic := '0';
    signal reset             : std_logic := '0';
    signal pc_address_in     : std_logic_vector(31 downto 0) := (others => '0'); 
    
    -- Outputs
    signal pc_address_out    		: std_logic_vector(31 downto 0) := (others => '0');
    signal pc_ready          		: std_logic := '0'; 
    
    -- Clock period definition
    constant clk_period : time := 5 ns;
    
begin
        
    Program_Counter_inst: entity work.Program_Counter(A_Program_Counter)
    port map(
        clk             		=> clk,
        reset           		=> reset,
        pc_address_in    		=> pc_address_in,
        pc_address_out   		=> pc_address_out,
        ready            		=> pc_ready 
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
    stim_proc: process
    begin
        report("----------Starting simulation----------");
        
        report("----------Initialize inputs----------");
        reset <= '1';
        pc_address_in <= (others => '0');
        wait for 20 ns;
        report("----------End of initialize inputs----------");
        
        report("----------Release reset----------");
        reset <= '0';
        wait for 10 ns;
        report("----------End of release reset----------");
        
        report("----------Test 1: Program counter output for 5 clk periods----------");
        report "Program Counter 1: " & integer'image(to_integer(unsigned(pc_address_out)));
        wait for clk_period;
        report "Program Counter 2: " & integer'image(to_integer(unsigned(pc_address_out)));
        wait for clk_period;
        report "Program Counter 3: " & integer'image(to_integer(unsigned(pc_address_out)));
        wait for clk_period;
        report "Program Counter 4: " & integer'image(to_integer(unsigned(pc_address_out)));
        wait for clk_period;
        report "Program Counter 5: " & integer'image(to_integer(unsigned(pc_address_out)));
        wait for clk_period;
        wait for 10 ns;
        report("----------End of Test 1----------");
        
        
        report("----------End of simulation----------");
        
        wait;
    end process;

end A_Program_Counter_tb;
