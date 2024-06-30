library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Display is 
	port(
		CLK_400Hz: in std_logic;
		DISPLAY_SELECTOR: out std_logic_vector(3 downto 0) := "1000";
		DISPLAY: out std_logic_vector(6 downto 0) := (others=>'0');
		entry_value: in std_logic_vector(12 downto 0);
		dmode: in std_logic
	);
end Display;

architecture A_Display of Display is
	signal D1, D2, D3, D4: std_logic_vector(6 downto 0) := (others=>'0');
	signal toInt: integer;
	signal unidades, decenas, centenas, miles: integer;
	signal internal_display_selector: std_logic_vector(3 downto 0) := "1000";
	
	TYPE DIG_ARRAY IS ARRAY (NATURAL RANGE <>) OF STD_LOGIC_VECTOR(6 DOWNTO 0);
	CONSTANT ADIG : DIG_ARRAY(0 to 10) :=(
		"0111111",   -- DIG 0 0
		"0000110",   -- DIG 1 1
		"1011011",   -- DIG 2 2
		"1001111",   -- DIG 3 3
		"1100110",   -- DIG 4 4
		"1101101",   -- DIG 5 5
		"1111101",   -- DIG 6 6
		"0000111",   -- DIG 7 7
		"1111111",   -- DIG 8 8
		"1100111",	 -- DIG 9 9
		"0000000"	 -- APAGADO 10
	);
	
	begin
	
	
	
	toInt <= to_integer(unsigned(entry_value));
	unidades <= toInt mod 10;
	decenas <= (toInt / 10) mod 10;
	centenas <= (toInt / 100) mod 10;
	miles <= (toInt / 1000) mod 10;

	
	
	process(CLK_400Hz, dmode)
	begin
		
		if dmode = '1' then
			D1 <= ADIG(miles);
			D2 <= ADIG(centenas);
			D3 <= ADIG(decenas);
			D4 <= ADIG(unidades);
			else
			D1 <= NOT ADIG(miles);
			D2 <= NOT ADIG(centenas);
			D3 <= NOT ADIG(decenas);
			D4 <= NOT ADIG(unidades);
		end if;

		if rising_edge(CLK_400Hz) then
			case internal_display_selector is
				when "1000" =>
					DISPLAY <= D3;-- Display 3
				when "0100" =>
					DISPLAY <= D2;-- Display 2
				when "0010" =>
					DISPLAY <= D1;-- Display 1
				when "0001" =>
					DISPLAY <= D4;-- Display 4
				when others =>
					DISPLAY <= (others => '0');
				end case;
				internal_display_selector <= to_stdlogicvector(to_bitvector(internal_display_selector)ROR 1);
		end if;

		DISPLAY_SELECTOR <= internal_display_selector;
	end process;
	
end A_Display;