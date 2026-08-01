library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- power_on_reset -- holds the design in reset for a while after configuration.
--
-- WHY THIS EXISTS. The design took its reset from a DIP switch and nothing
-- else. On the bench that looks fine, because every testbench begins by
-- pulsing reset. On silicon it is fatal: the switch sits at its resting level,
-- reset is never asserted, and the processor starts from whatever state
-- configuration left its flip-flops in.
--
-- For a state machine written as an enumerated type that is not a harmless
-- question. The synthesiser is free to encode the states one-hot, in which
-- case "all flip-flops at zero" is not state 0 -- it is not a state at all.
-- The next-state decode matches nothing, the machine never leaves, and the
-- processor is dead in a way no simulation can reproduce: there the signal has
-- an initial value and the bench pulses reset besides.
--
-- That is exactly how this processor behaved on 2026-08-01. The display read
-- 0000, and in debug mode it still read 0000 -- a state code of zero, which no
-- legal state can produce. That impossible reading is what identified this.
--
-- A power-on reset is the standard answer and costs a counter. The counter
-- itself is safe to start undefined-at-zero, because zero is the natural
-- power-up value of an FPGA flip-flop and zero is where this one wants to
-- begin. It is the one register in the design that does not need a reset,
-- which is what lets it provide reset for everything else.
--
-- The external reset input is kept and ORed in, so the operator can still
-- restart the machine by hand.

entity power_on_reset is
    generic (
        -- Cycles to hold reset after configuration. 1024 at 2.08 MHz is about
        -- half a millisecond -- far longer than anything here needs, and still
        -- invisible to a person.
        HOLD_CYCLES : natural := 1024
    );
    port (
        clk        : in  std_logic;
        reset_in   : in  std_logic;
        reset_out  : out std_logic
    );
end power_on_reset;

architecture rtl of power_on_reset is

    signal count   : unsigned(15 downto 0) := (others => '0');
    signal por     : std_logic := '1';

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if count = HOLD_CYCLES then
                por <= '0';
            else
                count <= count + 1;
                por   <= '1';
            end if;
        end if;
    end process;

    -- Either source resets the design.
    reset_out <= por or reset_in;

end rtl;

-- Made with my soul - Swately <3
