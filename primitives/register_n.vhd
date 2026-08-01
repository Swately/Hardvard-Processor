library ieee;
use ieee.std_logic_1164.all;

-- register_n -- N-bit register: N instances of dff sharing clock, reset and
-- enable.
--
-- Every architecturally visible register in the processor -- the program
-- counter, the instruction register, the address registers, the ALU source
-- latches -- is one of these. Writing them as `if rising_edge(clk) then q <= d`
-- in each module would work, but it hides that they are all the same object,
-- and it was inside exactly those hand-written clocked blocks that the latch
-- defects and the self-locking stall survived.

entity register_n is
    generic (
        WIDTH       : natural   := 32;
        RESET_VALUE : std_logic := '0'
    );
    port (
        clk : in  std_logic;
        rst : in  std_logic;
        en  : in  std_logic;
        d   : in  std_logic_vector(WIDTH - 1 downto 0);
        q   : out std_logic_vector(WIDTH - 1 downto 0)
    );
end register_n;

architecture structural of register_n is
    component dff
        generic (RESET_VALUE : std_logic := '0');
        port (clk, rst, en, d : in std_logic; q : out std_logic);
    end component;
begin

    gen_bits : for i in 0 to WIDTH - 1 generate
        cell : dff
            generic map (RESET_VALUE => RESET_VALUE)
            port map (clk => clk, rst => rst, en => en, d => d(i), q => q(i));
    end generate;

end structural;

-- Made with my soul - Swately <3
