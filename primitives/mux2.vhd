library ieee;
use ieee.std_logic_1164.all;

-- mux2 -- 1-bit 2:1 multiplexer, written as the gates it is.
--
--   y = (a AND NOT sel) OR (b AND sel)
--
-- This is deliberately NOT `y <= a when sel = '0' else b;`. The conditional
-- form describes the same function but leaves the structure to the tool; the
-- boolean form IS the schematic. The multiplexer is the second building block
-- of the whole design after the full adder: shifters, register files and the
-- ALU result select are all trees of this.

entity mux2 is
    port (
        a   : in  std_logic;   -- selected when sel = '0'
        b   : in  std_logic;   -- selected when sel = '1'
        sel : in  std_logic;
        y   : out std_logic
    );
end mux2;

architecture gates of mux2 is
begin
    y <= (a and (not sel)) or (b and sel);
end gates;

-- Made with my soul - Swately <3
