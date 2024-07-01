library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Top_Level_Unit is
	port(
		reset : in std_logic;
        DISPLAY_SELECTOR: out std_logic_vector(3 downto 0);
		DISPLAY: out std_logic_vector(6 downto 0);
		synchronization_signals: out std_logic_vector(4 downto 0);
		src_reg_led: out std_logic_vector(4 downto 0);
        trg_reg_led: out std_logic_vector(4 downto 0);
        des_reg_led: out std_logic_vector(4 downto 0)
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
			entry_value => internal_alu_result(31 downto 19)
		);

	Central_Processing_Unit_inst: entity work.Central_Processing_Unit(A_Central_Processing_Unit)
		port map(
			clk => internal_clk,
			reset => reset,
			alu_result => internal_alu_result,
			synchronization_signals => synchronization_signals,
			src_reg => src_reg_led,
			trg_reg => trg_reg_led,
			des_reg => des_reg_led
		);

end A_Top_Level_Unit;