library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Control_Unit
--
-- Decodes a 32-bit instruction into the datapath control signals. Structure is
-- unchanged from the original: the same instruction_state -> decode1 -> decode2
-- -> decode3/decode_alu -> update_state walk and the same ready handshake.
--
-- Repairs applied 2026-07-31 (see DIAGNOSIS.md §3):
--   * The control literals for LOADI/ADDI/SUBI/MOVE asserted bit 5 (IO_read)
--     instead of bit 1 (reg_write), so those instructions never wrote their
--     destination register. Corrected.
--   * STORE_IO asserted a LOAD-shaped pattern; it now asserts IO_write.
--   * No opcode asserted mem_write, so data memory was unwritable. STORE
--     (opcode 000110, the gap in the original numbering) was added.
--   * JUMP (opcode 001101) added; jump_address was decoded but unused.
--   * The bit-map comment in decode2 was the reverse of the assignments.
--   * The control word is widened 7 -> 8 bits; bit 7 (alu_imm) selects the
--     sign-extended immediate as ALU source B for the I-type instructions.
--   * `ready` now means "my outputs describe the word on my input", not "a
--     decode walk finished once".
--
-- Second pass, same day, after running GHDL's synthesiser over it:
--   * EVERY decoded field was a LATCH. The fields were assigned only in
--     decode1 from a COMBINATIONAL process, so in the other states they held
--     their value -- which is the textbook way to infer a latch. Simulation
--     cannot see this; `ghdl --synth` reports it as an error. All decoded
--     state now lives in the clocked process, and the combinational process
--     computes next_state and ready only.
--   * previous_state is gone. Its only purpose was `update_state ->
--     previous_state`, and update_state now simply holds until a new
--     instruction word arrives, which is what the restart condition already
--     detects. Keeping a signal whose sole role has been removed is how the
--     self-locking stall bug in the other modules survived unnoticed.

entity Control_Unit is
    port(
        clk, reset: in std_logic;
        instruction_in: in std_logic_vector(31 downto 0);
        src_reg, trg_reg, des_reg: out std_logic_vector(4 downto 0) := (others => '0');
        branch, reg_write, mem_write, mem_read, memto_reg, IO_read, IO_write, ready: out std_logic;
        alu_imm: out std_logic;
        -- JAL: route the return address (PC+1) to the ALU and the link
        -- register to the write port. Without a call/return pair, a routine
        -- cannot be reached from more than one place, so every "instruction
        -- built from other instructions" would have to be pasted at each call
        -- site instead of being a subroutine.
        link: out std_logic;
        immediate: out std_logic_vector(15 downto 0) := (others => '0');
        opcode: out std_logic_vector(5 downto 0) := (others => '0');
        alu_opcode: out std_logic_vector(3 downto 0) := (others => '0');
        -- Shift amount, instruction bits 10:6. The original decoded this field
        -- into a signal with zero readers -- it was parsed and thrown away
        -- because no instruction used it. The shift instructions use it now.
        shamt: out std_logic_vector(4 downto 0) := (others => '0');
		jump_address: out std_logic_vector(25 downto 0) := (others => '0');
        -- Legacy programmed-I/O side band. Superseded by memory-mapped I/O
        -- (peripherals live at the top of the data address space, so LOAD and
        -- STORE reach them with no new instruction). Kept because it is part
        -- of the original interface, driven to a defined value so it does not
        -- sit as an undriven inout.
        IO_addr, IO_data: inout std_logic_vector(31 downto 0) := (others => '0')
    );
end Control_Unit;

