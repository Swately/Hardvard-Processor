library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- tb_shifter -- exhaustive check of the structural barrel shifter.
--
-- Every shift amount 0..31, both directions, over a set of data patterns
-- chosen to catch the usual wiring faults: all-ones and the walking-one
-- patterns expose an off-by-one in a stage, and 0x80000001 exposes a lost
-- top or bottom bit.
--
-- The reference is numeric_std's shift_left / shift_right. Checking a
-- structural circuit against the behavioural operator it replaces is the point:
-- the operator is the specification, the structure is the implementation.

entity tb_shifter is
end tb_shifter;

architecture A_tb_shifter of tb_shifter is

    signal data   : std_logic_vector(31 downto 0) := (others => '0');
    signal shamt  : std_logic_vector(4 downto 0)  := (others => '0');
    signal dir    : std_logic := '0';
    signal result : std_logic_vector(31 downto 0);

    type pattern_array is array (natural range <>) of std_logic_vector(31 downto 0);
    constant PATTERNS : pattern_array := (
        X"00000001",
        X"80000000",
        X"80000001",
        X"FFFFFFFF",
        X"A5A5A5A5",
        X"0000FFFF",
        X"12345678",
        X"00000000"
    );

begin

    DUT : entity work.shifter_32(structural)
        port map (data => data, shamt => shamt, dir => dir, result => result);

    check : process
        variable expected : std_logic_vector(31 downto 0);
        variable fails    : integer := 0;
        variable checks   : integer := 0;
    begin
        for p in PATTERNS'range loop
            for n in 0 to 31 loop
                for d in 0 to 1 loop
                    data  <= PATTERNS(p);
                    shamt <= std_logic_vector(to_unsigned(n, 5));
                    if d = 0 then
                        dir <= '0';
                    else
                        dir <= '1';
                    end if;
                    wait for 1 ns;

                    if d = 0 then
                        expected := std_logic_vector(
                            shift_left(unsigned(PATTERNS(p)), n));
                    else
                        expected := std_logic_vector(
                            shift_right(unsigned(PATTERNS(p)), n));
                    end if;

                    checks := checks + 1;
                    if result /= expected then
                        fails := fails + 1;
                        if fails <= 8 then
                            report "MISMATCH data=" & to_hstring(PATTERNS(p))
                                & " shamt=" & integer'image(n)
                                & " dir=" & integer'image(d)
                                & " got=" & to_hstring(result)
                                & " expected=" & to_hstring(expected)
                                severity error;
                        end if;
                    end if;
                end loop;
            end loop;
        end loop;

        report "shifter checks run : " & integer'image(checks);
        if fails = 0 then
            report "RESULT: PASS -- structural shifter matches numeric_std "
                & "for every amount and both directions";
        else
            report "RESULT: FAIL (" & integer'image(fails) & " mismatches)"
                severity error;
        end if;

        std.env.finish;
    end process;

end A_tb_shifter;

-- Made with my soul - Swately <3
