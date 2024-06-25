library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Control_Unit is
    port(
        clk, reset: in std_logic;
        instruction_in: in std_logic_vector(31 downto 0);
        src_reg, trg_reg, des_reg: out std_logic_vector(4 downto 0) := (others => '0');
        branch, reg_write, mem_write, mem_read, memto_reg, IO_read, IO_write, ready: out std_logic;
        immediate: out std_logic_vector(15 downto 0) := (others => '0');
        opcode: out std_logic_vector(5 downto 0) := (others => '0');
        alu_opcode: out std_logic_vector(3 downto 0) := (others => '0');
		jump_address: out std_logic_vector(25 downto 0) := (others => '0');
        IO_addr, IO_data: inout std_logic_vector(31 downto 0) := (others => '0')
    );
end Control_Unit;

architecture A_Control_Unit of Control_Unit is
	
	type state_type is (instruction_state, decode1, decode2, decode3, decode_alu, ready_state);
	signal state, next_state, previous_state: state_type;
	
    signal function_signal         : std_logic_vector(5 downto 0) := (others => '0');
    signal shift_amount            : std_logic_vector(4 downto 0) := (others => '0');
    signal internal_jump_address   : std_logic_vector(25 downto 0) := (others => '0');
    signal internal_opcode         : std_logic_vector(5 downto 0) := (others => '0');
    signal internal_alu_opcode     : std_logic_vector(3 downto 0) := (others => 'X');
    signal internal_instruction    : std_logic_vector(31 downto 0) := (others => 'X');
    signal internal_control_signals : std_logic_vector(6 downto 0) := (others => 'X');
	signal internal_ready					 : std_logic := '0';
	signal internal_alu_opcode_ready         : std_logic := '0';
	signal internal_instruction_ready          : std_logic := '0';
	signal internal_opcode_ready          : std_logic := '0';
	signal update_counter : integer := 0;
	signal reset_counter : integer := 0;
	