architecture A_Control_Unit of Control_Unit is

	type state_type is (instruction_state, decode1, decode2, decode3, decode_alu, update_state);
	signal state, next_state: state_type;

    signal function_signal         : std_logic_vector(5 downto 0) := (others => '0');
    signal shift_amount            : std_logic_vector(4 downto 0) := (others => '0');
    signal internal_jump_address   : std_logic_vector(25 downto 0) := (others => '0');
    signal internal_opcode         : std_logic_vector(5 downto 0) := (others => '0');
    signal internal_alu_opcode     : std_logic_vector(3 downto 0) := "1000";
    signal internal_instruction    : std_logic_vector(31 downto 0) := (others => '0');
    signal internal_control_signals : std_logic_vector(8 downto 0) := (others => '0');
	signal internal_src_reg	: std_logic_vector(4 downto 0) := (others => '0');
	signal internal_trg_reg	: std_logic_vector(4 downto 0) := (others => '0');
	signal internal_des_reg	: std_logic_vector(4 downto 0) := (others => '0');
	signal internal_immediate		: std_logic_vector(15 downto 0) := (others => '0');
	signal internal_ready			: std_logic := '0';

begin

	-- Clocked half: the state register and every decoded field. All of these
	-- are state that must persist across the decode walk, so they belong here;
	-- driving them from the combinational process is what inferred latches.
	process(clk, reset)
    begin
        if reset = '1' then
            state                    <= instruction_state;
            internal_instruction     <= (others => '0');
            internal_opcode          <= (others => '0');
            internal_src_reg         <= (others => '0');
            internal_trg_reg         <= (others => '0');
            internal_des_reg         <= (others => '0');
            internal_immediate       <= (others => '0');
            internal_jump_address    <= (others => '0');
            internal_control_signals <= (others => '0');
            internal_alu_opcode      <= "1000";
            function_signal          <= (others => '0');
            shift_amount             <= (others => '0');

		elsif rising_edge(clk) then

			case state is

				when instruction_state =>
					internal_instruction <= instruction_in;

				when decode1 =>
					internal_opcode       <= internal_instruction(31 downto 26);
					internal_src_reg      <= internal_instruction(25 downto 21);
					internal_trg_reg      <= internal_instruction(20 downto 16);
					internal_des_reg      <= internal_instruction(15 downto 11);
					internal_immediate    <= internal_instruction(15 downto 0);
					function_signal       <= internal_instruction(5 downto 0);
					internal_jump_address <= internal_instruction(25 downto 0);
					shift_amount          <= internal_instruction(10 downto 6);

				when decode2 =>
				-- Control word is std_logic_vector(8 downto 0); the leftmost
				-- character of each literal is bit 8. The mapping is fixed by
				-- the concurrent assignments at the end of this architecture:
				--   bit 8 link | bit 7 alu_imm | bit 6 IO_write | bit 5 IO_read
				--   bit 4 memto_reg | bit 3 mem_read | bit 2 mem_write
				--   bit 1 reg_write | bit 0 branch
					case internal_opcode is
						when "000001" => internal_control_signals <= "000000010"; -- ALU (R-type) -> des_reg
						when "000010" => internal_control_signals <= "000011010"; -- LOAD  mem -> trg_reg
						when "000011" => internal_control_signals <= "010000010"; -- LOADI imm -> trg_reg
						when "000100" => internal_control_signals <= "010000010"; -- ADDI  src+imm -> trg_reg
						when "000101" => internal_control_signals <= "010000010"; -- SUBI  src-imm -> trg_reg
						when "000110" => internal_control_signals <= "000000100"; -- STORE trg_reg -> mem
						when "000111" => internal_control_signals <= "010000010"; -- MOVE  src -> trg_reg
						when "001000" => internal_control_signals <= "000000001"; -- BEQ
						when "001001" => internal_control_signals <= "000000000"; -- HALT
						when "001010" => internal_control_signals <= "000000001"; -- BNE
						when "001011" => internal_control_signals <= "001000000"; -- STORE_IO
						when "001100" => internal_control_signals <= "000000000"; -- NOP
						when "001101" => internal_control_signals <= "000000001"; -- JUMP
						when "001110" => internal_control_signals <= "100000011"; -- JAL   link + reg_write + branch
						when "001111" => internal_control_signals <= "000000001"; -- JR    branch
						when others   => internal_control_signals <= "000000000";
					end case;

				when decode3 =>
					case internal_opcode is
						when "000011" => internal_alu_opcode <= "1001";  -- LOADI: pass source B
						when "000100" => internal_alu_opcode <= "0000";  -- ADDI
						when "000101" => internal_alu_opcode <= "0001";  -- SUBI
						when others   => internal_alu_opcode <= "1000";  -- pass source A
					end case;

				when decode_alu =>
					case function_signal is
						when "000000" => internal_alu_opcode <= "0000";  -- ADD
						when "000001" => internal_alu_opcode <= "0001";  -- SUB
						-- 000010 MUL and 000011 DIV are RESERVED. They are
						-- software routines now (see Arithmetic_Logic_Unit.vhd);
						-- the hardware returns zero rather than reusing the
						-- encodings, so an old binary cannot silently mean
						-- something different.
						when "000010" => internal_alu_opcode <= "1111";  -- MUL, reserved
						when "000011" => internal_alu_opcode <= "1111";  -- DIV, reserved
						when "000100" => internal_alu_opcode <= "0100";  -- AND
						when "000101" => internal_alu_opcode <= "0101";  -- OR
						when "000110" => internal_alu_opcode <= "0110";  -- XOR
						when "000111" => internal_alu_opcode <= "0111";  -- NOT
						when "001000" => internal_alu_opcode <= "1010";  -- SHL
						when "001001" => internal_alu_opcode <= "1011";  -- SHR
						when "001010" => internal_alu_opcode <= "1100";  -- SLT
						when "001011" => internal_alu_opcode <= "1101";  -- SLTU
						when others   => internal_alu_opcode <= "1000";
					end case;

				when others =>
					null;

			end case;

			-- A new instruction word restarts the decode walk.
			if instruction_in /= internal_instruction then
				state <= instruction_state;
			else
				state <= next_state;
			end if;

		end if;
    end process;

	-- Combinational half: next_state and ready. Drives no stored value, so it
	-- cannot infer a latch.
    process(state, internal_opcode)
    begin
        case state is
			when instruction_state => next_state <= decode1;
			when decode1           => next_state <= decode2;
			when decode2 =>
				if internal_opcode = "000001" then
					next_state <= decode_alu;
				else
					next_state <= decode3;
				end if;
			when decode3           => next_state <= update_state;
			when decode_alu        => next_state <= update_state;
			-- Hold: the restart condition in the clocked process is what pulls
			-- the walk back to instruction_state when a new word arrives.
			when update_state      => next_state <= update_state;
		end case;

		-- The decoded outputs are valid once the walk has reached its end.
		if state = update_state then
			internal_ready <= '1';
		else
			internal_ready <= '0';
		end if;

    end process;

    branch     <= internal_control_signals(0);
    reg_write  <= internal_control_signals(1);
    mem_write  <= internal_control_signals(2);
    mem_read   <= internal_control_signals(3);
    memto_reg  <= internal_control_signals(4);
    IO_read    <= internal_control_signals(5);
    IO_write   <= internal_control_signals(6);
    alu_imm    <= internal_control_signals(7);
    link       <= internal_control_signals(8);
    alu_opcode <= internal_alu_opcode;
	src_reg    <= internal_src_reg;
	trg_reg    <= internal_trg_reg;
	des_reg    <= internal_des_reg;
	immediate  <= internal_immediate;
	jump_address <= internal_jump_address;
    opcode     <= internal_opcode;
    shamt      <= shift_amount;

	-- Legacy programmed-I/O side band, parked (see the entity note).
	IO_addr <= (others => '0');
	IO_data <= (others => '0');

	-- `ready` must mean "the control signals on my outputs belong to the word
	-- currently on my input", not merely "a decode walk finished". The
	-- state-only version stayed asserted while a NEW instruction was already
	-- present but not yet decoded, and the CPU latched the previous
	-- instruction's destination register. It only showed up when two
	-- consecutive instructions shared an opcode -- three LOADIs in a row --
	-- because an opcode comparison in the CPU cannot tell them apart.
	ready <= internal_ready when instruction_in = internal_instruction else '0';

end A_Control_Unit;

-- Made with my soul - Swately <3
