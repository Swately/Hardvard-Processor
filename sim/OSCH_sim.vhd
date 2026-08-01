library ieee;
use ieee.std_logic_1164.all;

-- OSCH -- SIMULATION-ONLY behavioural model of the MachXO2 internal oscillator.
--
-- Diamond supplies the real primitive, so this file must NOT be added to the
-- synthesis project. It exists so that Top_LCD_Test (and later the full
-- machine) can be simulated whole rather than in pieces.
--
-- Only the NOM_FREQ values this project uses are modelled. An unrecognised
-- value stops the simulation rather than quietly running at the wrong speed,
-- because a wrong clock here would silently invalidate every LCD timing
-- measurement made against it.

entity OSCH is
    generic (NOM_FREQ : string := "2.08");
    port (
        STDBY    : in  std_logic;
        OSC      : out std_logic;
        SEDSTDBY : out std_logic
    );
end OSCH;

architecture sim of OSCH is

    function period_of(f : string) return time is
    begin
        if f = "2.08" then
            return 480.769 ns;      -- 2.08 MHz
        elsif f = "133" or f = "133.00" then
            return 7.519 ns;        -- 133 MHz
        elsif f = "20.46" then
            return 48.876 ns;
        else
            report "OSCH_sim: unmodelled NOM_FREQ """ & f & """"
                severity failure;
            return 1 ns;
        end if;
    end function;

    constant PERIOD : time := period_of(NOM_FREQ);
    signal osc_i : std_logic := '0';

begin

    osc_i    <= not osc_i after PERIOD / 2;
    OSC      <= osc_i;
    SEDSTDBY <= '0';

end sim;

-- Made with my soul - Swately <3
