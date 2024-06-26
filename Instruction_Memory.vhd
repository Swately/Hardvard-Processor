library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Instruction_Memory is
	port(
		instruction_address_in: in std_logic_vector(7 downto 0);
		data_out: out std_logic_vector(31 downto 0)
	);

end Instruction_Memory;

architecture A_Instruction_Memory of Instruction_Memory is
	--R: "000000(OP) 00000(SR) 00000(TR) 00000(DR) 00000(SA) 000000(FUNC)" I: "000000 00000 00000 0000000000000000" J: "000000(OP) 00000000000000000000000000(ADDRESS)"
	type instruction_memory_type is array (0 to 255) of std_logic_vector(31 downto 0);
	signal instruction_memory : instruction_memory_type := (
		0 => "00001010101000110000000000001001",-- "000010 10101(SR) 00011(TR) 0000000000001001" LOAD Data_Memory 9 a registro 3 del banco de registros
		1 => "00001000000001110000000000000101",-- "000010 00000(SR) 00111(TR) 0000000000000101" LOAD Data_Memory 5 a registro 7 del banco de registros
		2 => "00001000000001100000000000000111",-- "000010 00000(SR) 00110(TR) 0000000000000111" LOAD Data_Memory 7 a registro 6 del banco de registros
		3 => "00000100011001110001100000000001",--	SUB "000001(OP) 00011(SR) 00111(TR) 00011(DR) 00000(SA) 000001(FUNC)" registro 3 - registro 7
		4 => "00101000011000010000000000000011",--BNE "001010(OP) 00011(SR) 00001(TR) 0000000000000011"
		5 => "00001000000001010000000000001001",-- "000010 00000(SR) 00101(TR) 0000000000001001" LOAD Data_Memory 9 a registro 5 del banco de registros
		6 => "00000100011001110001100000000000",--	ADD "000001(OP) 00011(SR) 00111(TR) 00110(DR) 00000(SA) 000000(FUNC)" registro 3 + registro 7
		7 => "00001000000000110000000000000001",-- "000010 00000(SR) 00011(TR) 0000000000000001" LOAD Data_Memory 1 a registro 3 del banco de registros
		8 => "00100100000000000000000000000000",--HALT
		others => (others => '0')
	);

begin
	data_out <= instruction_memory(to_integer(unsigned(instruction_address_in)));
end A_Instruction_Memory;