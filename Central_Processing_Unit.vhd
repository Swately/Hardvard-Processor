library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Central_Processing_Unit is
    port(
        clk, reset: in std_logic
    );
end Central_Processing_Unit;

architecture A_Central_Processing_Unit of Central_Processing_Unit is
    
    -- Internal Signals
    signal internal_pc_address_in				: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_data_address_in				: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_instruction_address_in		: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_instruction_in				: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_alu_source_a				: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_alu_source_b				: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_data_memory_in				: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_write_data					: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_read_reg1					: std_logic_vector(4 downto 0) := (others => '0');
    signal internal_read_reg2					: std_logic_vector(4 downto 0) := (others => '0');
    signal internal_write_reg					: std_logic_vector(4 downto 0) := (others => '0');
    signal internal_src_reg						: std_logic_vector(4 downto 0) := (others => '0');
    signal internal_trg_reg						: std_logic_vector(4 downto 0) := (others => '0');
    signal internal_des_reg						: std_logic_vector(4 downto 0) := (others => '0');
    signal internal_alu_opcode					: std_logic_vector(3 downto 0) := (others => '0');
    signal internal_immediate					: std_logic_vector(15 downto 0) := (others => '0');
    signal internal_pc_address_out				: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_data_address_out			: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_instruction_address_out		: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_data_memory_out				: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_data_instruction_memory_out	: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_reg_data1					: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_reg_data2					: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_result						: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_result_low					: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_result_high					: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_opcode						: std_logic_vector(5 downto 0) := (others => '0');
    signal internal_IO_addr						: std_logic_vector(31 downto 0) := (others => '0');
    signal internal_IO_data						: std_logic_vector(31 downto 0) := (others => '0');
	signal internal_jump_address				: std_logic_vector(25 downto 0) := (others => '0');
    signal internal_zero						: std_logic := '0';
    signal internal_sign						: std_logic := '0';
    signal internal_carry						: std_logic := '0';
    signal internal_overflow					: std_logic := '0';
    signal internal_parity						: std_logic := '0';
    signal internal_branch						: std_logic := '0';
	signal internal_breaker						: std_logic := '0';
    signal internal_reg_write					: std_logic := '0';
    signal internal_mem_write					: std_logic := '0';
    signal internal_mem_read					: std_logic := '0';
    signal internal_memto_reg					: std_logic := '0';
    signal internal_IO_read						: std_logic := '0';
    signal internal_IO_write					: std_logic := '0';
    signal internal_data_memory_ready			: std_logic := '0';
    signal internal_data_register_ready			: std_logic := '0';
    signal internal_regfile_ready				: std_logic := '0';
    signal internal_pc_ready					: std_logic := '0';
    signal internal_cu_ready					: std_logic := '0';
    signal internal_ins_memory_ready			: std_logic := '0';
	
	type state_type is (cu_state, pc_state, alu_state, store_state, reg_state, halt_state, update_state);
	signal state, next_state, previous_state: state_type;

begin

	internal_data_address_in <= "0000000000000000" & internal_immediate;
	internal_instruction_in <= internal_data_instruction_memory_out;
	internal_instruction_address_in <= internal_pc_address_out;

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
		jump_address	=> internal_jump_address,
        opcode 			=> internal_opcode,
        IO_read     	=> internal_IO_read,
        IO_write    	=> internal_IO_write,
        IO_addr     	=> internal_IO_addr,
        immediate   	=> internal_immediate,
        alu_opcode  	=> internal_alu_opcode,
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
        reg_write  	=> internal_reg_write,
        read_reg1  	=> internal_read_reg1,
        read_reg2  	=> internal_read_reg2,
        write_reg  	=> internal_write_reg,
        write_data 	=> internal_write_data,
        reg_data1  	=> internal_reg_data1,
        reg_data2  	=> internal_reg_data2
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
        result 			=> internal_result,
        result_low 		=> internal_result_low,
        result_high 	=> internal_result_high,
        zero 			=> internal_zero,
        sign 			=> internal_sign,
        carry 			=> internal_carry,
        overflow 		=> internal_overflow,
        parity			=> internal_parity
    );

    Instruction_Memory_Address_Register_inst: entity work.Instruction_Memory_Address_Register(A_Instruction_Memory_Address_Register)
    port map(
        clk 					=> clk,
        reset 					=> reset,
        ready 					=> internal_ins_memory_ready,
        instruction_address_in 	=> internal_instruction_address_in,
        instruction_address_out => internal_instruction_address_out
    );
	
    Instruction_Memory_inst: entity work.Instruction_Memory(A_Instruction_Memory)
    port map(
        instruction_address_in 	=> internal_instruction_address_out,
        data_out 				=> internal_data_instruction_memory_out
    );

    Data_Memory_Address_Register_inst: entity work.Data_Memory_Address_Register(A_Data_Memory_Address_Register)
    port map(
        clk 				=> clk,
        reset 				=> reset,
        ready 				=> internal_data_register_ready,
        data_address_in 	=> internal_data_address_in,
        data_address_out 	=> internal_data_address_out
    );
	
    Data_Memory_inst: entity work.Data_Memory(A_Data_Memory)
    port map(
        clk 					=> clk,
        data_register_ready 	=> internal_data_register_ready,
        ready 					=> internal_data_memory_ready,
        write_data_enable 		=> internal_mem_write,
        data_address_in 		=> internal_data_address_out,
        data_in 				=> internal_result,
        data_out 				=> internal_data_memory_out
    );
	
	process(clk)
	begin
		if reset = '1' then
			state <= cu_state;
		elsif rising_edge(clk) or falling_edge(clk) then
			state <= next_state;
			previous_state <= state;
		end if;
	end process;
	
	process(state)
	begin
		case state is
		
			when cu_state =>
				if internal_cu_ready = '1' then
					next_state <= reg_state;
				else
					next_state <= update_state;
				end if;
				
			when reg_state => 
				internal_read_reg1 <= internal_src_reg;
				internal_read_reg2 <= internal_trg_reg;
				
				if internal_memto_reg = '1' then
					internal_write_data <= internal_data_memory_out;
					internal_write_reg <= internal_trg_reg;
					next_state <= alu_state;
				else
					internal_write_data <= internal_result;
					internal_write_reg <= internal_des_reg;
					next_state <= alu_state;
				end if;
				
				
			
			when alu_state =>
				
				if internal_regfile_ready = '1' then
					internal_alu_source_a <= internal_reg_data1;
					internal_alu_source_b <= internal_reg_data2;
					next_state <= pc_state;
				else
					next_state <= update_state;
				end if;
			
			when store_state =>
			
			when pc_state =>
			
			if	internal_data_memory_ready = '1' and internal_regfile_ready = '1' and internal_pc_ready = '1' and internal_ins_memory_ready = '1' and internal_cu_ready = '1' then
				if internal_branch = '1' then
					internal_pc_address_in <= "000000" & internal_jump_address;
					next_state <= cu_state;
				else
					internal_pc_address_in <= std_logic_vector(unsigned(internal_pc_address_out) + 1);
					next_state <= cu_state;
				end if;
			else
				next_state <= update_state;
			end if;
			
			
			
			when update_state =>
				if internal_opcode = "001001" then
					next_state <= halt_state;
				else
					next_state <= previous_state;
				end if;
				
			when halt_state =>
				next_state <= halt_state;
				
				
			when others =>
				next_state <= halt_state;
				
		end case;
	end process;
	
	


end A_Central_Processing_Unit;
