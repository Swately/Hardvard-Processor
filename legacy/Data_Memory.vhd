library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Data_Memory
--
-- 256 x 32-bit data memory with an initialised image. Structure unchanged from
-- the original: the same set_state / write_read_state / data_out_state /
-- update_state walk and the same `ready` handshake.
--
-- Repairs applied 2026-07-31 (see DIAGNOSIS.md §4):
--   * data_memory was written from a COMBINATIONAL process, which is a
--     combinational path through storage and will not map to block RAM. All
--     array accesses now happen inside the clocked process.
--   * data_out was driven from that same combinational process; it is now a
--     registered output.
--   * The restart condition compared the latched data_in against the live
--     data_in. data_in is fed from the register file through the CPU, so it
--     moves while the access is in flight and restarted the walk. It now keys
--     on the ADDRESS only, which is stable for the whole instruction.
--
-- NOTE on the image below: address 9 holds 0x05F5E100, which is 100,000,000
-- and not the "1M" the original comment claimed. That single value is what
-- made the shipped program run for 1.5 years (DIAGNOSIS.md §2.1). The image is
-- preserved as-is; the demo program in Instruction_Memory.vhd now loads its
-- loop counter from address 3 instead.

entity Data_Memory is
	port(
		clk, write_data_enable, read_data_enable, data_register_ready, reset: in std_logic;
		commit: in std_logic;
		ready: out std_logic;
		data_address_in: in std_logic_vector(7 downto 0);
		data_in: in std_logic_vector(31 downto 0);
		data_out: out std_logic_vector(31 downto 0) := (others => '0')
	);

end Data_Memory;

architecture A_Data_Memory of Data_Memory is

	type state_type is (set_state, write_read_state, data_out_state, reset_state, update_state);
	signal state, next_state, previous_state: state_type;

	type data_memory_type is array (0 to 255) of std_logic_vector(31 downto 0);
	signal data_memory : data_memory_type := (
		0 => X"00000000", -- 0 en decimal
		1 => X"00000019", -- 25 en decimal
		2 => X"00000004", -- 4 en decimal
		3 => X"0000000A", -- 10 en decimal
		4 => X"0000001E", -- 30 en decimal
		5 => X"00000001", -- 1 en decimal
		6 => X"00000002", -- 2 en decimal
		7 => X"FFFFFFFF", -- -1 en decimal
		8 => X"000003E8", -- 1000 en decimal
		9 => X"05F5E100", -- 100,000,000 en decimal (el comentario original decia 1M)
		10 => X"0000048D", -- valor de x
		11 => X"FFFFF863", -- valor de y
		12 => X"FFFFF7EA", -- valor de w
		13 => X"000017FC", -- valor de w
		others => (others => '0')
	);

	signal internal_data_out: std_logic_vector(31 downto 0) := (others => '0');
	signal internal_address_in: std_logic_vector(7 downto 0) := (others => '0');
	signal internal_ready: std_logic := '0';

begin

	-- Everything that touches storage lives here, under the clock.
	process(clk, reset)
	begin
		if reset = '1' then
			state <= set_state;
			internal_address_in <= (others => '0');
			internal_data_out <= (others => '0');
		elsif rising_edge(clk) then

			-- WRITE PATH: one explicit commit point, exactly as in
			-- Register_File. The original wrote from a state of the read walk,
			-- so whether a STORE landed depended on where that walk happened to
			-- be when the CPU presented the data.
			if commit = '1' and write_data_enable = '1' then
				data_memory(to_integer(unsigned(data_address_in))) <= data_in;
			end if;

			-- READ PATH.
			case state is

				when set_state =>
					if data_register_ready = '1' then
						internal_address_in <= data_address_in;
					end if;

				when data_out_state =>
					-- The addressed word is presented unconditionally. The
					-- original zeroed data_out whenever read_data_enable was
					-- low, and the walk only restarted on an address change --
					-- so a STORE followed by a LOAD of the SAME address left
					-- the zero latched and the LOAD read 0. Measured: after
					-- `STORE r6 -> mem[20]` wrote 42, `LOAD mem[20] -> r8`
					-- returned 0. The CPU only consumes data_out when
					-- memto_reg is set, so presenting it always is harmless.
					internal_data_out <= data_memory(to_integer(unsigned(internal_address_in)));

				when others =>
					null;

			end case;

			-- Restart on a new address, or right after a commit so the next
			-- read observes the word just written.
			if commit = '1' or internal_address_in /= data_address_in then
				state <= set_state;
			else
				state <= next_state;
			end if;

			-- Never record update_state as the place to return to (see the
			-- same note in Central_Processing_Unit.vhd).
			if state /= update_state then
				previous_state <= state;
			end if;

		end if;
	end process;

	-- Pure next-state / ready decode. Touches no storage.
	process(state, previous_state, data_register_ready)
		variable ready_count : integer;
	begin
		ready_count := 0;
		next_state  <= set_state;

		-- As in Register_File: `ready` is asserted only in update_state, the
		-- cycle AFTER data_out_state. data_out is registered, so asserting
		-- ready during data_out_state advertises a value that is not visible
		-- until the next cycle.
		case state is
			when set_state =>
				ready_count := 0;
				if data_register_ready = '1' then
					next_state <= write_read_state;
				else
					next_state <= set_state;
				end if;

			when write_read_state =>
				ready_count := 0;
				next_state <= data_out_state;

			when data_out_state =>
				ready_count := 0;
				next_state <= update_state;

			when update_state =>
				-- Data is valid here; hold until the address changes.
				ready_count := 3;
				next_state <= update_state;

			when others =>
				next_state <= set_state;
		end case;

		if ready_count = 3 then
			internal_ready <= '1';
		else
			internal_ready <= '0';
		end if;

	end process;

	data_out <= internal_data_out;

	-- Same reasoning as in Register_File: `ready` has to mean "data_out belongs
	-- to the address being requested right now", so it drops as soon as the
	-- requested address differs from the latched one.
	ready <= internal_ready and data_register_ready
	         when internal_address_in = data_address_in else '0';

end A_Data_Memory;

-- Made with my soul - Swately <3
