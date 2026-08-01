library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.memory_image_pkg.all;

-- tb_memory -- self-checking bench for the modified-Harvard memory system.
--
-- It checks the four properties that make this arrangement what it is, rather
-- than merely that a RAM stores bytes:
--
--   1. a fetch and a data access happen in the SAME cycle, in different banks
--   2. a fetch and a data access happen in the same cycle in the SAME bank
--      (this is what true dual port buys and what a single-port memory or a
--      von Neumann bus could not do)
--   3. the instruction bank is WRITABLE through the data bus -- code space is
--      ordinary memory, which is the difference from classic Harvard
--   4. the data bank is FETCHABLE through the instruction bus -- code can live
--      anywhere in the space
--
-- Reads are synchronous, so every check waits one clock after presenting an
-- address and confirms against the published *_addr_q, which is the address
-- the bus contents actually belong to.

entity tb_memory is
end tb_memory;

architecture A_tb_memory of tb_memory is

    constant N : natural := 8;               -- bits per bank
    constant PERIOD : time := 10 ns;

    signal clk   : std_logic := '0';
    signal reset : std_logic := '1';
    signal halt  : boolean := false;

    signal fetch_addr   : std_logic_vector(N downto 0) := (others => '0');
    signal fetch_data   : std_logic_vector(31 downto 0);
    signal fetch_addr_q : std_logic_vector(N downto 0);

    signal data_addr    : std_logic_vector(N downto 0) := (others => '0');
    signal data_we      : std_logic := '0';
    signal data_din     : std_logic_vector(31 downto 0) := (others => '0');
    signal data_dout    : std_logic_vector(31 downto 0);
    signal data_addr_q  : std_logic_vector(N downto 0);

    signal fails : integer := 0;

    -- The parameter is NOT called `n`: VHDL identifiers are case-insensitive,
    -- so a parameter `n` hides the constant `N` and `to_unsigned(v, N+1)`
    -- silently sizes itself from the argument instead of the bank width.
    -- GHDL warns about the hiding; the warning was worth reading.
    function addr(v : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(v, N + 1));
    end function;

begin

    DUT : entity work.Memory_System(structural)
        generic map (BANK_ADDR_BITS => N)
        port map (
            clk => clk, reset => reset,
            fetch_addr => fetch_addr, fetch_data => fetch_data,
            fetch_addr_q => fetch_addr_q,
            data_addr => data_addr, data_we => data_we,
            data_din => data_din, data_dout => data_dout,
            data_addr_q => data_addr_q
        );

    clk_gen : process
    begin
        while not halt loop
            clk <= '0'; wait for PERIOD / 2;
            clk <= '1'; wait for PERIOD / 2;
        end loop;
        wait;
    end process;

    stim : process

        procedure check(name : string; got, want : std_logic_vector) is
        begin
            if got = want then
                report "  [PASS] " & name;
            else
                report "  [FAIL] " & name & " got=" & to_hstring(got)
                    & " want=" & to_hstring(want) severity error;
                fails <= fails + 1;
            end if;
        end procedure;

    begin
        wait for PERIOD * 2;
        reset <= '0';
        wait until rising_edge(clk);

        ------------------------------------------------------------------
        report "1. fetch and data in the SAME cycle, DIFFERENT banks";
        fetch_addr <= addr(7);          -- bank 0: the JAL
        data_addr  <= addr(256 + 9);    -- bank 1: the 100,000,000 constant
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;
        -- Compared against the image PACKAGE, not against literals copied out
        -- of it. Hard-coding the words made this bench fail the moment the
        -- program was reassembled, which is a test coupled to the wrong thing:
        -- what is under test is the memory, not the program in it.
        check("instruction at 7 matches the image", fetch_data, BANK0_INIT(7));
        check("data at 265 matches the image", data_dout, BANK1_INIT(9));
        check("fetch_addr_q tracks", fetch_addr_q, addr(7));
        check("data_addr_q tracks", data_addr_q, addr(256 + 9));

        ------------------------------------------------------------------
        report "2. fetch and data in the SAME cycle, SAME bank";
        fetch_addr <= addr(0);          -- bank 0
        data_addr  <= addr(3);          -- bank 0 as well
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;
        check("instruction at 0", fetch_data, BANK0_INIT(0));
        check("the same bank read as DATA at 3", data_dout, BANK0_INIT(3));

        ------------------------------------------------------------------
        report "3. code space is WRITABLE through the data bus";
        data_addr <= addr(18);          -- the poisoned LOADI in bank 0
        data_din  <= X"30000000";       -- overwrite it with a NOP
        data_we   <= '1';
        wait until rising_edge(clk);
        data_we   <= '0';
        fetch_addr <= addr(18);
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;
        check("instruction 18 now FETCHES as the NOP just written",
              fetch_data, X"30000000");

        ------------------------------------------------------------------
        report "4. the data bank is FETCHABLE as code";
        data_addr <= addr(256 + 40);
        data_din  <= X"24000000";       -- a HALT, written into the data bank
        data_we   <= '1';
        wait until rising_edge(clk);
        data_we   <= '0';
        fetch_addr <= addr(256 + 40);
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;
        check("a word in the DATA bank fetches as an instruction",
              fetch_data, X"24000000");

        ------------------------------------------------------------------
        report "";
        if fails = 0 then
            report "RESULT: PASS -- modified Harvard confirmed: two buses, "
                & "one address space, either bank holds either kind";
        else
            report "RESULT: FAIL (" & integer'image(fails) & ")" severity error;
        end if;

        halt <= true;
        wait for PERIOD;
        std.env.finish;
    end process;

end A_tb_memory;

-- Made with my soul - Swately <3
