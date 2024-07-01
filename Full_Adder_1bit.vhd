library ieee;
use ieee.std_logic_1164.all;

entity Full_Adder_1bit is
    port(
        bit_a, bit_b, carry_in, mode : in std_logic;
        result, carry_out : out std_logic := '0'
    );
end Full_Adder_1bit;

architecture A_Full_Adder_1bit of Full_Adder_1bit is
begin
    result <= bit_a xor (bit_b xor mode) xor carry_in;
    carry_out <= (bit_a and (bit_b xor mode)) or ((carry_in and (bit_b xor mode)) or (bit_a and carry_in));
end A_Full_Adder_1bit;