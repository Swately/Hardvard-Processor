library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Program_Counter is
    port(
        clk, reset: in std_logic;
        ready: out std_logic;
        pc_address_in: in std_logic_vector(31 downto 0);
        pc_address_out: out std_logic_vector(31 downto 0)
    );
end Program_Counter;

architecture A_Program_Counter of Program_Counter is
    signal internal_pc_in: std_logic_vector(31 downto 0) := (others => 'X');
    signal internal_ready: std_logic := '0';
begin
    
    
    process(clk, reset)
    begin
        if reset = '1' then
            internal_pc_in <= (others => '0');
        elsif rising_edge(clk) then
			internal_pc_in <= pc_address_in;
        end if;
    end process;
    
    process(clk, reset)
    begin
        if reset = '1' then
            internal_ready <= '0';
        elsif falling_edge(clk) then
            if internal_pc_in = pc_address_in then
                    internal_ready <= '1';
                else
                    internal_ready <= '0';
                end if;
        end if;
    end process;
    
    pc_address_out <= internal_pc_in;
    ready <= internal_ready;
end A_Program_Counter;
