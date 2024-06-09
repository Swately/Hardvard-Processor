library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Control_Unit_tb is
end Control_Unit_tb;

architecture A_Control_Unit_tb of Control_Unit_tb is

	--Inputs
	signal clk				: std_logic := '0';
	signal reset			: std_logic := '0';
	signal instruction_in	: std_logic_vector(31 downto 0) := (others => '0');
	--Outputs
	signal branch			: std_logic := '0';
	signal reg_write		: std_logic := '0';
	signal mem_write		: std_logic := '0';
	signal mem_read			: std_logic := '0';
	signal memto_reg		: std_logic := '0';
	signal IO_read			: std_logic := '0';
	signal IO_write			: std_logic := '0';
	signal IO_addr			: std_logic_vector(31 downto 0) := (others => '0');
	signal immediate		: std_logic_vector(15 downto 0) := (others => '0');
	signal alu_opcode		: std_logic_vector(3 downto 0) := (others => '0');
	signal src_reg			: std_logic_vector(4 downto 0) := (others => '0');
	signal trg_reg			: std_logic_vector(4 downto 0) := (others => '0');
	signal des_reg			: std_logic_vector(4 downto 0) := (others => '0');
	signal jump_address		: std_logic_vector(25 downto 0) := (others => '0');
	--Inout signals
	signal IO_data			: std_logic_vector(31 downto 0) := (others => '0');
	--Other signals
	signal function_signal	: std_logic_vector(5 downto 0) := (others => '0');
	signal shift_amount		: std_logic_vector(4 downto 0) := (others => '0');
	signal address			: std_logic_vector(25 downto 0) := (others => '0');
	-- Clock period definition
    constant clk_period : time := 5 ns;
	-- Control signal
	signal cu_ready        	: std_logic := '0';
	
