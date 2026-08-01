library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Peripherals -- the memory-mapped I/O block.
--
-- Reached through ordinary LOAD and STORE. No instruction was added for I/O:
-- the top sixteen words of the address space are decoded to these registers
-- instead of to RAM, so `store r8, LCD_DATA` is just a store whose address
-- happens to land here. The STORE_IO opcode the original control unit carried
-- was never wired to anything and is not used.
--
-- REGISTER MAP  (offset within the block; the CPU decodes the base)
--   3  BUTTONS    R   the button inputs, one per bit
--   4  RANDOM     R   the free-running LFSR
--   5  DIGITS     W   four BCD nibbles for the 7-segment display
--   6  EXT_PERIOD R   local cycles between the last two external edges
--   7  EXT_MIN    R   smallest period seen since the last clear
--   8  EXT_MAX    R   largest period seen
--   9  EXT_COUNT  R   how many periods have been measured
--   9  EXT_CLEAR  W   any write clears min/max/count
--
-- The EXT_* block measures a second, independent oscillator fed in on a pin.
-- max - min is the drift between the two clocks, in local cycles: it is the
-- number that decides whether a two-oscillator entropy source is viable here
-- before any generator gets built.
--
-- The character-LCD controller used to live here. It was dropped: the board
-- already has a working multiplexed 7-segment display, and the LCD cost 302
-- LUT4 (measured) on a part the design did not fit. Offsets 0..2 are left
-- vacant rather than renumbered, so an old binary cannot mean something new.
--
-- DIGITS is BCD, not binary. Turning a number into decimal digits is done in
-- software with __div, the same routine the game already uses -- the hardware
-- converter cost 2,184 cells and is gone.
--
-- Reads are registered so this block behaves like the memory beside it: an
-- address presented in cycle N produces its word in N+1. Anything else would
-- make the CPU need two different rules for the same bus.

entity Peripherals is
    generic (
        CLK_HZ : natural := 2_080_000
    );
    port (
        clk   : in std_logic;
        reset : in std_logic;

        -- CPU side
        addr  : in  std_logic_vector(3 downto 0);
        we    : in  std_logic;
        din   : in  std_logic_vector(31 downto 0);
        dout  : out std_logic_vector(31 downto 0);

        -- outside world
        buttons : in  std_logic_vector(4 downto 0);
        ext_osc : in  std_logic := '0';   -- the second oscillator
        digits  : out std_logic_vector(15 downto 0)
    );
end Peripherals;

architecture structural of Peripherals is

    constant REG_BUTTONS : std_logic_vector(3 downto 0) := X"3";
    constant REG_RANDOM  : std_logic_vector(3 downto 0) := X"4";
    constant REG_DIGITS  : std_logic_vector(3 downto 0) := X"5";
    constant REG_EXT_PER : std_logic_vector(3 downto 0) := X"6";
    constant REG_EXT_MIN : std_logic_vector(3 downto 0) := X"7";
    constant REG_EXT_MAX : std_logic_vector(3 downto 0) := X"8";
    constant REG_EXT_CNT : std_logic_vector(3 downto 0) := X"9";

    signal rnd         : std_logic_vector(31 downto 0);
    signal button_word : std_logic_vector(31 downto 0);
    signal read_mux    : std_logic_vector(31 downto 0);
    signal digits_r    : std_logic_vector(15 downto 0) := (others => '1');

    signal ext_period, ext_min, ext_max, ext_count : std_logic_vector(31 downto 0);
    signal ext_clear : std_logic;

    constant ZEROS : std_logic_vector(31 downto 0) := (others => '0');

begin

    RNG : entity work.lfsr_32(structural)
        port map (clk => clk, reset => reset, value => rnd);

    -- Any write to the count register clears the accumulated statistics, so a
    -- measurement run starts from a known state without spending a register.
    ext_clear <= '1' when (we = '1' and addr = REG_EXT_CNT) else '0';

    EXT_MEAS : entity work.edge_counter(rtl)
        port map (
            clk => clk, reset => reset,
            ext_in => ext_osc,
            clear  => ext_clear,
            period => ext_period, min_period => ext_min,
            max_period => ext_max, sample_count => ext_count
        );

    -- The display latch. Blank at reset: nibbles of 1111 show nothing, so the
    -- board is dark until the program has something to say.
    process(clk, reset)
    begin
        if reset = '1' then
            digits_r <= (others => '1');
        elsif rising_edge(clk) then
            if we = '1' and addr = REG_DIGITS then
                digits_r <= din(15 downto 0);
            end if;
        end if;
    end process;

    digits <= digits_r;

    button_word <= ZEROS(31 downto 5) & buttons;

    with addr select read_mux <=
        button_word                    when REG_BUTTONS,
        rnd                            when REG_RANDOM,
        ZEROS(31 downto 16) & digits_r when REG_DIGITS,
        ext_period                     when REG_EXT_PER,
        ext_min                        when REG_EXT_MIN,
        ext_max                        when REG_EXT_MAX,
        ext_count                      when REG_EXT_CNT,
        ZEROS                          when others;

    -- Registered, to match the memory's read timing.
    process(clk, reset)
    begin
        if reset = '1' then
            dout <= (others => '0');
        elsif rising_edge(clk) then
            dout <= read_mux;
        end if;
    end process;

end structural;

-- Made with my soul - Swately <3
