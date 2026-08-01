library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Top_LCD_Test
--
-- Minimal bring-up design: no CPU, no game. It brings up a 16x2 HD44780 and
-- writes a fixed two-line screen, so that the LCD wiring and the pin
-- assignment can be validated on their own before anything depends on them.
--
-- The pin map for the LCD header in the Holith board notes is marked "likely"
-- -- it was inferred from the header sequence, not confirmed on hardware. This
-- design is the cheapest way to confirm it.
--
-- What you should see:
--
--     +----------------+
--     |PHARVARD LCD OK |
--     |0123456789ABCDEF|
--     +----------------+
--
-- The second line is a ruler on purpose: it shows all 16 columns at once and
-- makes a scrambled data bus obvious immediately. Reading it as ...89:;<=>?
-- means D0..D7 are permuted; a blank screen with a row of black blocks means
-- the display never took the initialisation (usually RS or E miswired).
--
-- LED on pin 55 blinks about once a second regardless of the LCD, so a dead
-- display can be told apart from a design that never started.

entity Top_LCD_Test is
    port (
        reset   : in  std_logic;
        heartbeat : out std_logic;
        lcd_rs  : out std_logic;
        lcd_rw  : out std_logic;
        lcd_e   : out std_logic;
        lcd_d   : out std_logic_vector(7 downto 0)
    );
end Top_LCD_Test;

architecture A_Top_LCD_Test of Top_LCD_Test is

    component OSCH
        generic (NOM_FREQ : string := "2.08");
        port (
            STDBY : in  std_logic;
            OSC   : out std_logic;
            SEDSTDBY : out std_logic
        );
    end component;

    -- 2.08 MHz is the OSCH setting already proven on this board.
    constant CLK_HZ : natural := 2_080_000;

    signal clk : std_logic;

    signal wr_en   : std_logic := '0';
    signal wr_rs   : std_logic := '0';
    signal wr_data : std_logic_vector(7 downto 0) := (others => '0');
    signal busy    : std_logic;
    signal lcd_ready : std_logic;

    -- The screen, as a flat script of (rs, byte) pairs: two set-address
    -- commands and 32 characters.
    type script_step_t is record
        rs   : std_logic;
        data : std_logic_vector(7 downto 0);
    end record;
    type script_t is array (natural range <>) of script_step_t;

    function ch(c : character) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(character'pos(c), 8));
    end function;

    function txt(rs : std_logic; c : character) return script_step_t is
    begin
        return (rs => rs, data => ch(c));
    end function;

    constant SCRIPT : script_t := (
        -- DDRAM address 0x00 -> line 1, column 0
        (rs => '0', data => X"80"),
        txt('1','P'), txt('1','H'), txt('1','A'), txt('1','R'),
        txt('1','V'), txt('1','A'), txt('1','R'), txt('1','D'),
        txt('1',' '), txt('1','L'), txt('1','C'), txt('1','D'),
        txt('1',' '), txt('1','O'), txt('1','K'), txt('1',' '),
        -- DDRAM address 0x40 -> line 2, column 0
        (rs => '0', data => X"C0"),
        txt('1','0'), txt('1','1'), txt('1','2'), txt('1','3'),
        txt('1','4'), txt('1','5'), txt('1','6'), txt('1','7'),
        txt('1','8'), txt('1','9'), txt('1','A'), txt('1','B'),
        txt('1','C'), txt('1','D'), txt('1','E'), txt('1','F')
    );

    signal step : natural range 0 to SCRIPT'length := 0;

    signal hb_count : unsigned(23 downto 0) := (others => '0');
    signal hb       : std_logic := '0';

begin

    OSC_Inst : OSCH
        generic map (NOM_FREQ => "2.08")
        port map (
            STDBY    => '0',
            OSC      => clk,
            SEDSTDBY => open
        );

    LCD_Inst : entity work.LCD_Controller(A_LCD_Controller)
        generic map (CLK_HZ => CLK_HZ)
        port map (
            clk     => clk,
            reset   => reset,
            wr_en   => wr_en,
            wr_rs   => wr_rs,
            wr_data => wr_data,
            busy    => busy,
            ready   => lcd_ready,
            lcd_rs  => lcd_rs,
            lcd_rw  => lcd_rw,
            lcd_e   => lcd_e,
            lcd_d   => lcd_d
        );

    -- Walk the script once, one byte per accepted write.
    process(clk, reset)
    begin
        if reset = '1' then
            step    <= 0;
            wr_en   <= '0';
            wr_rs   <= '0';
            wr_data <= (others => '0');
        elsif rising_edge(clk) then
            wr_en <= '0';
            if lcd_ready = '1' and busy = '0' and wr_en = '0'
               and step < SCRIPT'length then
                wr_rs   <= SCRIPT(step).rs;
                wr_data <= SCRIPT(step).data;
                wr_en   <= '1';
                step    <= step + 1;
            end if;
        end if;
    end process;

    -- Heartbeat: proves the bitstream is running even if the LCD shows nothing.
    process(clk)
    begin
        if rising_edge(clk) then
            if hb_count = 1_040_000 then       -- half of 2.08 MHz -> ~1 Hz
                hb_count <= (others => '0');
                hb       <= not hb;
            else
                hb_count <= hb_count + 1;
            end if;
        end if;
    end process;

    heartbeat <= hb;

end A_Top_LCD_Test;

-- Made with my soul - Swately <3
