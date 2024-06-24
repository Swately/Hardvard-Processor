library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Data_Memory is
	port(
		clk, write_data_enable, data_register_ready, reset: in std_logic;
		ready: out std_logic;
		data_address_in: in std_logic_vector(31 downto 0);
		data_in: in std_logic_vector(31 downto 0);
		data_out: out std_logic_vector(31 downto 0) := (others => '0')
	);

end Data_Memory;

architecture A_Data_Memory of Data_Memory is

	type state_type is (set_state, write_read_state, data_out_state, reset_state, update_state);
	signal state, next_state, previous_state: state_type;
	
	type data_memory_type is array (0 to 65535) of std_logic_vector(31 downto 0);
	signal data_memory : data_memory_type := (
		0 => X"0000000A", -- 10 en decimal
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
	
	signal internal_data_in: std_logic_vector(31 downto 0) := (others => 'X');
	signal internal_address_in: std_logic_vector(31 downto 0) := (others => 'X');
	signal internal_ready: std_logic := '0';

begin

	process(clk, reset, data_register_ready)
	begin
		if reset = '1' then
			state <= set_state;
		elsif rising_edge(clk) or falling_edge(clk) then
			state <= next_state;
			previous_state <= state;
			
			if internal_address_in /= data_address_in or internal_data_in /= data_in then
				state <= set_state;
			end if;
		end if;
	end process;
	
	process(state, data_in, data_address_in, data_register_ready)
		variable ready_count : integer;
	begin
		case state is
			when set_state =>
				if data_register_ready = '1' then
					internal_data_in <= data_in;
					internal_address_in <= data_address_in;
					ready_count := 1;
					next_state <= write_read_state;
				else
					next_state <= update_state;
				end if;
				
			when write_read_state =>
				if write_data_enable = '1' then
					data_memory(to_integer(unsigned(internal_address_in))) <= internal_data_in;
				end if;
				ready_count := 2;
				next_state <= data_out_state;
			
			when data_out_state =>
				data_out <= data_memory(to_integer(unsigned(internal_address_in)));
				ready_count := 3;
				next_state <= update_state;
				
			when update_state =>
				next_state <= previous_state;
				
			when others =>
				next_state <= set_state;
		end case;
		
		if ready_count = 3 then
			internal_ready <= '1';
		else
			internal_ready <= '0';
		end if;
		
	end process;

	
	ready <= internal_ready and data_register_ready;
	
end A_Data_Memory;