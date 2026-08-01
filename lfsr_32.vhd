library ieee;
use ieee.std_logic_1164.all;

-- lfsr_32 -- free-running 32-bit linear feedback shift register.
--
-- Structural: a register_n (so, 32 dff cells) plus three XOR gates. Nothing
-- else. It is the cheapest source of pseudo-randomness there is and it is
-- built entirely from the primitive floor.
--
-- Taps 32, 22, 2, 1 give a maximal-length sequence: it visits all 2^32 - 1
-- non-zero states before repeating. The all-zero state is a fixed point --
-- once there it never leaves -- so the reset value must not be zero, which is
-- why RESET_VALUE below is not (others => '0').
--
-- WHY THIS IS HARDWARE AND NOT A SUBROUTINE. A software LFSR is easy with the
-- shift instructions, but it only advances when the program runs it, so every
-- run of the machine would produce the same sequence from the same seed. This
-- one advances every clock, forever, including while the processor sits
-- waiting for a button. The entropy is not in the register: it is in WHEN the
-- player presses, sampled against a counter running at 2 MHz. That is how a
-- real slot machine does it, and it is honest about where the randomness
-- comes from.

entity lfsr_32 is
    port (
        clk   : in  std_logic;
        reset : in  std_logic;
        value : out std_logic_vector(31 downto 0)
    );
end lfsr_32;

architecture structural of lfsr_32 is

    component register_n
        generic (WIDTH : natural := 32; RESET_VALUE : std_logic := '0');
        port (
            clk : in  std_logic;
            rst : in  std_logic;
            en  : in  std_logic;
            d   : in  std_logic_vector(WIDTH - 1 downto 0);
            q   : out std_logic_vector(WIDTH - 1 downto 0)
        );
    end component;

    signal state    : std_logic_vector(31 downto 0);
    signal next_val : std_logic_vector(31 downto 0);
    signal feedback : std_logic;

begin

    -- Three XOR gates over the tap positions.
    feedback <= state(31) xor state(21) xor state(1) xor state(0);

    -- Shift left, feedback into bit 0. Pure wiring apart from the XORs above.
    next_val <= state(30 downto 0) & feedback;

    -- RESET_VALUE '1' seeds the register with all ones, which is simply a
    -- non-zero state; any non-zero seed gives the same cycle from a different
    -- point.
    -- NOT called `Reg`: an instance label becomes an instance NAME when the
    -- design is translated to Verilog, and `reg` is a Verilog keyword. The
    -- generated netlist then fails to parse. Instance labels are part of the
    -- portable surface of a design, not just local decoration.
    State_Reg : register_n
        generic map (WIDTH => 32, RESET_VALUE => '1')
        port map (clk => clk, rst => reset, en => '1',
                  d => next_val, q => state);

    value <= state;

end structural;

-- Made with my soul - Swately <3
