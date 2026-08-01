library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Central_Processing_Unit
--
-- Structure unchanged from the original: the same component set, the same
-- instruction_state -> cu_state -> alu_state -> store_state -> pc_state walk
-- with update_state as the stall, and the same ready-gated handshake.
--
-- Repairs applied 2026-07-31 (see DIAGNOSIS.md):
--   * internal_data_memory_in was declared and wired to Data_Memory.data_in but
--     never assigned, so the memory write port was tied to zero. It now carries
--     the trg_reg value, which is what STORE writes.
--   * There was no path to place an immediate on an ALU source, so the I-type
--     instructions could not work even once their control word was fixed. The
--     new alu_imm control bit selects a sign-extended immediate as source B.
--   * The destination register was chosen by memto_reg alone, so the I-type
--     instructions would have written des_reg instead of trg_reg.
--   * alu_state compared internal_write_reg against des_reg/trg_reg to decide
--     whether to advance. For any non-writing instruction whose bits 15:11 are
--     non-zero, write_reg is forced to 0 and never matches, so the FSM loops in
--     cu_state forever. The shipped program only avoided this because its BNE
--     happens to have 15:11 = 00000. Replaced by a ready gate.
--   * store_state had the same shape of comparison against data_memory_out and
--     the same hazard. Replaced.
--   * JUMP (opcode 001101) added; jump_address was decoded and routed here but
--     no instruction ever used it.
--   * Sensitivity lists completed, reset added to the clocked process's list.
--   * Dead signals removed: internal_write_data, internal_data_address_in,
--     internal_breaker, internal_dmode had no readers.

entity Central_Processing_Unit is
    generic (
        -- Frequency of clk. Handed down to the peripheral block, whose LCD
        -- controller derives millisecond-scale timing from it. A CPU clock
        -- that does not match this generic produces a display that never
        -- initialises, so it is a generic and not a constant buried in a file.
        CLK_HZ : natural := 2_080_000
    );
    port(
        clk, reset                  : in std_logic;
        alu_result                  : out std_logic_vector(31 downto 0);
        synchronization_signals     : out std_logic_vector(4 downto 0);
        src_reg						: out std_logic_vector(4 downto 0);
        trg_reg						: out std_logic_vector(4 downto 0);
        des_reg						: out std_logic_vector(4 downto 0);

        -- Outside world, reached through memory-mapped I/O.
        buttons                     : in  std_logic_vector(4 downto 0) := (others => '0');
        ext_osc                     : in  std_logic := '0';
        digits                      : out std_logic_vector(15 downto 0);

        -- Bring-up observation window. Four hex digits, most significant
        -- first: CPU state | register-file state | handshake bits | low nibble
        -- of read port 2. Drives nothing inside the processor.
        debug                       : out std_logic_vector(15 downto 0)
    );
end Central_Processing_Unit;

