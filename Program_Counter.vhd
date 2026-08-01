library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Program_Counter -- structural.
--
-- The two storage elements are register_n instances, which are register_n ->
-- dff -> the primitive floor. Nothing here writes `q <= d` by hand any more;
-- the registers are objects, not a pattern retyped per module.
--
-- The control FSM stays as an enum in a clocked process. That is not a
-- shortcut being tolerated: a state register IS a register plus next-state
-- logic, and writing the enum encoding out by hand would fix a bit pattern
-- the synthesiser is better placed to choose (one-hot, gray, binary) without
-- making the diagram any clearer.
--
-- Repairs from earlier passes still hold: the address registers were latches
-- inferred from a combinational process, `ready_count` was a latch of its own,
-- `ready` led its data by one cycle, and previous_state had no remaining
-- purpose. See DIAGNOSIS.md §6.4.

entity Program_Counter is
    port(
        clk, reset: in std_logic;
        ready: out std_logic;
        pc_address_in: in std_logic_vector(31 downto 0);
        pc_address_out: out std_logic_vector(31 downto 0)
    );
end Program_Counter;

architecture A_Program_Counter of Program_Counter is

    component register_n
        generic (WIDTH : natural := 32; RESET_VALUE : std_logic := '0');
        port (
            clk : in  std_logic;
            rst : in  std_logic;
            en  : in  std_logic;
            d   : in  std_logic_vector(WIDTH - 1 downto 0);
            q   : out std_logic_vector(WIDTH - 1 downto 0)
        );
    end component;

    type state_type is (address_in_state, address_out_state, update_state);
    signal state, next_state: state_type;

    signal internal_pc_in  : std_logic_vector(31 downto 0);
    signal internal_pc_out : std_logic_vector(31 downto 0);
    signal en_in, en_out   : std_logic := '0';
    signal internal_ready  : std_logic := '0';

begin

    -- The two registers. Each is 32 dff cells.
    Reg_In : register_n
        generic map (WIDTH => 32)
        port map (clk => clk, rst => reset, en => en_in,
                  d => pc_address_in, q => internal_pc_in);

    Reg_Out : register_n
        generic map (WIDTH => 32)
        port map (clk => clk, rst => reset, en => en_out,
                  d => internal_pc_in, q => internal_pc_out);

    -- Enables: exactly one state loads each register.
    en_in  <= '1' when state = address_in_state  else '0';
    en_out <= '1' when state = address_out_state else '0';

    -- State register only. It holds no datapath value.
    process(clk, reset)
    begin
        if reset = '1' then
            state <= address_in_state;
        elsif rising_edge(clk) then
            -- A new requested address restarts the walk.
            if internal_pc_in /= pc_address_in then
                state <= address_in_state;
            else
                state <= next_state;
            end if;
        end if;
    end process;

    process(state)
    begin
        case state is
            when address_in_state  => next_state <= address_out_state;
            when address_out_state => next_state <= update_state;
            when update_state      => next_state <= update_state;
        end case;

        if state = update_state then
            internal_ready <= '1';
        else
            internal_ready <= '0';
        end if;
    end process;

    pc_address_out <= internal_pc_out;

    -- Valid only once the latch has caught up with the request.
    ready <= internal_ready when internal_pc_in = pc_address_in else '0';

end A_Program_Counter;

-- Made with my soul - Swately <3
