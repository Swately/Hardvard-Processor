library ieee;
use ieee.std_logic_1164.all;

entity Full_Adder_32bits is
    port(
        entry_a, entry_b: in std_logic_vector(31 downto 0);
        mode: in std_logic;
        carry_out: out std_logic;
        result: out std_logic_vector(32 downto 0) := (others => '0')
    );
end Full_Adder_32bits;

architecture A_Full_Adder_32bits of Full_Adder_32bits is

    signal internal_carry: std_logic_vector(32 downto 0) := (others => '0');

    component Full_Adder_1bit
        port(
            bit_a, bit_b, carry_in, mode : in std_logic;
            result, carry_out: out std_logic
        );
    end component;
begin
    internal_carry(0) <= mode;
    gen_adder: for i in 0 to 31 generate
        Full_Adder_i: Full_Adder_1bit
            port map(
                bit_a => entry_a(i),
                bit_b => entry_b(i),
                carry_in => internal_carry(i),
                mode => mode,
                result => result(i),
                carry_out => internal_carry(i+1)
            );
    end generate gen_adder;

    result(32) <= internal_carry(32);
    carry_out <= internal_carry(32);
end A_Full_Adder_32bits;