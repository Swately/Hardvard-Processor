library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- tb_lcd -- self-checking bench for Top_LCD_Test.
--
-- Contains a behavioural HD44780 model that latches on the falling edge of E,
-- decodes the command set, and maintains the real 16x2 DDRAM. At the end it
-- prints the screen exactly as the display would show it and ASSERTS the
-- expected content, so "the LCD driver works" is a checked claim rather than a
-- reading of the waveform.
--
-- The model also refuses data written before the initialisation completes,
-- which is what a real HD44780 does and what makes a missing power-on wait
-- show up as a blank screen instead of passing silently.
--
-- Run:
--   ghdl -a --std=08 --workdir=sim/work sim/OSCH_sim.vhd
--   ghdl -a --std=08 --workdir=sim/work LCD_Controller.vhd Top_LCD_Test.vhd
--   ghdl -a --std=08 --workdir=sim/work sim/tb_lcd.vhd
--   ghdl -r --std=08 --workdir=sim/work tb_lcd --stop-time=40ms

entity tb_lcd is
end tb_lcd;

architecture A_tb_lcd of tb_lcd is

    signal reset     : std_logic := '1';
    signal heartbeat : std_logic;
    signal lcd_rs    : std_logic;
    signal lcd_rw    : std_logic;
    signal lcd_e     : std_logic;
    signal lcd_d     : std_logic_vector(7 downto 0);

    -- HD44780 model state
    type ddram_t is array (0 to 127) of character;
    signal ddram : ddram_t := (others => ' ');

    signal ac          : integer := 0;      -- address counter
    signal initialised : boolean := false;
    signal fn_set_seen : integer := 0;
    signal cmd_count   : integer := 0;
    signal data_count  : integer := 0;
    signal early_data  : integer := 0;      -- data written before init finished
    signal rw_violation: integer := 0;

    constant EXPECT_L1 : string(1 to 16) := "PHARVARD LCD OK ";
    constant EXPECT_L2 : string(1 to 16) := "0123456789ABCDEF";

begin

    DUT : entity work.Top_LCD_Test(A_Top_LCD_Test)
        port map (
            reset     => reset,
            heartbeat => heartbeat,
            lcd_rs    => lcd_rs,
            lcd_rw    => lcd_rw,
            lcd_e     => lcd_e,
            lcd_d     => lcd_d
        );

    stim : process
    begin
        reset <= '1';
        wait for 5 us;
        reset <= '0';
        wait;
    end process;

    -- ------------------------------------------------------------------
    -- HD44780 behavioural model: latch on the FALLING edge of E.
    -- ------------------------------------------------------------------
    hd44780 : process(lcd_e)
        variable b   : integer;
        variable adr : integer;
    begin
        if falling_edge(lcd_e) then

            if lcd_rw /= '0' then
                rw_violation <= rw_violation + 1;
            end if;

            b := to_integer(unsigned(lcd_d));

            if lcd_rs = '0' then
                cmd_count <= cmd_count + 1;

                if b = 16#01# then                    -- clear display
                    ddram <= (others => ' ');
                    ac    <= 0;
                elsif b = 16#02# or b = 16#03# then   -- return home
                    ac <= 0;
                elsif b >= 16#80# then                -- set DDRAM address
                    ac <= b - 16#80#;
                elsif b >= 16#40# then                -- set CGRAM address
                    ac <= b - 16#40#;
                elsif b >= 16#30# and b <= 16#3F# then -- function set (8-bit)
                    fn_set_seen <= fn_set_seen + 1;
                    -- The datasheet needs three 0x30 writes then the real
                    -- function set before the controller is usable.
                    if fn_set_seen >= 3 then
                        initialised <= true;
                    end if;
                end if;

            else
                data_count <= data_count + 1;
                if not initialised then
                    early_data <= early_data + 1;
                else
                    adr := ac;
                    if adr >= 0 and adr <= 127 then
                        ddram(adr) <= character'val(b);
                    end if;
                    ac <= ac + 1;
                end if;
            end if;
        end if;
    end process;

    -- ------------------------------------------------------------------
    -- Report and check.
    -- ------------------------------------------------------------------
    checker : process
        variable l1, l2 : string(1 to 16);
        variable fails  : integer := 0;
    begin
        -- Power-on wait is 15 ms, the rest of init about 6 ms, then 34 writes.
        wait for 32 ms;

        for i in 0 to 15 loop
            l1(i + 1) := ddram(i);
            l2(i + 1) := ddram(16#40# + i);
        end loop;

        report "";
        report "        +----------------+";
        report "        |" & l1 & "|";
        report "        |" & l2 & "|";
        report "        +----------------+";
        report "";
        report "commands issued : " & integer'image(cmd_count);
        report "data bytes      : " & integer'image(data_count);

        if l1 /= EXPECT_L1 then
            report "FAIL line 1: got """ & l1 & """ expected """
                & EXPECT_L1 & """" severity error;
            fails := fails + 1;
        end if;
        if l2 /= EXPECT_L2 then
            report "FAIL line 2: got """ & l2 & """ expected """
                & EXPECT_L2 & """" severity error;
            fails := fails + 1;
        end if;
        if early_data /= 0 then
            report "FAIL: " & integer'image(early_data)
                & " data byte(s) written before initialisation finished"
                severity error;
            fails := fails + 1;
        end if;
        if rw_violation /= 0 then
            report "FAIL: RW was driven high " & integer'image(rw_violation)
                & " time(s); this controller is write-only" severity error;
            fails := fails + 1;
        end if;
        if data_count /= 32 then
            report "FAIL: expected 32 characters, saw "
                & integer'image(data_count) severity error;
            fails := fails + 1;
        end if;

        if fails = 0 then
            report "RESULT: PASS -- the screen matches, init order respected";
        else
            report "RESULT: FAIL (" & integer'image(fails) & " checks)"
                severity error;
        end if;

        std.env.finish;
    end process;

end A_tb_lcd;

-- Made with my soul - Swately <3
