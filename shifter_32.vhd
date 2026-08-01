library ieee;
use ieee.std_logic_1164.all;

-- shifter_32 -- 32-bit logical barrel shifter, structural.
--
-- Five stages. Stage k either passes its input through or shifts it left by
-- 2^k, selected by bit k of the shift amount; 1+2+4+8+16 covers every shift
-- from 0 to 31. Each stage is one mux2_n, so the whole shifter is 160 copies
-- of the one-bit multiplexer in primitives/mux2.vhd and nothing else.
--
-- The shift itself costs NO logic: `s(31-N downto 0) & zeros` is pure wiring,
-- a renaming of which wire goes where. Only the per-stage multiplexers are
-- gates. That is the point of the barrel structure.
--
-- Right shifts reuse the same network by reversing the bit order going in and
-- coming out:
--
--     reverse( shift_left( reverse(x), n ) )  =  shift_right_logical(x, n)
--
-- The two reversals are also pure wiring, so a bidirectional shifter costs the
-- same as a unidirectional one plus two 32-bit multiplexers.
--
-- Logical only: a right shift fills with zeros. An arithmetic right shift
-- (sign fill) would need the fill value to be data(31) instead of '0' in the
-- reversed domain, which is a further mux per stage; it is not in the ISA, so
-- it is not built.

entity shifter_32 is
    port (
        data   : in  std_logic_vector(31 downto 0);
        shamt  : in  std_logic_vector(4 downto 0);
        dir    : in  std_logic;   -- '0' = shift left, '1' = shift right
        result : out std_logic_vector(31 downto 0)
    );
end shifter_32;

architecture structural of shifter_32 is

    component mux2_n
        generic (WIDTH : natural := 32);
        port (
            a   : in  std_logic_vector(WIDTH - 1 downto 0);
            b   : in  std_logic_vector(WIDTH - 1 downto 0);
            sel : in  std_logic;
            y   : out std_logic_vector(WIDTH - 1 downto 0)
        );
    end component;

    constant ZEROS : std_logic_vector(31 downto 0) := (others => '0');

    -- Six stage boundaries but only five shifted versions: s(5) is the final
    -- output and nothing is shifted out of it. Sizing the two arrays alike
    -- would leave sh(5) undriven, which is a real synthesis warning about a
    -- wire that goes nowhere.
    type stage_t is array (0 to 5) of std_logic_vector(31 downto 0);
    type shift_t is array (0 to 4) of std_logic_vector(31 downto 0);
    signal s  : stage_t;                       -- stage inputs / outputs
    signal sh : shift_t;                       -- s(k) shifted left by 2^k

    signal din_rev, dout_rev : std_logic_vector(31 downto 0);

begin

    -- Bit reversal in: wiring only.
    gen_rev_in : for i in 0 to 31 generate
        din_rev(i) <= data(31 - i);
    end generate;

    pre_mux : mux2_n
        generic map (WIDTH => 32)
        port map (a => data, b => din_rev, sel => dir, y => s(0));

    -- The five shift stages.
    gen_stage : for k in 0 to 4 generate
        constant N : natural := 2 ** k;
    begin
        -- Shift left by N: wiring only, zero fill at the bottom.
        sh(k) <= s(k)(31 - N downto 0) & ZEROS(N - 1 downto 0);

        stage_mux : mux2_n
            generic map (WIDTH => 32)
            port map (a => s(k), b => sh(k), sel => shamt(k), y => s(k + 1));
    end generate;

    -- Bit reversal out: wiring only.
    gen_rev_out : for i in 0 to 31 generate
        dout_rev(i) <= s(5)(31 - i);
    end generate;

    post_mux : mux2_n
        generic map (WIDTH => 32)
        port map (a => s(5), b => dout_rev, sel => dir, y => result);

end structural;

-- Made with my soul - Swately <3
