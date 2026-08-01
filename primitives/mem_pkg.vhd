library ieee;
use ieee.std_logic_1164.all;

-- mem_pkg -- the word-array type the memory banks are built from.
--
-- Separated into a package so a bank's initial contents can be handed to it as
-- a generic. That is what lets both banks be the SAME component: they differ
-- only in what they are loaded with, not in what they are.

package mem_pkg is

    type word_array is array (natural range <>) of std_logic_vector(31 downto 0);

end package mem_pkg;

-- Made with my soul - Swately <3
