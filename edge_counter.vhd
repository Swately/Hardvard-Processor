library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- edge_counter -- measures the period of an external, asynchronous signal in
-- local clock cycles, and tracks the spread across many measurements.
--
-- THIS IS THE INSTRUMENT, NOT THE GENERATOR. Its whole job is to answer one
-- question before any entropy design is built: how much does the interval
-- between two independent oscillators actually wander?
--
--   max_period = min_period  ->  the wander is below one local clock period
--                                (480 ns at 2.08 MHz). No usable entropy at
--                                this sampling rate; slow the external source
--                                down and try again.
--   max - min = k            ->  the pair drifts by k cycles, and that spread
--                                is what a generator would have to harvest.
--
-- Jitter accumulates as a random walk, so a source divided down by N carries
-- roughly sqrt(N) times more of it per edge. That is why the companion Arduino
-- sketch emits 1 kHz rather than its raw 16 MHz clock, and why the answer to
-- "no spread" is to divide further rather than to give up.
--
-- THE SYNCHRONISER, AND AN HONEST WARNING.
-- ext_in belongs to another clock domain, so sampling it can drive the first
-- flip-flop metastable. Two stages make that vanishingly unlikely to reach the
-- logic behind them; the residual risk is the standard one every CDC carries.
-- Note the consequence for this project: metastability is not simulable, so
-- what this block reports on real hardware is NOT something the golden-model
-- regression can predict or check. It is a measuring instrument whose readings
-- only exist on silicon.

entity edge_counter is
    port (
        clk   : in  std_logic;
        reset : in  std_logic;

        -- The other oscillator, asynchronous to clk.
        ext_in : in std_logic;

        -- Clear the accumulated min/max and the sample count.
        clear : in std_logic;

        period       : out std_logic_vector(31 downto 0);  -- last measurement
        min_period   : out std_logic_vector(31 downto 0);
        max_period   : out std_logic_vector(31 downto 0);
        sample_count : out std_logic_vector(31 downto 0)
    );
end edge_counter;

architecture rtl of edge_counter is

    -- Two-stage synchroniser plus one more cycle of history for edge detect.
    signal sync : std_logic_vector(2 downto 0) := (others => '0');
    signal rising_ext : std_logic;

    signal counter : unsigned(31 downto 0) := (others => '0');
    signal last    : unsigned(31 downto 0) := (others => '0');
    signal lo      : unsigned(31 downto 0) := (others => '1');
    signal hi      : unsigned(31 downto 0) := (others => '0');
    signal n       : unsigned(31 downto 0) := (others => '0');

    -- The first measurement after a clear starts from an arbitrary point in
    -- the external signal's cycle, so it is not a period at all. Discarding it
    -- keeps a meaningless value out of min/max, which would otherwise wreck
    -- the spread with a single sample.
    signal armed : std_logic := '0';

begin

    rising_ext <= sync(1) and (not sync(2));

    process(clk, reset)
    begin
        if reset = '1' then
            sync    <= (others => '0');
            counter <= (others => '0');
            last    <= (others => '0');
            lo      <= (others => '1');
            hi      <= (others => '0');
            n       <= (others => '0');
            armed   <= '0';

        elsif rising_edge(clk) then

            sync <= sync(1 downto 0) & ext_in;

            if clear = '1' then
                counter <= (others => '0');
                lo      <= (others => '1');
                hi      <= (others => '0');
                n       <= (others => '0');
                armed   <= '0';

            elsif rising_ext = '1' then
                -- Restart at ONE, not zero. The edge cycle itself does not
                -- increment, so restarting at zero makes the reported figure
                -- period - 1: two edges N cycles apart would read N-1. The
                -- spread survives that (both ends shift alike) but the
                -- absolute reading does not, and a period reported as 2079
                -- when it is 2080 is the kind of quiet off-by-one that ends up
                -- in a table nobody rechecks.
                counter <= to_unsigned(1, counter'length);

                if armed = '1' then
                    last <= counter;
                    n    <= n + 1;
                    if counter < lo then
                        lo <= counter;
                    end if;
                    if counter > hi then
                        hi <= counter;
                    end if;
                else
                    -- First edge after a clear: only start the clock.
                    armed <= '1';
                end if;

            else
                counter <= counter + 1;
            end if;

        end if;
    end process;

    period       <= std_logic_vector(last);
    min_period   <= std_logic_vector(lo);
    max_period   <= std_logic_vector(hi);
    sample_count <= std_logic_vector(n);

end rtl;

-- Made with my soul - Swately <3
