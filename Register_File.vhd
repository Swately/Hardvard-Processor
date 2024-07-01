library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Register_File is
    port(
        clk, reset, reg_write: in std_logic;
        read_reg1, read_reg2, write_reg: in std_logic_vector(4 downto 0);
        write_data: in std_logic_vector(31 downto 0);
		ready: out std_logic;
        reg_data1, reg_data2: out std_logic_vector(31 downto 0)
    );
end Register_File;

architecture A_Register_File of Register_File is
    type Register_Array is array(0 to 31) of std_logic_vector(31 downto 0);
    signal register_bank: Register_Array;
	signal internal_ready: std_logic := '0';
	signal internal_write_data: std_logic_vector(31 downto 0) := (others => '0');
	signal internal_reg_data1: std_logic_vector(31 downto 0) := (others => '0');
	signal internal_reg_data2: std_logic_vector(31 downto 0) := (others => '0');
	signal internal_write_reg: std_logic_vector(4 downto 0) := (others => '0');
	signal internal_read_reg1: std_logic_vector(4 downto 0) := (others => '0');
	signal internal_read_reg2: std_logic_vector(4 downto 0) := (others => '0');
	
	type state_type is (set_state, write_state, reset_state, update_state);
	signal state, next_state, previous_state: state_type;
begin
	
    process(clk, reset, write_data, write_reg, read_reg1, read_reg2)
    begin
        if reset = '1' then
			state <= reset_state;
        elsif rising_edge(clk) then
           state <= next_state;
		   previous_state <= state;
		   
		   	if reg_write = '1' then
				if internal_write_data /= write_data or internal_write_reg /= write_reg then
					state <= set_state;
				end if;
			else
				if internal_read_reg1 /= read_reg1 or internal_read_reg2 /= read_reg2 then
					state <= set_state;
				end if;
			end if;
        end if;
    end process;
	
	process(state, write_data, write_reg, read_reg1, read_reg2, reg_write)
		variable ready_count : integer;
	begin
		case state is
		
			when reset_state =>
				for i in 0 to 31 loop
					register_bank(i) <= (others => '0');
				end loop;
				ready_count := 0;
				next_state <= set_state;
				
			when set_state =>
				internal_write_data <= write_data;
				internal_write_reg <= write_reg;
				internal_read_reg1 <= read_reg1;
				internal_read_reg2 <= read_reg2;
				ready_count := 1;
				next_state <= write_state;
				
			when write_state =>
			
				if internal_write_data = write_data and internal_write_reg = write_reg and internal_read_reg1 = read_reg1 and internal_read_reg2 = read_reg2 then
					if reg_write = '1' then
						register_bank(to_integer(unsigned(internal_write_reg))) <= internal_write_data;
					end if;

					internal_reg_data1 <= register_bank(to_integer(unsigned(internal_read_reg1)));
					internal_reg_data2 <= register_bank(to_integer(unsigned(internal_read_reg2)));
					next_state <= update_state;
					ready_count := 2;
				else
					next_state <= set_state;
				end if;

			when update_state =>
				next_state <= previous_state;
				
			when others =>
				next_state <= set_state;

		end case;
				
		if ready_count = 2 then
			internal_ready <= '1';
		else
			internal_ready <= '0';
		end if;
	end process;
	
	reg_data1 <= internal_reg_data1;
    reg_data2 <= internal_reg_data2;
	ready <= internal_ready;
	
end A_Register_File;
