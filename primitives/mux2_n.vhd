library ieee;
use ieee.std_logic_1164.all;

-- mux2_n -- N-bit 2:1 multiplexer: N instances of mux2 sharing one select.
--
-- Structural, so that every wide multiplexer in the processor is visibly made
-- of the same one-bit cell rather than appearing out of a `when/else`.

entity mux2_n is
    generic (
        WIDTH : natural := 32
    );
    port (
        a   : in  std_logic_vector(WIDTH - 1 downto 0);
        b   : in  std_logic_vector(WIDTH - 1 downto 0);
        sel : in  std_logic;
        y   : out std_logic_vector(WIDTH - 1 downto 0)
    );
end mux2_n;

architecture structural of mux2_n is
    component mux2
        port (a, b, sel : in std_logic; y : out std_logic);
    end component;
begin

    gen_bits : for i in 0 to WIDTH - 1 generate
        cell : mux2 port map (a => a(i), b => b(i), sel => sel, y => y(i));
    end generate;

end structural;

-- Made with my soul - Swately <3
