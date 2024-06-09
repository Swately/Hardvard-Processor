library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Instruction_Memory_Address_Register is
	port(
		clk, reset: in std_logic;
		ready: out std_logic;
		instruction_address_in: in std_logic_vector(31 downto 0);
		instruction_address_out: out std_logic_vector(31 downto 0)
	);
end Instruction_Memory_Address_Register;

architecture A_Instruction_Memory_Address_Register of Instruction_Memory_Address_Register is
	signal internal_address: std_logic_vector(31 downto 0) := (others => 'X');
	signal internal_ready: std_logic := '0';
begin
	Instruction_Memory_Address_Register_Process: process(clk, reset)
	begin
		if reset = '1' then
			instruction_address_out <= (others => '0');
		elsif rising_edge(clk) then
			instruction_address_out <= instruction_address_in;
			internal_address <= instruction_address_in;
		end if;
	end process Instruction_Memory_Address_Register_Process;
	
	process(clk, reset)
	begin
		if reset = '1' then
			internal_ready <= '0';
		elsif falling_edge(clk) then
			if instruction_address_in = internal_address then
				internal_ready <= '1';
			else
				internal_ready <= '0';
			end if;
		end if;
	end process;
	ready <= internal_ready;
end A_Instruction_Memory_Address_Register;