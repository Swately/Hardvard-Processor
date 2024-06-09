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
	signal internal_reg_data: std_logic_vector(31 downto 0) := (others => 'X');
begin
    process(clk, reset)
    begin
        if reset = '1' then
            for i in 0 to 31 loop
                register_bank(i) <= (others => '0');
            end loop;
        elsif rising_edge(clk) then
            if reg_write = '1' then
                register_bank(to_integer(unsigned(write_reg))) <= write_data;
				internal_reg_data <= write_data;
            end if;
        end if;
    end process;
	
	process(clk, reset)
	begin
		if reset = '1' then
			internal_ready <= '0';
		elsif falling_edge(clk) then
			internal_ready <= '1';
			if reg_write = '1' then
                if internal_reg_data /= write_data then
					internal_ready <= '0';
				else
					internal_reg_data <= (others => 'X');
					internal_ready <= '1';
				end if;
            end if;
		end if;
	end process;
    reg_data1 <= register_bank(to_integer(unsigned(read_reg1)));
    reg_data2 <= register_bank(to_integer(unsigned(read_reg2)));
	ready <= internal_ready;
end A_Register_File;
