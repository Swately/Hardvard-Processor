library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Instruction_Memory is
	port(
		instruction_address_in: in std_logic_vector(31 downto 0);
		data_out: out std_logic_vector(31 downto 0)
	);

end Instruction_Memory;

architecture A_Instruction_Memory of Instruction_Memory is
	--R: "000000 00000 00000 00000 00000 000000" I: "000000 00000 00000 0000000000000000" J: "000000 00000000000000000000000000"
	type instruction_memory_type is array (0 to 255) of std_logic_vector(31 downto 0);
	signal instruction_memory : instruction_memory_type := (
		0 => "00001000000000000000000000000000",-- "000010 00000 00000 0000000000000000" LOAD Data_Memory0 a registro 0 del banco de registros
		1 => "00010000000000000000000000000000",--ADDI "000010 00000 00000 0000000000000000" registro 0 + 1
		2 => "00100100000000000000000000000000",--HALT
		3 => "00100100000000000000000000000000",--HALT
		others => (others => '0')
	);

begin
	data_out <= instruction_memory(to_integer(unsigned(instruction_address_in)));
end A_Instruction_Memory;