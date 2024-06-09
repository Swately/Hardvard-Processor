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
	--R: "000000(OP) 00000(SR) 00000(TR) 00000(DR) 00000(SA) 000000(FUNC)" I: "000000 00000 00000 0000000000000000" J: "000000 00000000000000000000000000"
	type instruction_memory_type is array (0 to 255) of std_logic_vector(31 downto 0);
	signal instruction_memory : instruction_memory_type := (
		0 => "00001000000000000000000000000000",-- "000010 00000(SR) 00000(TR) 0000000000000000" LOAD Data_Memory 0 a registro 0 del banco de registros
		0 => "00001000000000010000000000000101",-- "000010 00000(SR) 00001(TR) 0000000000000101" LOAD Data_Memory 5 a registro 1 del banco de registros
		1 => "00010000000000000000000000000001",--ADD "000000(OP) 00000(SR) 00000(TR) 00000(DR) 00000(SA) 000000(FUNC)" registro 0 + 
		2 => "00100100000000000000000000000000",--BNZ
		3 => "00100100000000000000000000000000",--HALT
		others => (others => '0')
	);

begin
	data_out <= instruction_memory(to_integer(unsigned(instruction_address_in)));
end A_Instruction_Memory;