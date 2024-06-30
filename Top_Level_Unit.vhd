library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Top_Level_Unit is
	port(
		reset : in std_logic;
        DISPLAY_SELECTOR: out std_logic_vector(3 downto 0);
		DISPLAY: out std_logic_vector(6 downto 0)
	);
end Top_Level_Unit;

architecture A_Top_Level_Unit of Top_Level_Unit is

	signal internal_clk : std_logic := '0';
	signal internal_clk_400Hz : std_logic := '0';
	signal internal_clk_1Hz : std_logic := '0';
	signal internal_dmode : std_logic := '1';
	signal internal_alu_result : std_logic_vector(31 downto 0) := (others => '0');
	signal internal_entry_value_display : std_logic_vector(12 downto 0) := (others => '0');

begin
	
	Clock_Inst: entity work.Clock(A_Clock)
		port map(
			CLK_24Hz => internal_clk,
            CLK_400Hz => internal_clk_400Hz
		);

    Display_Inst: entity work.Display(A_Display)
    port map(
        CLK_400Hz   => internal_clk_400Hz,
        dmode       => internal_dmode,
        DISPLAY_SELECTOR => DISPLAY_SELECTOR,
        DISPLAY => DISPLAY,
        entry_value => internal_entry_value_display
    );

	Central_Processing_Unit_inst: entity work.Central_Processing_Unit(A_Central_Processing_Unit)
    port map(
        clk => internal_clk,
		reset => reset,
		alu_result => internal_alu_result
    );

	process(internal_clk)
	begin
		if rising_edge(internal_clk) then
			internal_entry_value_display <= internal_alu_result(12 downto 0); 
		end if;
	end process;

end A_Top_Level_Unit;