architecture A_Central_Processing_Unit of Central_Processing_Unit is

    -- Internal Signals

    signal internal_pc_address_in				: std_logic_vector(31 downto 0) := (others => '0');
    -- Address of the instruction being executed. It is NOT the live program
    -- counter: pc_address_out moves the moment the counter accepts a new
    -- value, and feeding the incrementer from a moving base is what made the
    -- PC walk two addresses at a time. This register is stable for the whole
    -- instruction, which also makes it the right source for JAL's PC+1.
    signal internal_pc_current					: std_logic_vector(8 downto 0) := (others => '0');
    signal internal_pc_current_en				: std_logic := '0';
    signal internal_instruction_in				: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_alu_source_a				: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_alu_source_b				: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_data_memory_in				: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_read_reg1					: std_logic_vector(4 downto 0) := (others => '0');
    signal internal_read_reg2					: std_logic_vector(4 downto 0) := (others => '0');
    signal internal_write_reg					: std_logic_vector(4 downto 0) := (others => '0');
    signal internal_src_reg						: std_logic_vector(4 downto 0) := (others => '0');
    signal internal_trg_reg						: std_logic_vector(4 downto 0) := (others => '0');
    signal internal_des_reg						: std_logic_vector(4 downto 0) := (others => '0');
    signal internal_alu_opcode					: std_logic_vector(3 downto 0) := (others => '0');
    signal internal_shamt						: std_logic_vector(4 downto 0) := (others => '0');
    signal internal_immediate					: std_logic_vector(15 downto 0) := (others => '0');
    signal internal_immediate_ext				: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_pc_address_out				: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_data_memory_out				: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_data_instruction_memory_out	: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_fetch_addr_q				: std_logic_vector(8 downto 0) := (others => '0');
    signal internal_data_addr_q					: std_logic_vector(8 downto 0) := (others => '0');
    signal internal_fetch_valid					: std_logic := '0';
    signal internal_data_valid					: std_logic := '0';
    signal internal_reg_data1					: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_reg_data2					: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_result						: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_result_low					: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_result_high					: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_IO_addr						: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_IO_data						: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_full_adder_result           : std_logic_vector(32 downto 0) := (others => '0');
    signal internal_pc_base                     : std_logic_vector(31 downto 0) := (others => '0');
    signal internal_data_address                : std_logic_vector(31 downto 0) := (others => '0');
    signal internal_data_address_full           : std_logic_vector(32 downto 0) := (others => '0');
	signal internal_jump_address				: std_logic_vector(25 downto 0) := (others => '0');
    signal internal_opcode						: std_logic_vector(5 downto 0) := (others => '0');
    signal internal_zero						: std_logic := '0';
    signal internal_sign						: std_logic := '0';
    signal internal_carry						: std_logic := '0';
    signal internal_overflow					: std_logic := '0';
    signal internal_parity						: std_logic := '0';
    signal internal_branch						: std_logic := '0';
    signal internal_reg_write					: std_logic := '0';
    signal internal_mem_write					: std_logic := '0';
    signal internal_mem_read					: std_logic := '0';
    signal internal_memto_reg					: std_logic := '0';
    signal internal_alu_imm						: std_logic := '0';
    signal internal_link						: std_logic := '0';
    signal internal_data_we						: std_logic := '0';

    -- Memory-mapped I/O. The top sixteen words of the address space are
    -- peripherals rather than RAM: 0x1F0..0x1FF, i.e. addr(8 downto 4) all
    -- ones. LOAD and STORE reach them with no new instruction.
    signal internal_io_sel						: std_logic := '0';
    signal internal_io_sel_q					: std_logic := '0';
    signal internal_io_dout						: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_mem_dout					: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_mem_we						: std_logic := '0';
    signal internal_io_we						: std_logic := '0';

    -- The link register. r31 by convention, as in MIPS's $ra.
    constant LINK_REG : std_logic_vector(4 downto 0) := "11111";
    signal internal_IO_read						: std_logic := '0';
    signal internal_IO_write					: std_logic := '0';
    signal internal_regfile_ready				: std_logic := '0';
    signal internal_reg_commit					: std_logic := '0';
    signal internal_pc_ready					: std_logic := '0';
    signal internal_cu_ready					: std_logic := '0';

	type state_type is (instruction_state, cu_state, pc_state, alu_state, store_state, reg_state, halt_state, update_state);
	signal state, next_state, previous_state: state_type;

	-- Observation only. VCD cannot represent an enumerated type, so the FSM
	-- state is mirrored onto a vector to make it visible in a waveform dump.
	-- It drives nothing.
	signal state_dbg, prev_state_dbg : std_logic_vector(3 downto 0) := (others => '0');

	-- The register file's own walk state, brought out so a stall can be READ
	-- off the board instead of guessed at. Simulation cannot see this problem:
	-- it only appears on silicon.
	signal internal_regfile_dbg : std_logic_vector(3 downto 0) := (others => '0');

	function state_code(s : state_type) return std_logic_vector is
	begin
		case s is
			when instruction_state => return "0001";
			when cu_state          => return "0010";
			when alu_state         => return "0011";
			when store_state       => return "0100";
			when pc_state          => return "0101";
			when reg_state         => return "0110";
			when halt_state        => return "0111";
			when update_state      => return "1000";
		end case;
	end function;

