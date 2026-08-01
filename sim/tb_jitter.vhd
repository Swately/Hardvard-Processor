library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- tb_jitter -- verifies the jitter MEASUREMENT CHAIN against a known answer.
--
-- Real oscillator jitter cannot be simulated: a VHDL simulator is
-- deterministic. What CAN be verified, and what this bench does, is that the
-- instrument reports the right number when the variation is one the bench
-- itself chose.
--
-- The external oscillator here has periods that walk deliberately through
-- 2080..2085 local clock cycles. So:
--
--     min    = 2080
--     max    = 2085
--     SPREAD = 5      <- what the display must show in mode 0
--
-- If the board later reads 0000 with a real Arduino attached, that is a
-- statement about the two oscillators, not about the instrument: this bench is
-- what rules out the instrument being the thing that is broken.

entity tb_jitter is
end tb_jitter;

architecture A_tb_jitter of tb_jitter is

    constant PERIOD : time := 480.769 ns;      -- 2.08 MHz board clock

    constant BASE   : integer := 2080;         -- ~1 kHz external signal
    constant SPAN   : integer := 5;            -- deliberate wander, in cycles

    signal clk     : std_logic := '0';
    signal reset   : std_logic := '1';
    signal halt    : boolean   := false;
    signal buttons : std_logic_vector(4 downto 0) := (others => '0');
    signal ext_osc : std_logic := '0';

    signal DISPLAY_SELECTOR : std_logic_vector(3 downto 0);
    signal DISPLAY          : std_logic_vector(6 downto 0);
    signal sync             : std_logic_vector(4 downto 0);
    signal src_led, trg_led, des_led : std_logic_vector(4 downto 0);

    type digit_array is array (0 to 3) of character;
    signal seen : digit_array := (others => ' ');

    function decode(p : std_logic_vector(6 downto 0)) return character is
    begin
        case p is
            when "0111111" => return '0';
            when "0000110" => return '1';
            when "1011011" => return '2';
            when "1001111" => return '3';
            when "1100110" => return '4';
            when "1101101" => return '5';
            when "1111101" => return '6';
            when "0000111" => return '7';
            when "1111111" => return '8';
            when "1100111" => return '9';
            when "0000000" => return ' ';
            when others    => return '?';
        end case;
    end function;

begin

    DUT : entity work.Top_Level_Unit(A_Top_Level_Unit)
        generic map (CLK_HZ => 2_080_000)
        port map (
            clk_in => clk, reset => reset, buttons => buttons,
            ext_osc => ext_osc,
            DISPLAY_SELECTOR => DISPLAY_SELECTOR, DISPLAY => DISPLAY,
            synchronization_signals => sync,
            src_reg_led => src_led, trg_reg_led => trg_led,
            des_reg_led => des_led
        );

    clk_gen : process
    begin
        while not halt loop
            clk <= '0'; wait for PERIOD / 2;
            clk <= '1'; wait for PERIOD / 2;
        end loop;
        wait;
    end process;

    -- The stand-in for the Arduino: rising edges spaced BASE..BASE+SPAN cycles
    -- apart, walking deterministically so the expected answer is exact.
    ext_gen : process
        variable extra : integer := 0;
    begin
        wait for PERIOD * 40;
        while not halt loop
            ext_osc <= '1';
            wait for PERIOD * 20;
            ext_osc <= '0';
            wait for PERIOD * (BASE - 20 + extra);
            extra := (extra + 1) mod (SPAN + 1);
        end loop;
        wait;
    end process;

    sweep : process(clk)
    begin
        if rising_edge(clk) then
            case DISPLAY_SELECTOR is
                when "1000" => seen(0) <= decode(DISPLAY);
                when "0100" => seen(1) <= decode(DISPLAY);
                when "0010" => seen(2) <= decode(DISPLAY);
                when "0001" => seen(3) <= decode(DISPLAY);
                when others => null;
            end case;
        end if;
    end process;

    check : process

        variable fails : integer := 0;

        procedure show(caption : string) is
            variable s : string(1 to 4);
        begin
            for i in 0 to 3 loop
                s(i + 1) := seen(i);
            end loop;
            report "";
            report caption;
            report "        +------+";
            report "        | " & s & " |";
            report "        +------+";
        end procedure;

        procedure expect(caption : string; want : string) is
            variable s : string(1 to 4);
        begin
            for i in 0 to 3 loop
                s(i + 1) := seen(i);
            end loop;
            if s = want then
                report "  [PASS] " & caption & " = """ & s & """";
            else
                report "  [FAIL] " & caption & " got """ & s
                    & """ want """ & want & """" severity error;
                fails := fails + 1;
            end if;
        end procedure;

        -- A REALISTIC press. The program spends most of its loop inside three
        -- software divisions -- about 30 ms -- and only samples the button
        -- between them, so a press shorter than one loop can be missed
        -- entirely. A human holds a button for 100-200 ms, which is several
        -- loops, so this is not a problem on the board; a 4 ms pulse in a
        -- testbench is not a human.
        --
        -- The clean fix, if it ever matters, is a sticky button latch in the
        -- peripheral block: set on any press, cleared when the CPU reads it.
        -- That is what real peripherals do and it costs about ten LUT4.
        procedure press is
        begin
            buttons <= "00001";
            wait for 150 ms;
            buttons <= "00000";
            wait for 30 ms;
        end procedure;

    begin
        reset <= '1';
        wait for PERIOD * 8;
        reset <= '0';

        -- Long enough for several external periods plus the software's three
        -- divisions per display update.
        wait for 120 ms;
        show("MODE 0 -- SPREAD (max - min)");
        -- Leading zeros are kept rather than blanked: a measurement reading
        -- "0005" cannot be misread, where "   5" invites a second look.
        expect("spread", "0005");

        press;
        wait for 60 ms;
        show("MODE 1 -- MIN period");
        expect("min", "2080");

        press;
        wait for 60 ms;
        show("MODE 2 -- MAX period");
        expect("max", "2085");

        press;
        wait for 60 ms;
        show("MODE 3 -- sample count");

        report "";
        if fails = 0 then
            report "RESULT: PASS -- the measurement chain reports the injected "
                & "wander exactly";
        else
            report "RESULT: FAIL (" & integer'image(fails) & ")" severity error;
        end if;

        halt <= true;
        wait for PERIOD;
        std.env.finish;
    end process;

end A_tb_jitter;

-- Made with my soul - Swately <3
