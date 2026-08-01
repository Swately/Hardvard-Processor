library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.mem_pkg.all;
use work.memory_image_pkg.all;

-- Memory_System -- modified Harvard: separate instruction and data buses over
-- a single unified address space.
--
-- WHAT THIS IS, BY NAME. Classic Harvard has separate instruction and data
-- memories that cannot see each other: code lives in one, data in the other,
-- and neither can hold the other kind. Classic von Neumann has one memory and
-- one bus, so a fetch and a data access cannot happen at once. This is the
-- third option, MODIFIED HARVARD: two independent buses, so a fetch and a data
-- access still proceed in parallel, but ONE address space, so any word of
-- memory can hold an instruction or a datum. It is the arrangement ARM
-- Cortex-M uses, and most DSPs.
--
-- HOW IT IS POSSIBLE. Each bank is a TRUE DUAL-PORT RAM: two independent
-- read/write ports into the same array, both active in the same cycle. Port A
-- of every bank serves the fetch bus; port B serves the data bus. Nothing has
-- to be arbitrated and nothing stalls, because the two ports are physically
-- separate in the silicon. FPGA block RAM provides exactly this.
--
--   address(8) = 0  -> bank 0, words 0..255
--   address(8) = 1  -> bank 1, words 256..511
--
-- The banks are identical components differing only in what they are loaded
-- with. Either can hold code, data, or both.
--
-- THE ONE-CYCLE RULE. Block RAM reads are synchronous: an address presented in
-- cycle N produces its word in cycle N+1. Rather than leave every user to
-- remember that, this module publishes fetch_addr_q and data_addr_q -- the
-- address each output actually belongs to. A consumer compares those against
-- what it asked for and knows, without counting cycles, whether the word on
-- the bus is the one it wanted. The previous design had a combinational
-- instruction ROM, which simulates but does not map to block RAM.
--
-- Everything here except the RAM itself is structural: the output selects are
-- mux2_n, the latency-tracking address registers are register_n.

entity Memory_System is
    generic (
        BANK_ADDR_BITS : natural := 8      -- per bank; total space is one more
    );
    port (
        clk   : in std_logic;
        reset : in std_logic;

        -- Instruction bus (port A of every bank)
        fetch_addr   : in  std_logic_vector(BANK_ADDR_BITS downto 0);
        fetch_data   : out std_logic_vector(31 downto 0);
        fetch_addr_q : out std_logic_vector(BANK_ADDR_BITS downto 0);
        fetch_valid  : out std_logic;

        -- Data bus (port B of every bank)
        data_addr    : in  std_logic_vector(BANK_ADDR_BITS downto 0);
        data_we      : in  std_logic;
        data_din     : in  std_logic_vector(31 downto 0);
        data_dout    : out std_logic_vector(31 downto 0);
        data_addr_q  : out std_logic_vector(BANK_ADDR_BITS downto 0);
        data_valid   : out std_logic
    );
end Memory_System;

architecture structural of Memory_System is

    component ram_dp
        generic (ADDR_BITS : natural; INIT : word_array);
        port (
            clk    : in  std_logic;
            a_addr : in  std_logic_vector(ADDR_BITS - 1 downto 0);
            a_we   : in  std_logic;
            a_din  : in  std_logic_vector(31 downto 0);
            a_dout : out std_logic_vector(31 downto 0);
            b_addr : in  std_logic_vector(ADDR_BITS - 1 downto 0);
            b_we   : in  std_logic;
            b_din  : in  std_logic_vector(31 downto 0);
            b_dout : out std_logic_vector(31 downto 0)
        );
    end component;

    component mux2_n
        generic (WIDTH : natural := 32);
        port (
            a, b : in  std_logic_vector(WIDTH - 1 downto 0);
            sel  : in  std_logic;
            y    : out std_logic_vector(WIDTH - 1 downto 0)
        );
    end component;

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

    constant N : natural := BANK_ADDR_BITS;

    signal bank_sel_f, bank_sel_d : std_logic;

    signal b0_a_dout, b1_a_dout : std_logic_vector(31 downto 0);
    signal b0_b_dout, b1_b_dout : std_logic_vector(31 downto 0);

    signal b0_b_we, b1_b_we : std_logic;

    signal fetch_addr_r, data_addr_r : std_logic_vector(N downto 0);

    signal we_hist : std_logic_vector(1 downto 0) := "00";
    signal settled : std_logic;

    constant ZEROS32 : std_logic_vector(31 downto 0) := (others => '0');