begin
		
	Control_Unit_inst: entity work.Control_Unit(A_Control_Unit)
    port map(
        clk         	=> clk,
        reset       	=> reset,
		ready			=> cu_ready,
        instruction_in 	=> instruction_in,
        branch      	=> branch,
        reg_write   	=> reg_write,
		jump_address	=> jump_address,
        mem_write   	=> mem_write,
        mem_read    	=> mem_read,
        memto_reg   	=> memto_reg,
        IO_read     	=> IO_read,
        IO_write    	=> IO_write,
        IO_addr     	=> IO_addr,
        immediate   	=> immediate,
        alu_opcode  	=> alu_opcode,
        src_reg     	=> src_reg,
        trg_reg     	=> trg_reg,
        des_reg     	=> des_reg,
        IO_data     	=> IO_data
    );

	
	-- Clock process:
    clk_process : process
    begin
        clk <= '0';
        wait for clk_period/2;
        clk <= '1';
        wait for clk_period/2;
    end process;
	
	-- Stimulus process:
	stim_proc:process
	begin
		report("----------Starting simulation----------");
		
		report("----------Initialize inputs----------");
		reset 				<= '1';
		instruction_in 		<= (others => '0');
		IO_data 			<= (others => '0');
        wait for 20 ns;
		report("----------End of initialize inputs----------");
		
		report("----------Release reset----------");
		reset <= '0';
		report("----------End of release reset----------");
		
		--R: "000000 00000 00000 00000 00000 000000" I: "000000 00000 00000 0000000000000000" J: "000000 00000000000000000000000000"
		report("----------Test 1: load memory 0 to register 0----------");
		-- "000010 00000 00000 0000000000000000" LOAD data_memory 0 a registro 0 del banco de registros en este caso trg_reg es el registro donde se almacenara e immediate sera la direccion de la memoria
		instruction_in <= "00001000000000000000000000000000";
		wait for clk_period;
		report "instruction_in = " & to_string(instruction_in);
		report "branch = " & std_logic'image(branch);
		report "reg_write = " & std_logic'image(reg_write);
		report "mem_write = " & std_logic'image(mem_write);
		report "mem_read = " & std_logic'image(mem_read);
		report "memto_reg = " & std_logic'image(memto_reg);
		report "IO_read = " & std_logic'image(IO_read);
		report "IO_write = " & std_logic'image(IO_write);
		report "src_reg = " & to_string(src_reg);
		report "trg_reg = " & to_string(trg_reg);
		report "des_reg = " & to_string(des_reg);
		report "immediate = " & to_string(immediate);
		report "alu_opcode = " & to_string(alu_opcode);
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		report("----------End of Test 1----------");
		
		report("----------Test 2: load memory 10 to register 1----------");
		-- "000010 00000 00001 0000000000001010" LOAD data_memory 10 a registro 1 del banco de registros opcode, sr, tr, imm
		instruction_in <= "00001000000000010000000000001010";
		wait for clk_period;
		report "instruction_in = " & to_string(instruction_in);
		report "branch = " & std_logic'image(branch);
		report "reg_write = " & std_logic'image(reg_write);
		report "mem_write = " & std_logic'image(mem_write);
		report "mem_read = " & std_logic'image(mem_read);
		report "memto_reg = " & std_logic'image(memto_reg);
		report "IO_read = " & std_logic'image(IO_read);
		report "IO_write = " & std_logic'image(IO_write);
		report "src_reg = " & to_string(src_reg);
		report "trg_reg = " & to_string(trg_reg);
		report "des_reg = " & to_string(des_reg);
		report "immediate = " & to_string(immediate);
		report "alu_opcode = " & to_string(alu_opcode);
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		report("----------End of Test 2----------");
		
		report("----------Test 3: mul register 0 and register 1 and save on register 2----------");
		--R: "000001 00000 00001 00010 00000 000010"
		instruction_in <= "00000100000000010001000000000010";
		wait for clk_period;
		report "instruction_in = " & to_string(instruction_in);
		report "branch = " & std_logic'image(branch);
		report "reg_write = " & std_logic'image(reg_write);
		report "mem_write = " & std_logic'image(mem_write);
		report "mem_read = " & std_logic'image(mem_read);
		report "memto_reg = " & std_logic'image(memto_reg);
		report "IO_read = " & std_logic'image(IO_read);
		report "IO_write = " & std_logic'image(IO_write);
		report "src_reg = " & to_string(src_reg);
		report "trg_reg = " & to_string(trg_reg);
		report "des_reg = " & to_string(des_reg);
		report "immediate = " & to_string(immediate);
		report "alu_opcode = " & to_string(alu_opcode);
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		report("----------End of Test 3----------");
		
		report("----------Test 4: load memory 1 to register 3----------");
		-- "000010 00000 00011 0000000000000001" LOAD data_memory 1 a registro 3 del banco de registros en este caso trg_reg es el registro donde se almacenara e immediate sera la direccion de la memoria
		instruction_in <= "00001000000000110000000000000001";
		wait for clk_period;
		report "instruction_in = " & to_string(instruction_in);
		report "branch = " & std_logic'image(branch);
		report "reg_write = " & std_logic'image(reg_write);
		report "mem_write = " & std_logic'image(mem_write);
		report "mem_read = " & std_logic'image(mem_read);
		report "memto_reg = " & std_logic'image(memto_reg);
		report "IO_read = " & std_logic'image(IO_read);
		report "IO_write = " & std_logic'image(IO_write);
		report "src_reg = " & to_string(src_reg);
		report "trg_reg = " & to_string(trg_reg);
		report "des_reg = " & to_string(des_reg);
		report "immediate = " & to_string(immediate);
		report "alu_opcode = " & to_string(alu_opcode);
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		report("----------End of Test 4----------");
		
		report("----------Test 5: load memory 12 to register 4----------");
		-- "000010 00000 00100 0000000000001100" LOAD data_memory 12 a registro 4 del banco de registros en este caso trg_reg es el registro donde se almacenara e immediate sera la direccion de la memoria
		instruction_in <= "00001000000001000000000000001100";
		wait for clk_period;
		report "instruction_in = " & to_string(instruction_in);
		report "branch = " & std_logic'image(branch);
		report "reg_write = " & std_logic'image(reg_write);
		report "mem_write = " & std_logic'image(mem_write);
		report "mem_read = " & std_logic'image(mem_read);
		report "memto_reg = " & std_logic'image(memto_reg);
		report "IO_read = " & std_logic'image(IO_read);
		report "IO_write = " & std_logic'image(IO_write);
		report "src_reg = " & to_string(src_reg);
		report "trg_reg = " & to_string(trg_reg);
		report "des_reg = " & to_string(des_reg);
		report "immediate = " & to_string(immediate);
		report "alu_opcode = " & to_string(alu_opcode);
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		report("----------End of Test 5----------");
		
		report("----------Test 6: HALT----------");
		-- "000010 00000 00100 0000000000001100" HALT
		instruction_in <= "00100100000000000000000000000000";
		wait for clk_period;
		report "instruction_in = " & to_string(instruction_in);
		report "branch = " & std_logic'image(branch);
		report "reg_write = " & std_logic'image(reg_write);
		report "mem_write = " & std_logic'image(mem_write);
		report "mem_read = " & std_logic'image(mem_read);
		report "memto_reg = " & std_logic'image(memto_reg);
		report "IO_read = " & std_logic'image(IO_read);
		report "IO_write = " & std_logic'image(IO_write);
		report "src_reg = " & to_string(src_reg);
		report "trg_reg = " & to_string(trg_reg);
		report "des_reg = " & to_string(des_reg);
		report "immediate = " & to_string(immediate);
		report "alu_opcode = " & to_string(alu_opcode);
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		report("----------End of Test 6----------");
		
		report("----------Test 7: MOVE----------");
		-- "000010 00000 00100 0000000000001100" MOVE data_memory 12 a registro 4 del banco de registros en este caso trg_reg es el registro donde se almacenara e immediate sera la direccion de la memoria
		instruction_in <= "00011100000001000000000000001100";
		wait for clk_period;
		report "instruction_in = " & to_string(instruction_in);
		report "branch = " & std_logic'image(branch);
		report "reg_write = " & std_logic'image(reg_write);
		report "mem_write = " & std_logic'image(mem_write);
		report "mem_read = " & std_logic'image(mem_read);
		report "memto_reg = " & std_logic'image(memto_reg);
		report "IO_read = " & std_logic'image(IO_read);
		report "IO_write = " & std_logic'image(IO_write);
		report "src_reg = " & to_string(src_reg);
		report "trg_reg = " & to_string(trg_reg);
		report "des_reg = " & to_string(des_reg);
		report "immediate = " & to_string(immediate);
		report "alu_opcode = " & to_string(alu_opcode);
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		report("----------End of Test 7----------");
		
		report("----------Initialize inputs----------");
		reset 				<= '1';
		instruction_in 		<= (others => '0');
		IO_data 			<= (others => '0');
        wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		report("----------End of initialize inputs----------");
		
		report("----------Release reset----------");
		reset <= '0';
        wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		report("----------End of release reset----------");
		
		report("----------Test 7: MOVE----------");
		-- "000010 00000 00100 0000000000001100" MOVE data_memory 12 a registro 4 del banco de registros en este caso trg_reg es el registro donde se almacenara e immediate sera la direccion de la memoria
		instruction_in <= "00011100000001000000000000001100";
		wait for clk_period;
		report "instruction_in = " & to_string(instruction_in);
		report "branch = " & std_logic'image(branch);
		report "reg_write = " & std_logic'image(reg_write);
		report "mem_write = " & std_logic'image(mem_write);
		report "mem_read = " & std_logic'image(mem_read);
		report "memto_reg = " & std_logic'image(memto_reg);
		report "IO_read = " & std_logic'image(IO_read);
		report "IO_write = " & std_logic'image(IO_write);
		report "src_reg = " & to_string(src_reg);
		report "trg_reg = " & to_string(trg_reg);
		report "des_reg = " & to_string(des_reg);
		report "immediate = " & to_string(immediate);
		report "alu_opcode = " & to_string(alu_opcode);
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		wait for clk_period;
		report("----------End of Test 7----------");
		
		report("----------End of simulation----------");
		
		wait;
	end process;

end A_Control_Unit_tb;