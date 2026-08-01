library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.mem_pkg.all;

-- Register_File -- 32 x 32-bit register bank, in RAM.
--
-- Structure, states and the `ready` handshake are unchanged. What changed is
-- where the 1,024 bits live.
--
-- WHY THIS IS NOT A RETREAT FROM THE STRUCTURAL DISCIPLINE. It is the opposite.
-- primitives/PRIMITIVES.md declares memory as the one irreducible primitive:
-- storage cannot be assembled from gates in any practical sense, and on an
-- FPGA it has to reach block RAM to be usable. A register bank built from
-- flip-flops and a 32-to-1 multiplexer of 32-bit words is exactly the case
-- that document warns about, and it measured **5,313 cells -- 58% of the
-- entire design**, more than the processor's whole datapath. Putting it in
-- RAM is following the rule, not bending it.
--
-- ONE WRITE PORT, TWO READ PORTS, FROM TWO DUAL-PORT RAMS. A dual-port RAM
-- gives two ports; a register file needs three. The standard answer is to keep
-- TWO copies of the bank with identical contents: every write goes to both,
-- and each copy serves one read port. It costs twice the bits and no logic,
-- which on a part with block RAM to spare is the right trade.
--
-- Register 0 still reads as zero and cannot be written; that is done at the
-- output, so the RAM never has to be special-cased.

entity Register_File is
    port(
        clk, reset, reg_write: in std_logic;
        commit: in std_logic;
        read_reg1, read_reg2, write_reg: in std_logic_vector(4 downto 0);
        write_data: in std_logic_vector(31 downto 0);
		ready: out std_logic;
        reg_data1, reg_data2: out std_logic_vector(31 downto 0);

        -- Observation only, for the hardware bring-up. Drives nothing.
        dbg_state: out std_logic_vector(3 downto 0)
    );
end Register_File;

architecture A_Register_File of Register_File is

    component ram_dp
        generic (ADDR_BITS : natural; INIT : word_array);
        port (
            clk    : in  std_logic;
            a_addr : in  std_logic_vector(ADDR_BITS - 1 downto 0);
            a_we   : in  std_logic;
            a_din  : in  std_logic_vector(31 downto 0);
            a_dout : out std_logic_vector(31 downto 0);
            b_addr : in  std_logic_vector(ADDR_BITS - 1 downto 0);
            b_we   : in  std_logic;
            b_din  : in  std_logic_vector(31 downto 0);
            b_dout : out std_logic_vector(31 downto 0)
        );
    end component;

    -- The bank powers up cleared.
    constant BANK_INIT : word_array(0 to 0) := (0 => (others => '0'));

	signal internal_ready: std_logic := '0';
	signal internal_reg_data1: std_logic_vector(31 downto 0);
	signal internal_reg_data2: std_logic_vector(31 downto 0);
	signal internal_read_reg1: std_logic_vector(4 downto 0) := (others => '0');
	signal internal_read_reg2: std_logic_vector(4 downto 0) := (others => '0');

	signal bank_we : std_logic := '0';

	constant ZEROS32 : std_logic_vector(31 downto 0) := (others => '0');

	type state_type is (set_state, write_state, reset_state, update_state);
	signal state, next_state: state_type;

begin

	-- The write point: one explicit commit strobe, raised by the CPU in its
	-- store_state. Keying the write on anything that moves during the
	-- instruction is what made the original re-execute an instruction three
	-- times (DIAGNOSIS.md §2.3). r0 is hardwired and never written.
	bank_we <= '1' when (commit = '1' and reg_write = '1'
	                     and write_reg /= "00000") else '0';

	-- Copy 1 serves read port 1, copy 2 serves read port 2. Port A of each is
	-- the shared write; its read output is unused.
	Bank1 : ram_dp
		generic map (ADDR_BITS => 5, INIT => BANK_INIT)
		port map (
			clk    => clk,
			a_addr => write_reg, a_we => bank_we, a_din => write_data,
			a_dout => open,
			b_addr => read_reg1, b_we => '0',     b_din => ZEROS32,
			b_dout => internal_reg_data1
		);

	Bank2 : ram_dp
		generic map (ADDR_BITS => 5, INIT => BANK_INIT)
		port map (
			clk    => clk,
			a_addr => write_reg, a_we => bank_we, a_din => write_data,
			a_dout => open,
			b_addr => read_reg2, b_we => '0',     b_din => ZEROS32,
			b_dout => internal_reg_data2
		);

	-- Latency tracking: which addresses the outputs currently answer for.
    process(clk, reset)
    begin
        if reset = '1' then
			state <= reset_state;
			internal_read_reg1 <= (others => '0');
			internal_read_reg2 <= (others => '0');

        elsif rising_edge(clk) then

			internal_read_reg1 <= read_reg1;
			internal_read_reg2 <= read_reg2;

			-- Restart the walk when the request changes, or right after a
			-- commit so the next read observes the value just written.
			if commit = '1'
			   or internal_read_reg1 /= read_reg1
			   or internal_read_reg2 /= read_reg2 then
				state <= set_state;
			else
				state <= next_state;
			end if;

        end if;
    end process;

	-- Pure next-state / ready decode. `ready` is asserted only in update_state,
	-- two cycles after the addresses were presented, because the RAM read is
	-- registered: asserting it earlier would advertise a value that is not on
	-- the bus yet, which is the defect this design already had once.
	process(state)
		variable ready_count : integer;
	begin
		ready_count := 0;
		next_state  <= set_state;

		case state is
			when reset_state  => next_state <= set_state;
			when set_state    => next_state <= write_state;
			when write_state  => next_state <= update_state;
			when update_state =>
				ready_count := 2;
				next_state  <= update_state;
			when others       => next_state <= set_state;
		end case;

		if ready_count = 2 then
			internal_ready <= '1';
		else
			internal_ready <= '0';
		end if;
	end process;

	-- Register 0 reads as zero regardless of what the RAM holds.
	reg_data1 <= (others => '0') when internal_read_reg1 = "00000" else internal_reg_data1;
    reg_data2 <= (others => '0') when internal_read_reg2 = "00000" else internal_reg_data2;

	-- `ready` means "these outputs answer the addresses being asked for RIGHT
	-- NOW", not "a read finished at some point".
	ready <= internal_ready when (internal_read_reg1 = read_reg1
	                              and internal_read_reg2 = read_reg2)
	         else '0';

	-- Which state the walk is in, so a stall is readable on the board rather
	-- than inferred. 1=reset 2=set 3=write 4=update.
	with state select dbg_state <=
		"0001" when reset_state,
		"0010" when set_state,
		"0011" when write_state,
		"0100" when update_state;

end A_Register_File;

-- Made with my soul - Swately <3
