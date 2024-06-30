library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Clock is 
	port(
		CLK, CLK_1Hz, CLK_24Hz, CLK_60Hz, CLK_120Hz, CLK_360Hz, CLK_400Hz: out std_logic
	);
	
end Clock;

architecture A_Clock of Clock is 

component OSCH
	generic (NOM_FREQ: string); -- := "2.08" Frecuencia programable
	port(
		STDBY: in std_logic;
		OSC: out std_logic
	);
	
end component;

	ATTRIBUTE NOM_FREQ: string;
	ATTRIBUTE NOM_FREQ of OSInst0: label is "133MHz";
	signal counter_1Hz, counter_24Hz, counter_60Hz, counter_120Hz, counter_360Hz, counter_400Hz: unsigned(31 downto 0) := (others => '0');
	signal tick_1Hz, tick_24Hz, tick_60Hz, tick_120Hz, tick_360Hz, tick_400Hz: std_logic := '0';
	signal internalCLK: std_logic := '0';
	
	begin
	
	OSInst0: OSCH
	generic map(NOM_FREQ => "133")
	port map(
		STDBY => '0',
		OSC => internalCLK
	);
	
	process(internalCLK)
	begin
		if rising_edge(internalCLK) then
			if counter_1Hz = 133000000 then
				tick_1Hz <= not tick_1Hz;
				counter_1Hz <= (others => '0');
			else
				counter_1Hz <= counter_1Hz + 1;
			end if;
			if counter_24Hz = 2770833 then
				tick_24Hz <= not tick_24Hz;
				counter_24Hz <= (others => '0');
			else
				counter_24Hz <= counter_24Hz + 1;
			end if;
			if counter_60Hz = 1108333 then
				tick_60Hz <= not tick_60Hz;
				counter_60Hz <= (others => '0');
			else
				counter_60Hz <= counter_60Hz + 1;
			end if;
			if counter_120Hz = 554167 then
				tick_120Hz <= not tick_120Hz;
				counter_120Hz <= (others => '0');
			else
				counter_120Hz <= counter_120Hz + 1;
			end if;
			if counter_360Hz = 184722 then
				tick_360Hz <= not tick_360Hz;
				counter_360Hz <= (others => '0');
			else
				counter_360Hz <= counter_360Hz + 1;
			end if;
			if counter_400Hz = 166250 then
				tick_400Hz <= not tick_400Hz;
				counter_400Hz <= (others => '0');
			else
				counter_400Hz <= counter_400Hz + 1;
			end if;
		end if;
	end process;
	CLK_1Hz <= tick_1Hz;
	CLK_24Hz <= tick_24Hz;
	CLK_60Hz <= tick_60Hz;
	CLK_120Hz <= tick_120Hz;
	CLK_360Hz <= tick_360Hz;
	CLK_400Hz <= tick_400Hz;
	CLK <= internalCLK; 
	
end A_Clock;
