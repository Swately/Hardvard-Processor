library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Data_Memory_Address_Register is
	port(
		clk, reset: in std_logic;
		ready: out std_logic;
		data_address_in: in std_logic_vector(31 downto 0);
		data_address_out: out std_logic_vector(31 downto 0)
	);
end Data_Memory_Address_Register;

architecture A_Data_Memory_Address_Register of Data_Memory_Address_Register is
	type state_type is (address_in_state, address_out_state, update_state);
	signal state, next_state, previous_state: state_type;

	signal internal_address_in: std_logic_vector(31 downto 0) := (others => 'X');
	signal internal_address_out: std_logic_vector(31 downto 0) := (others => 'X');
	signal internal_ready: std_logic := '0';
begin
	
	process(clk, reset)
	begin
		if reset = '1' then
			state <= address_in_state;
		elsif rising_edge(clk) or falling_edge(clk) then
			state <= next_state;
			previous_state <= state;

			if internal_address_in /= data_address_in then
				state <= address_in_state;
			end if;
		end if;
	end process;

	process(state, data_address_in)
		variable ready_count : integer;
	begin
		case(state) is
		
			when address_in_state =>
				internal_address_in <= data_address_in;
				ready_count := 1;
				next_state <= address_out_state;

			when address_out_state =>	
				internal_address_out <= internal_address_in;
				ready_count := 2;
				next_state <= update_state;

			when update_state =>
				next_state <= previous_state;

			when others =>
				next_state <= address_in_state;
		end case ;

		if ready_count = 2 then
			internal_ready <= '1';
		else
			internal_ready <= '0';
		end if;

	end process;
	
	data_address_out <= internal_address_out;
	ready <= internal_ready;
end A_Data_Memory_Address_Register;