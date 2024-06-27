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

    type state_type is (address_in_state, address_out_state, update_state);
    signal state, next_state, previous_state: state_type;

    signal internal_pc_in: std_logic_vector(31 downto 0) := (others => 'X');
    signal internal_pc_out: std_logic_vector(31 downto 0) := (others => 'X');
    signal internal_ready: std_logic := '0';
begin
    
    process(clk, reset) 
    begin
        if reset = '1' then
            state <= address_in_state;
        elsif rising_edge(clk) or falling_edge(clk) then
            state <= next_state;
            previous_state <= state;

            if internal_pc_in /= pc_address_in then
                state <= address_in_state;
            end if;
        end if;
    end process;

    process(state, pc_address_in)
        variable ready_count : integer;
    begin
        
        case state is

            when address_in_state =>
            internal_pc_in <= pc_address_in;
                ready_count := 1;
                next_state <= address_out_state;

            when address_out_state =>	
                internal_pc_out <= internal_pc_in;
                ready_count := 2;
                next_state <= update_state;

            when update_state =>
                next_state <= previous_state;

            when others =>
                next_state <= address_in_state;

        end case ;

        if ready_count = 2 then
            internal_ready <= '1';
        else
            internal_ready <= '0';
        end if;

    end process;
    
    
    
    pc_address_out <= internal_pc_out;
    ready <= internal_ready;
end A_Program_Counter;
