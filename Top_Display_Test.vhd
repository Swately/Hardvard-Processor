library ieee;
use ieee.std_logic_1164.all;

-- Top_Display_Test -- the display, and nothing else.
--
-- Layer isolation, the way the Holith bring-up did it: before believing
-- anything about the processor, prove the path OSCH -> Display -> pins on its
-- own. There is no CPU here, no memory, no register file. The digits are a
-- constant.
--
-- If this shows 1234, then the segment order, the digit order, the sweep rate
-- and every pin in that group are correct, and whatever is wrong lives further
-- up. If it does not, the fault is in this small file and its four
-- constraints, which is a much smaller place to look.
--
-- The LED on pin 55 blinks about once a second so that "display dark" and
-- "design not running" cannot be confused -- the same trick the LCD bring-up
-- used, and the reason that one would have been diagnosable at a glance.

entity Top_Display_Test is
    generic (
        CLK_HZ : natural := 2_080_000
    );
    port (
        reset            : in  std_logic;
        DISPLAY_SELECTOR : out std_logic_vector(3 downto 0);
        DISPLAY          : out std_logic_vector(6 downto 0);
        heartbeat        : out std_logic
    );
end Top_Display_Test;

architecture rtl of Top_Display_Test is

    component OSCH
        generic (NOM_FREQ : string := "2.08");
        port (STDBY : in std_logic; OSC : out std_logic;
              SEDSTDBY : out std_logic);
    end component;

    signal clk : std_logic;
    signal hb_count : natural range 0 to CLK_HZ := 0;
    signal hb : std_logic := '0';

begin

    OSC_Inst : OSCH
        generic map (NOM_FREQ => "2.08")
        port map (STDBY => '0', OSC => clk, SEDSTDBY => open);

    -- 0x1234: four distinct, non-symmetric digits, so a reversed or permuted
    -- digit order is unmistakable rather than plausible.
    Display_Inst : entity work.Display(A_Display)
        generic map (CLK_HZ => CLK_HZ, STEP_HZ => 400)
        port map (
            clk    => clk,
            reset  => reset,
            digits => X"1234",
            dmode  => '1',
            DISPLAY_SELECTOR => DISPLAY_SELECTOR,
            DISPLAY => DISPLAY
        );

    -- Deliberately NOT held by reset: if the reset input is miswired or stuck
    -- asserted, this still blinks and says so.
    process(clk)
    begin
        if rising_edge(clk) then
            if hb_count = CLK_HZ / 2 then
                hb_count <= 0;
                hb <= not hb;
            else
                hb_count <= hb_count + 1;
            end if;
        end if;
    end process;

    heartbeat <= hb;

end rtl;

-- Made with my soul - Swately <3
