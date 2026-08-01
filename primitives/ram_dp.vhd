library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.mem_pkg.all;

-- ram_dp -- true dual-port RAM. A PRIMITIVE (see PRIMITIVES.md).
--
-- This is the one declared concession in a structurally built processor.
-- Storage cannot be assembled from gates in any practical sense: a 256 x 32
-- bank made of flip-flops and multiplexers measured 5,313 cells for the
-- register file alone. On an FPGA a memory has to reach block RAM, and block
-- RAM is a vendor macro that no amount of structural VHDL will conjure. So the
-- array is declared and the tool is allowed to infer storage.
--
-- TRUE DUAL PORT is what makes this design's memory organisation work. Both
-- ports read and write the same array independently and in the same cycle, so
-- one bank can serve an instruction fetch on port A while it serves a data
-- access on port B. No arbitration, no stalls. FPGA block RAM provides this
-- natively; it is not a trick.
--
-- Reads are SYNCHRONOUS: the data for an address presented in cycle N appears
-- in cycle N+1. That is how block RAM behaves, and pretending otherwise (a
-- combinational read, as the original instruction ROM had) is exactly the sort
-- of description that simulates but does not map. Whoever uses this must track
-- the one-cycle latency -- Memory_System does, by publishing the address each
-- output currently corresponds to.
--
-- Write-first is NOT modelled: a read of an address being written on the same
-- port in the same cycle returns the OLD contents. Read-before-write is the
-- safer assumption and matches the default block RAM mode.

entity ram_dp is
    generic (
        ADDR_BITS : natural := 8;
        INIT      : word_array
    );
    port (
        clk : in std_logic;

        -- Port A
        a_addr : in  std_logic_vector(ADDR_BITS - 1 downto 0);
        a_we   : in  std_logic;
        a_din  : in  std_logic_vector(31 downto 0);
        a_dout : out std_logic_vector(31 downto 0);

        -- Port B
        b_addr : in  std_logic_vector(ADDR_BITS - 1 downto 0);
        b_we   : in  std_logic;
        b_din  : in  std_logic_vector(31 downto 0);
        b_dout : out std_logic_vector(31 downto 0)
    );
end ram_dp;

architecture inferred of ram_dp is

    constant DEPTH : natural := 2 ** ADDR_BITS;

    -- Build the storage from INIT, padding with zeros if the image is shorter
    -- than the bank.
    function init_bank return word_array is
        variable m : word_array(0 to DEPTH - 1) := (others => (others => '0'));
    begin
        for i in INIT'range loop
            if i < DEPTH then
                m(i) := INIT(i);
            end if;
        end loop;
        return m;
    end function;

    signal mem : word_array(0 to DEPTH - 1) := init_bank;

begin

    -- BOTH PORTS IN ONE PROCESS, deliberately. Writing the array from two
    -- separate processes gives the signal two drivers; std_logic resolution
    -- then turns every bit one process is not driving into 'X', and the memory
    -- reads back as garbage. The bench caught exactly that. A single process
    -- has a single driver and is also the idiom synthesisers recognise as
    -- true dual-port block RAM.
    --
    -- Collision rule: if both ports write the same address in the same cycle,
    -- port B wins, because its assignment comes last. Real block RAM leaves
    -- this case undefined, so a program must not rely on it either way.
    both_ports : process(clk)
    begin
        if rising_edge(clk) then

            if a_we = '1' then
                mem(to_integer(unsigned(a_addr))) <= a_din;
            end if;
            if b_we = '1' then
                mem(to_integer(unsigned(b_addr))) <= b_din;
            end if;

            -- Read-before-write on both ports: a read of an address being
            -- written this cycle returns the OLD contents, which is the
            -- default block RAM behaviour.
            a_dout <= mem(to_integer(unsigned(a_addr)));
            b_dout <= mem(to_integer(unsigned(b_addr)));

        end if;
    end process;

end inferred;

-- Made with my soul - Swately <3
