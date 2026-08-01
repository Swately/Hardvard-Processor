library ieee;
use ieee.std_logic_1164.all;

-- dff -- D flip-flop with asynchronous reset and clock enable.
--
-- THIS IS THE IRREDUCIBLE SEQUENTIAL PRIMITIVE. Everything with state in this
-- processor is built from it, and it is the one place where a behavioural
-- description is not a shortcut but a necessity.
--
-- Why it cannot be built from gates: a flip-flop made of cross-coupled NANDs
-- is a combinational loop, and a synthesiser either rejects it or produces
-- something that does not behave like a flip-flop. Below this level you are no
-- longer describing FPGA fabric, you are describing transistors. Every
-- structural methodology stops here for the same reason -- Nand2Tetris treats
-- the DFF as a given primitive and says so explicitly.
--
-- The clock enable is likewise not a shortcut: an FPGA flip-flop has a real CE
-- input in silicon. Building it as a feedback mux would describe hardware that
-- is not what the chip actually contains, and would cost logic for nothing.

entity dff is
    generic (
        RESET_VALUE : std_logic := '0'
    );
    port (
        clk : in  std_logic;
        rst : in  std_logic;   -- asynchronous, active high
        en  : in  std_logic;   -- clock enable, active high
        d   : in  std_logic;
        q   : out std_logic
    );
end dff;

architecture behavioural of dff is
    signal q_i : std_logic := RESET_VALUE;
begin

    process(clk, rst)
    begin
        if rst = '1' then
            q_i <= RESET_VALUE;
        elsif rising_edge(clk) then
            if en = '1' then
                q_i <= d;
            end if;
        end if;
    end process;

    q <= q_i;

end behavioural;

-- Made with my soul - Swately <3
