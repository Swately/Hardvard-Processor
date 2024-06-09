library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Data_Memory is
	port(
		clk, write_data_enable, data_register_ready: in std_logic;
		ready: out std_logic;
		data_address_in: in std_logic_vector(31 downto 0);
		data_in: in std_logic_vector(31 downto 0);
		data_out: out std_logic_vector(31 downto 0) := (others => '0')
	);

end Data_Memory;

architecture A_Data_Memory of Data_Memory is
	
	type data_memory_type is array (0 to 255) of std_logic_vector(31 downto 0);
	signal data_memory : data_memory_type := (
		0 => X"00000011", -- 17 en decimal
		1 => X"00000019", -- 25 en decimal
		2 => X"00000004", -- 4 en decimal
		3 => X"0000000A", -- 10 en decimal
		4 => X"0000001E", -- 30 en decimal
		5 => X"00000001", -- 1 en decimal
		6 => X"00000002", -- 2 en decimal
		7 => X"FFFFFFFF", -- -1 en decimal
		8 => X"00000007", -- 7 en decimal
		9 => X"05F5E100", -- 1M en decimal
		10 => X"0000048D", -- valor de x
		11 => X"FFFFF863", -- valor de y
		12 => X"FFFFF7EA", -- valor de w
		13 => X"000017FC", -- valor de w
		others => (others => '0')
	);
	
	signal internal_data: std_logic_vector(31 downto 0) := (others => 'X');
	signal internal_ready: std_logic := '0';

begin


	process(clk)
	begin
		if rising_edge(clk) then
			if write_data_enable = '1' then
				data_memory(to_integer(unsigned(data_address_in))) <= data_in;
				data_out <= data_in;
				internal_data <= data_in;
			else
				data_out <= data_memory(to_integer(unsigned(data_address_in)));
				internal_data <= data_memory(to_integer(unsigned(data_address_in)));
			end if;
		end if;
	end process;
	
	process(clk)
	begin
		if falling_edge(clk) then
			if write_data_enable = '1' then
				if data_in = internal_data then
					internal_ready <= '1';
				else
					internal_ready <= '0';
				end if;
			else
				if data_memory(to_integer(unsigned(data_address_in))) = internal_data then
					internal_ready <= '1';
				else
					internal_ready <= '0';
				end if;
			end if;
		end if;
	end process;
	
	ready <= internal_ready and data_register_ready;
	
end A_Data_Memory;