begin

    bank_sel_f <= fetch_addr(N);
    bank_sel_d <= data_addr(N);

    -- A data write lands in exactly one bank; the other sees we = '0'.
    b0_b_we <= data_we and (not bank_sel_d);
    b1_b_we <= data_we and bank_sel_d;

    -- The fetch port never writes. Instruction memory is still WRITABLE -- but
    -- through the data bus, which is the whole point of a unified space.
    Bank0 : ram_dp
        generic map (ADDR_BITS => N, INIT => BANK0_INIT)
        port map (
            clk    => clk,
            a_addr => fetch_addr(N - 1 downto 0),
            a_we   => '0',
            a_din  => ZEROS32,
            a_dout => b0_a_dout,
            b_addr => data_addr(N - 1 downto 0),
            b_we   => b0_b_we,
            b_din  => data_din,
            b_dout => b0_b_dout
        );

    Bank1 : ram_dp
        generic map (ADDR_BITS => N, INIT => BANK1_INIT)
        port map (
            clk    => clk,
            a_addr => fetch_addr(N - 1 downto 0),
            a_we   => '0',
            a_din  => ZEROS32,
            a_dout => b1_a_dout,
            b_addr => data_addr(N - 1 downto 0),
            b_we   => b1_b_we,
            b_din  => data_din,
            b_dout => b1_b_dout
        );

    -- Latency tracking: remember which address each output belongs to. Always
    -- enabled, so these follow the request by exactly the RAM's one cycle.
    Fetch_Addr_Reg : register_n
        generic map (WIDTH => N + 1)
        port map (clk => clk, rst => reset, en => '1',
                  d => fetch_addr, q => fetch_addr_r);

    Data_Addr_Reg : register_n
        generic map (WIDTH => N + 1)
        port map (clk => clk, rst => reset, en => '1',
                  d => data_addr, q => data_addr_r);

    -- Output select uses the DELAYED bank bit, because that is the bank the
    -- data on the bus actually came from.
    Fetch_Mux : mux2_n
        generic map (WIDTH => 32)
        port map (a => b0_a_dout, b => b1_a_dout,
                  sel => fetch_addr_r(N), y => fetch_data);

    Data_Mux : mux2_n
        generic map (WIDTH => 32)
        port map (a => b0_b_dout, b => b1_b_dout,
                  sel => data_addr_r(N), y => data_dout);

    fetch_addr_q <= fetch_addr_r;
    data_addr_q  <= data_addr_r;

    -- ------------------------------------------------------------------
    -- Validity, and why it needs more than an address match.
    -- ------------------------------------------------------------------
    -- The array updates at the END of a write cycle and the read port is
    -- registered, so a word written in cycle N only appears on the bus in
    -- cycle N+2. The address does not change across a store followed by a load
    -- of the same place, so an address match ALONE would report the stale
    -- value as valid -- which is exactly the STORE-then-LOAD sequence the demo
    -- program performs.
    --
    -- Two cycles of write history cover it. Any write stalls BOTH buses, not
    -- just the data bus: in a unified address space a store can land on the
    -- word being fetched, and refusing to reason about which is cheaper than
    -- being subtly wrong about self-modifying code.
    write_history : process(clk, reset)
    begin
        if reset = '1' then
            we_hist <= (others => '0');
        elsif rising_edge(clk) then
            we_hist <= we_hist(0) & data_we;
        end if;
    end process;

    settled <= '1' when (data_we = '0' and we_hist = "00") else '0';

    fetch_valid <= '1' when (fetch_addr_r = fetch_addr and settled = '1')
                   else '0';
    data_valid  <= '1' when (data_addr_r  = data_addr  and settled = '1')
                   else '0';

end structural;

-- Made with my soul - Swately <3