begin

	state_dbg      <= state_code(state);
	prev_state_dbg <= state_code(previous_state);

	-- What the board shows during bring-up.
	--   digit 3: which state the processor is in
	--   digit 2: which state the register file is in
	--   digit 1: commit, regfile_ready, fetch_valid, cu_ready
	--   digit 0: low nibble of read port 2 -- for `store r4, DIGITS` with
	--            r4 = 0x1234 this must read 4, which proves the RAM gave back
	--            what was written to it.
	debug <= state_dbg
	         & internal_regfile_dbg
	         & (internal_reg_commit & internal_regfile_ready
	            & internal_fetch_valid & internal_cu_ready)
	         & internal_reg_data2(3 downto 0);

    Control_Unit_inst: entity work.Control_Unit(A_Control_Unit)
    port map(
        clk         	=> clk,
        reset       	=> reset,
        ready 			=> internal_cu_ready,
        instruction_in 	=> internal_instruction_in,
        branch      	=> internal_branch,
        reg_write   	=> internal_reg_write,
        mem_write   	=> internal_mem_write,
        mem_read    	=> internal_mem_read,
        memto_reg   	=> internal_memto_reg,
        alu_imm         => internal_alu_imm,
        link            => internal_link,
		jump_address	=> internal_jump_address,
        opcode 			=> internal_opcode,
        IO_read     	=> internal_IO_read,
        IO_write    	=> internal_IO_write,
        IO_addr     	=> internal_IO_addr,
        immediate   	=> internal_immediate,
        alu_opcode  	=> internal_alu_opcode,
        shamt           => internal_shamt,
        src_reg     	=> internal_src_reg,
        trg_reg     	=> internal_trg_reg,
        des_reg     	=> internal_des_reg,
        IO_data     	=> internal_IO_data
    );

    Register_File_inst: entity work.Register_File(A_Register_File)
    port map(
        clk        	=> clk,
        reset      	=> reset,
        ready		=> internal_regfile_ready,
        commit      => internal_reg_commit,
        reg_write  	=> internal_reg_write,
        read_reg1  	=> internal_src_reg,
        read_reg2  	=> internal_trg_reg,
        write_reg  	=> internal_write_reg,
        write_data 	=> internal_result,
        reg_data1  	=> internal_reg_data1,
        reg_data2  	=> internal_reg_data2,
        dbg_state   => internal_regfile_dbg
    );

    Program_Counter_inst: entity work.Program_Counter(A_Program_Counter)
    port map(
        clk            			=> clk,
        reset          			=> reset,
        ready					=> internal_pc_ready,
        pc_address_in  			=> internal_pc_address_in,
        pc_address_out 			=> internal_pc_address_out
    );

    Arithmetic_Logic_Unit_inst: entity work.Arithmetic_Logic_Unit(A_Arithmetic_Logic_Unit)
    port map(
        alu_source_a 	=> internal_alu_source_a,
        alu_source_b 	=> internal_alu_source_b,
        alu_opcode 		=> internal_alu_opcode,
        shamt           => internal_shamt,
        result 			=> internal_result,
        result_low 		=> internal_result_low,
        result_high 	=> internal_result_high,
        zero 			=> internal_zero,
        sign_flag 		=> internal_sign,
        carry 			=> internal_carry,
        overflow 		=> internal_overflow,
        parity			=> internal_parity
    );

    -- ------------------------------------------------------------------
    -- Memory: one modified-Harvard system replaces four modules.
    -- ------------------------------------------------------------------
    -- Gone from here: Instruction_Memory, Data_Memory, and both address
    -- registers. The address registers were three-state machines with a ready
    -- handshake; what actually needed tracking was never a protocol, it was
    -- the memory's own one-cycle read latency, and that belongs inside the
    -- memory. Data_Memory's entire FSM disappears with them.
    --
    -- What the CPU still keeps is internal_pc_current below -- the address of
    -- the instruction being executed. That is an architectural value, not a
    -- memory-interface detail: the incrementer needs a base that does not move
    -- while the instruction runs, and JAL needs it to form the return address.
    Memory_System_inst: entity work.Memory_System(structural)
    generic map(
        BANK_ADDR_BITS => 8            -- two banks of 256, 512 words in all
    )
    port map(
        clk          => clk,
        reset        => reset,
        fetch_addr   => internal_pc_address_out(8 downto 0),
        fetch_data   => internal_data_instruction_memory_out,
        fetch_addr_q => internal_fetch_addr_q,
        fetch_valid  => internal_fetch_valid,
        data_addr    => internal_data_address(8 downto 0),
        data_we      => internal_mem_we,
        data_din     => internal_data_memory_in,
        data_dout    => internal_mem_dout,
        data_addr_q  => internal_data_addr_q,
        data_valid   => internal_data_valid
    );

    Peripherals_inst: entity work.Peripherals(structural)
    generic map(
        CLK_HZ => CLK_HZ
    )
    port map(
        clk     => clk,
        reset   => reset,
        addr    => internal_data_address(3 downto 0),
        we      => internal_io_we,
        din     => internal_data_memory_in,
        dout    => internal_io_dout,
        buttons => buttons,
        ext_osc => ext_osc,
        digits  => digits
    );

    -- A store commits on the same one-cycle strobe as a register write, so a
    -- memory write and a register write can never disagree about when the
    -- instruction took effect.
    internal_data_we <= internal_mem_write and internal_reg_commit;

    -- ------------------------------------------------------------------
    -- The address decode. This is the whole I/O mechanism.
    -- ------------------------------------------------------------------
    internal_io_sel <= '1' when internal_data_address(8 downto 4) = "11111"
                       else '0';

    internal_mem_we <= internal_data_we and (not internal_io_sel);
    internal_io_we  <= internal_data_we and internal_io_sel;

    -- Both sides read synchronously, so the select has to be delayed by the
    -- same cycle as the data it is choosing between.
    process(clk, reset)
    begin
        if reset = '1' then
            internal_io_sel_q <= '0';
        elsif rising_edge(clk) then
            internal_io_sel_q <= internal_io_sel;
        end if;
    end process;

    internal_data_memory_out <= internal_io_dout when internal_io_sel_q = '1'
                                else internal_mem_dout;

    PC_Current_Reg: entity work.register_n(structural)
    generic map(
        WIDTH => 9
    )
    port map(
        clk => clk,
        rst => reset,
        en  => internal_pc_current_en,
        d   => internal_pc_address_out(8 downto 0),
        q   => internal_pc_current
    );

	-- Increment base: see the note on internal_pc_current. Zero-extension is
	-- wiring, not logic.
	internal_pc_base <= "00000000000000000000000" & internal_pc_current;

	-- The current-instruction address is captured at the moment the fetch is
	-- known good.
	internal_pc_current_en <= '1' when (state = instruction_state
	                                    and internal_fetch_valid = '1') else '0';

    Full_Adder_32bits: entity work.Full_Adder_32bits(A_Full_Adder_32bits)
    port map(
        entry_a => internal_pc_base,
        entry_b => "00000000000000000000000000000001",
        mode => '0',
        result => internal_full_adder_result
    );

	-- ------------------------------------------------------------------
	-- Address adder: the data address is BASE REGISTER + IMMEDIATE.
	-- ------------------------------------------------------------------
	-- The original used the immediate alone, which makes every address a
	-- constant compiled into the instruction -- and with only constant
	-- addresses there is no stack, no array indexing and no pointer of any
	-- kind. A routine cannot even save its own return address.
	--
	-- Nothing was added to the instruction set to fix that. `src` was already
	-- decoded and unused by LOAD and STORE, and r0 reads as zero, so an
	-- absolute address is just the case where the base register is r0:
	--
	--     load  rt, addr        ==  load  rt, addr(r0)     0 + addr
	--     store rt, off(sp)     ==  the stack
	--
	-- Register-indirect addressing is a SUPERSET of what was there, and every
	-- program written against the old form keeps working unchanged. The cost
	-- is one more 32-bit adder, built from the same ripple-carry cell as the
	-- other two.
	Address_Adder: entity work.Full_Adder_32bits(A_Full_Adder_32bits)
	port map(
		entry_a => internal_reg_data1,
		entry_b => internal_immediate_ext,
		mode    => '0',
		result  => internal_data_address_full
	);

	internal_data_address <= internal_data_address_full(31 downto 0);

	-- STORE writes the trg_reg word, which the register file presents on
	-- reg_data2. This assignment is the one the original was missing.
	internal_data_memory_in <= internal_reg_data2;

	-- Sign-extended immediate, the ALU's source B for the I-type instructions.
	internal_immediate_ext <= std_logic_vector(resize(signed(internal_immediate), 32));

	-- The register-file write point. store_state lasts exactly one cycle, so
	-- this is a one-cycle strobe: the ALU result for this instruction is final
	-- by then, and committing here removes the write/read entanglement that
	-- made the original re-execute an instruction three times.
	internal_reg_commit <= '1' when state = store_state else '0';

	-- Clocked half: the state register, and every datapath register the FSM
	-- writes. The original updated these from the COMBINATIONAL process, which
	-- means each one was an inferred latch fed by a case statement.
	process(clk, reset)
	begin
		if reset = '1' then
			state <= instruction_state;
			previous_state <= instruction_state;
			internal_instruction_in <= (others => '0');
			internal_alu_source_a <= (others => '0');
			internal_alu_source_b <= (others => '0');
			internal_write_reg <= (others => '0');
			internal_pc_address_in <= (others => '0');

		elsif rising_edge(clk) then
			-- previous_state must never be allowed to become update_state.
			-- update_state's exit is `next_state <= previous_state`, so if the
			-- stall lasts two consecutive cycles the second one records
			-- update_state as the place to return to and the FSM locks up
			-- pointing at itself. The original captured it unconditionally.
			if state /= update_state then
				previous_state <= state;
			end if;

			-- Datapath actions, selected by the CURRENT state.
			case state is

				when instruction_state =>
					-- Latch only once the program counter has reached the
					-- value pc_state asked for AND the memory says the word on
					-- the instruction bus belongs to that address. fetch_valid
					-- also covers a store having just landed in code space,
					-- which a plain address comparison could not see.
					if internal_pc_address_out = internal_pc_address_in
					   and internal_fetch_valid = '1' then
						internal_instruction_in <= internal_data_instruction_memory_out;
					end if;

				when cu_state =>
					-- Gated on the register file too: the original sampled
					-- reg_data1/reg_data2 on cu_ready alone, so it captured the
					-- previous instruction's operands. The opcode comparison
					-- proves the control unit has decoded THIS instruction and
					-- not the previous one whose `ready` is still asserted.
					if internal_cu_ready = '1' and internal_regfile_ready = '1'
					   and internal_data_valid = '1'
					   and internal_opcode = internal_instruction_in(31 downto 26) then
						if internal_link = '1' then
							-- JAL: the return address is PC+1, which the
							-- incrementer already has on its output, and it
							-- goes to the link register through the ordinary
							-- write port. No separate return-address path.
							internal_alu_source_a <= internal_full_adder_result(31 downto 0);
							internal_alu_source_b <= (others => '0');
							internal_write_reg    <= LINK_REG;

						elsif internal_memto_reg = '1' then
							-- LOAD: the memory word goes straight through the ALU.
							internal_alu_source_a <= internal_data_memory_out;
							internal_alu_source_b <= (others => '0');
							if internal_reg_write = '1' then
								internal_write_reg <= internal_trg_reg;
							else
								internal_write_reg <= (others => '0');
							end if;

						elsif internal_alu_imm = '1' then
							-- I-type: source B is the sign-extended immediate
							-- and the destination is trg_reg, not des_reg.
							internal_alu_source_a <= internal_reg_data1;
							internal_alu_source_b <= internal_immediate_ext;
							if internal_reg_write = '1' then
								internal_write_reg <= internal_trg_reg;
							else
								internal_write_reg <= (others => '0');
							end if;

						else
							-- R-type and everything else: two register sources,
							-- destination des_reg.
							internal_alu_source_a <= internal_reg_data1;
							internal_alu_source_b <= internal_reg_data2;
							if internal_reg_write = '1' then
								internal_write_reg <= internal_des_reg;
							else
								internal_write_reg <= (others => '0');
							end if;
						end if;
					end if;

				when pc_state =>
					-- The branch decision must see the value the instruction
					-- just committed, so it waits for the re-read.
					if internal_regfile_ready = '0' then
						null;
					elsif internal_branch = '1' and internal_opcode = "001000"  -- BEQ
					   and internal_reg_data1 = internal_reg_data2 then
						internal_pc_address_in <= "0000000000000000" & internal_immediate;

					elsif internal_branch = '1' and internal_opcode = "001010"  -- BNE
					      and internal_reg_data1 /= internal_reg_data2 then
						internal_pc_address_in <= "0000000000000000" & internal_immediate;

					elsif internal_branch = '1' and internal_opcode = "001101" then -- JUMP
						internal_pc_address_in <= "000000" & internal_jump_address;

					elsif internal_branch = '1' and internal_opcode = "001110" then -- JAL
						internal_pc_address_in <= "000000" & internal_jump_address;

					elsif internal_branch = '1' and internal_opcode = "001111" then -- JR
						-- Return: the target comes from a register, so a
						-- routine can go back to whoever called it.
						internal_pc_address_in <= internal_reg_data1;

					else
						internal_pc_address_in <= internal_full_adder_result(31 downto 0);
					end if;

				when others =>
					null;

			end case;

			-- State transition. Precedence made explicit; the original wrote
			-- three unconditional assignments to `state` in sequence and relied
			-- on last-one-wins.
			if state = halt_state then
				-- HALT is terminal. Without this the re-fetch override below
				-- pulled the FSM back out of halt and the PC kept walking.
				state <= halt_state;

			elsif state = store_state then
				-- store_state is the commit strobe and must last exactly one
				-- cycle, so it is exempt from any stall.
				state <= pc_state;

			else
				state <= next_state;
			end if;

			-- The original had two further overrides here, applied in EVERY
			-- state: force instruction_state when
			-- pc_address_out(7:0) /= instruction_address_in, and force
			-- update_state when the register file was not ready. The first one
			-- is a fetch trigger that fires wherever the FSM happens to be, so
			-- the PC increment of one instruction lands in the middle of the
			-- next one and aborts it before it can commit -- measured: the SUB
			-- reached alu_state with the correct operands and was yanked to
			-- instruction_state one cycle before store_state. Both stalls are
			-- now expressed inside the states that need them.

		end if;
	end process;

	-- Combinational half: next_state only. Drives no datapath register.
	process(state, previous_state, internal_opcode, internal_cu_ready,
	        internal_regfile_ready, internal_data_valid, internal_fetch_valid,
	        internal_pc_address_out, internal_pc_address_in,
	        internal_instruction_in)
	begin
		next_state <= update_state;

		case state is

			when instruction_state =>
				-- Hold until the counter has settled AND the memory vouches
				-- for the word on the instruction bus.
				if internal_pc_address_out = internal_pc_address_in
				   and internal_fetch_valid = '1' then
					next_state <= cu_state;
				else
					next_state <= instruction_state;
				end if;

			when cu_state =>
				-- The data bus is in the gate too: a LOAD samples data_dout
				-- here, and the original sampled it without ever checking that
				-- the memory had produced it.
				if internal_cu_ready = '1' and internal_regfile_ready = '1'
				   and internal_data_valid = '1'
				   and internal_opcode = internal_instruction_in(31 downto 26) then
					if internal_opcode = "001001" then      -- HALT
						next_state <= halt_state;
					else
						next_state <= alu_state;
					end if;
				else
					next_state <= cu_state;
				end if;

			when alu_state =>
				-- Advance once the control unit and the register file are both
				-- settled. The original compared internal_write_reg against
				-- des_reg/trg_reg here, which deadlocks for any non-writing
				-- instruction whose bits 15:11 are non-zero.
				if internal_cu_ready = '1' and internal_regfile_ready = '1' then
					next_state <= store_state;
				else
					next_state <= alu_state;
				end if;

			when store_state =>
				-- One cycle only; the clocked process forces the exit.
				next_state <= pc_state;

			when pc_state =>
				-- Hold until the register file has re-read after the commit, so
				-- that a branch decides on the value this instruction just
				-- wrote. Staying here is harmless: the increment is idempotent
				-- because it is based on instruction_address_in.
				if internal_regfile_ready = '1' then
					next_state <= instruction_state;
				else
					next_state <= pc_state;
				end if;

			when reg_state =>
				next_state <= pc_state;

			when update_state =>
				next_state <= previous_state;

			when halt_state =>
				next_state <= halt_state;

			when others =>
				next_state <= halt_state;

		end case;

	end process;

    alu_result <= internal_result;
    synchronization_signals(0) <= internal_cu_ready;
    synchronization_signals(1) <= internal_pc_ready;
    synchronization_signals(2) <= internal_fetch_valid;
    synchronization_signals(3) <= internal_regfile_ready;
    synchronization_signals(4) <= internal_data_valid;
    src_reg <= internal_src_reg;
    trg_reg <= internal_trg_reg;
    des_reg <= internal_des_reg;


end A_Central_Processing_Unit;

-- Made with my soul - Swately <3
