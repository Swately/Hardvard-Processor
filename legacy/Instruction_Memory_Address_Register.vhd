library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Instruction_Memory_Address_Register
--
-- Presents the fetch address to the instruction ROM. Structure unchanged: the
-- same address_in_state -> address_out_state -> update_state walk and the same
-- `ready` handshake.
--
-- Repairs applied 2026-07-31: identical to Program_Counter.vhd --
-- internal_address_in/out were latches driven from a combinational process,
-- the `ready_count` variable was a latch of its own, `ready` led the value it
-- advertised by one cycle, and previous_state had no remaining purpose. See
-- that file's header for the reasoning; the fault was the same in all three
-- address registers because they are copies of one another.

entity Instruction_Memory_Address_Register is
	port(
		clk, reset: in std_logic;
		ready: out std_logic;
		instruction_address_in: in std_logic_vector(7 downto 0);
		instruction_address_out: out std_logic_vector(7 downto 0)
	);
end Instruction_Memory_Address_Register;

architecture A_Instruction_Memory_Address_Register of Instruction_Memory_Address_Register is

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
					internal_address_in <= instruction_address_in;
				when address_out_state =>
					internal_address_out <= internal_address_in;
				when others =>
					null;
			end case;

			if internal_address_in /= instruction_address_in then
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

	instruction_address_out <= internal_address_out;

	ready <= internal_ready when internal_address_in = instruction_address_in else '0';

end A_Instruction_Memory_Address_Register;

-- Made with my soul - Swately <3
