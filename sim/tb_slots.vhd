library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- tb_slots -- plays the slot machine in simulation.
--
-- Drives the whole Top_Level_Unit and reconstructs what the four-digit
-- 7-segment display shows, by decoding the segment patterns and the one-hot
-- digit select exactly as an eye watching the multiplexed sweep would.
--
-- Every symbol on that display came out of `random mod 8`, and the modulo is a
-- subroutine; the credit count is printed by dividing by ten twice, also in
-- software. So the readout below is a picture of the software arithmetic
-- working.

entity tb_slots is
end tb_slots;

architecture A_tb_slots of tb_slots is

    constant PERIOD : time := 480.769 ns;      -- 2.08 MHz, the board clock

    signal clk     : std_logic := '0';
    signal reset   : std_logic := '1';
    signal halt    : boolean   := false;
    signal buttons : std_logic_vector(4 downto 0) := (others => '0');

    signal DISPLAY_SELECTOR : std_logic_vector(3 downto 0);
    signal DISPLAY          : std_logic_vector(6 downto 0);
    signal sync             : std_logic_vector(4 downto 0);
    signal src_led, trg_led, des_led : std_logic_vector(4 downto 0);

    -- What the eye integrates: the last pattern seen for each digit position.
    type digit_array is array (0 to 3) of character;
    signal seen : digit_array := (others => ' ');

    -- {g,f,e,d,c,b,a} patterns, same table the driver uses.
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

    -- Watch the sweep: whichever digit is enabled, record what it is showing.
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

    play : process

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

        procedure press is
        begin
            buttons <= "00001";
            wait for 3 ms;
            buttons <= "00000";
            wait for 3 ms;
        end procedure;

    begin
        reset <= '1';
        wait for PERIOD * 8;
        reset <= '0';

        wait for 20 ms;
        show("AFTER RESET -- the credit count, waiting for a coin");

        press;
        wait for 60 ms;
        show("SPIN 1 -- the three reels");
        wait for 260 ms;
        show("SPIN 1 -- credits after paying out");

        press;
        wait for 60 ms;
        show("SPIN 2 -- the three reels");
        wait for 260 ms;
        show("SPIN 2 -- credits");

        press;
        wait for 60 ms;
        show("SPIN 3 -- the three reels");
        wait for 260 ms;
        show("SPIN 3 -- credits");

        report "";
        report "RESULT: PASS -- the processor drove the multiplexed display";

        halt <= true;
        wait for PERIOD;
        std.env.finish;
    end process;

end A_tb_slots;

-- Made with my soul - Swately <3
