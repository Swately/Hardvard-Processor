library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Data_Memory_Address_Register
--
-- Presents the data address to the data memory. Structure unchanged: the same
-- address_in_state -> address_out_state -> update_state walk and the same
-- `ready` handshake.
--
-- Repairs applied 2026-07-31: identical to Program_Counter.vhd and to the
-- instruction-side register -- latches inferred from a combinational process,
-- a latched `ready_count` variable, a `ready` that led its data by one cycle,
-- and a previous_state with no remaining purpose. See Program_Counter.vhd for
-- the reasoning.

entity Data_Memory_Address_Register is
	port(
		clk, reset: in std_logic;
		ready: out std_logic;
		data_address_in: in std_logic_vector(7 downto 0);
		data_address_out: out std_logic_vector(7 downto 0)
	);
end Data_Memory_Address_Register;

architecture A_Data_Memory_Address_Register of Data_Memory_Address_Register is

	type state_type is (address_in_state, address_out_state, update_state);
	signal state, next_state: state_type;

	signal internal_address_in: std_logic_vector(7 downto 0) := (others => '0');
	signal internal_address_out: std_logic_vector(7 downto 0) := (others => '0');
	signal internal_ready: std_logic := '0';

begin

	process(clk, reset)
	begin
		if reset = '1' then
			state                <= address_in_state;
			internal_address_in  <= (others => '0');
			internal_address_out <= (others => '0');

		elsif rising_edge(clk) then

			case state is
				when address_in_state =>
					internal_address_in <= data_address_in;
				when address_out_state =>
					internal_address_out <= internal_address_in;
				when others =>
					null;
			end case;

			if internal_address_in /= data_address_in then
				state <= address_in_state;
			else
				state <= next_state;
			end if;

		end if;
	end process;

	process(state)
	begin
		case state is
			when address_in_state  => next_state <= address_out_state;
			when address_out_state => next_state <= update_state;
			when update_state      => next_state <= update_state;
		end case;

		if state = update_state then
			internal_ready <= '1';
		else
			internal_ready <= '0';
		end if;
	end process;

	data_address_out <= internal_address_out;

	ready <= internal_ready when internal_address_in = data_address_in else '0';

end A_Data_Memory_Address_Register;

-- Made with my soul - Swately <3