begin

	process(clk, reset)
    begin
        if reset = '1' then
            state <= instruction_state;
		elsif rising_edge(clk) or falling_edge(clk) then
			state <= next_state;
			previous_state <= state;
			
			if instruction_in /= internal_instruction then
				state <= instruction_state;
			end if;
		end if;
		
    end process;
        
    process(state, internal_opcode, reset)
    begin
        case state is
			
			when instruction_state =>
				internal_ready <= '0';
				update_counter <= 0;
				internal_instruction <= instruction_in;
				next_state <= decode1;
				
			
			when decode1 =>
				internal_opcode <= internal_instruction(31 downto 26);
				src_reg         <= internal_instruction(25 downto 21);
				trg_reg         <= internal_instruction(20 downto 16);
				des_reg         <= internal_instruction(15 downto 11);
				immediate       <= internal_instruction(15 downto 0);
				function_signal <= internal_instruction(5 downto 0);
				jump_address    <= internal_instruction(25 downto 0);
				shift_amount    <= internal_instruction(10 downto 6); 
				internal_ready <= '0';
				update_counter <= 1;
				next_state <= decode2;
				
			when decode2 =>
			--branch (6);reg_write (5);mem_write(4);mem_read(3); memto_reg(2);IO_read(1);IO_write(0);
				case internal_opcode is
					when "000001" => -- ALU operation
						internal_control_signals <= "0000010";
						update_counter <= 2;
						next_state <= decode_alu;
					when "000010" => -- LOAD
						internal_control_signals <= "0011010";
						update_counter <= 2;
						next_state <= decode3;
					when "000011" => -- LOADI
						internal_control_signals <= "0100000";
						update_counter <= 2;
						next_state <= decode3;
					when "000100" => -- ADDI
						internal_control_signals <= "0100000";
						update_counter <= 2;
						next_state <= decode3;
					when "000101" => -- SUBI
						internal_control_signals <= "0100000";
						update_counter <= 2;
						next_state <= decode3;
					when "000111" => -- MOVE REG
						internal_control_signals <= "0100000";
						update_counter <= 2;
						next_state <= decode3;
					when "001000" => -- BNZ
						internal_control_signals <= "0000001";
						update_counter <= 2;
						next_state <= decode3;
					when "001001" => -- HALT
						internal_control_signals <= "0000000";
						update_counter <= 2;
						next_state <= decode3;
					when "001010" => -- STORE
						internal_control_signals <= "0010000";
						update_counter <= 2;
						next_state <= decode3;
					when "001011" => -- STORE_IO
						IO_addr <= (others => '0');
						internal_control_signals <= "0010010";
						update_counter <= 2;
						next_state <= decode3;
					when "001100" => -- NOP
						IO_addr <= (others => '0');
						internal_control_signals <= "0000000";
						update_counter <= 2;
						next_state <= decode3;
					when others =>
						internal_control_signals <= "0000000";
						IO_addr <= (others => '0');
						update_counter <= 2;
						next_state <= decode3;
				end case;
				internal_ready <= '0';
			
			when decode3 =>
				case internal_opcode is
					when "000010" => -- LOAD
						internal_alu_opcode <= "1000";
						update_counter <= 3;
						next_state <= ready_state;
					when "000011" => -- LOADI
						internal_alu_opcode <= "1000";
						update_counter <= 3;
						next_state <= ready_state;
					when "000100" => -- ADDI
						internal_alu_opcode <= "0000";
						update_counter <= 3;
						next_state <= ready_state;
					when "000101" => -- SUBI
						internal_alu_opcode <= "0001";
						update_counter <= 3;
						next_state <= ready_state;
					when "000111" => -- MOVE
						internal_alu_opcode <= "1000";
						update_counter <= 3;
						next_state <= ready_state;
					when "001000" => -- BNZ
						internal_alu_opcode <= "1000";
						update_counter <= 3;
						next_state <= ready_state;
					when "001001" => -- HALT
						internal_alu_opcode <= "1000";
						update_counter <= 3;
						next_state <= ready_state;
					when "001010" => -- STORE
						internal_alu_opcode <= "1000";
						update_counter <= 3;
						next_state <= ready_state;
					when "001011" => -- STORE_IO
						IO_addr <= (others => '0');
						internal_alu_opcode <= "1000";
						update_counter <= 3;
						next_state <= ready_state;
					when "001100" => -- NOP
						IO_addr <= (others => '0');
						internal_alu_opcode <= "1000";
						update_counter <= 3;
						next_state <= ready_state;
					when others =>
						update_counter <= 3;
						next_state <= ready_state;
				end case;
				internal_ready <= '0';
			
			when decode_alu =>
				case function_signal is
					when "000000" => -- ADD 
						internal_alu_opcode <= "0000";
						update_counter <= 3;
						next_state <= ready_state;
					when "000001" => -- SUB
						internal_alu_opcode <= "0001";
						update_counter <= 3;
						next_state <= ready_state;
					when "000010" => -- MUL
						internal_alu_opcode <= "0010";
						update_counter <= 3;
						next_state <= ready_state;
					when "000011" => -- DIV
						internal_alu_opcode <= "0011";
						update_counter <= 3;
						next_state <= ready_state;
					when "000100" => -- AND
						internal_alu_opcode <= "0100";
						update_counter <= 3;
						next_state <= ready_state;
					when "000101" => -- OR
						internal_alu_opcode <= "0101";
						update_counter <= 3;
						next_state <= ready_state;
					when "000110" => -- XOR
						internal_alu_opcode <= "0110";
						update_counter <= 3;
						next_state <= ready_state;
					when "000111" => -- NOT
						internal_alu_opcode <= "0111";
						update_counter <= 3;
						next_state <= ready_state;
					when others =>
						internal_alu_opcode <= "1000";
						update_counter <= 3;
						next_state <= ready_state;
				end case;
				internal_ready <= '0';
			
			when ready_state =>
				if update_counter = 3 then
					internal_ready <= '1';
				else
					internal_ready <= '0';
				end if;
				
				if internal_instruction /= instruction_in then
					next_state <= instruction_state;
				end if;
				
			when others =>
				next_state <= instruction_state;
				
		end case;
		
    end process;
	
	
    

    branch <= internal_control_signals(0);
    reg_write <= internal_control_signals(1);
    mem_write <= internal_control_signals(2);
    mem_read <= internal_control_signals(3);
    memto_reg <= internal_control_signals(4);
    IO_read <= internal_control_signals(5);
    IO_write <= internal_control_signals(6);
    alu_opcode <= internal_alu_opcode;
    opcode <= internal_opcode;
	ready <= internal_ready;

end A_Control_Unit;
