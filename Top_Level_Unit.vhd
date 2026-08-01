library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Top_Level_Unit
--
-- Board top level: internal oscillator -> Clock dividers -> CPU at 24 Hz, with
-- the ALU result on the 4-digit 7-segment display and the handshake signals on
-- LEDs.
--
-- Repair applied 2026-07-31 (see DIAGNOSIS.md §2.2): the display was fed
-- alu_result(31 downto 19) -- the TOP 13 bits of a 32-bit result. With the
-- shipped program that is the constant 190, and the counter had to fall by
-- 2^19 = 524,288 before a single digit moved: one visible change every 2.9
-- days. Wired to (12 downto 0) the same program updates the display every
-- 0.47 s. This one line is the main reason the board looked dead.

entity Top_Level_Unit is
	generic (
		-- Frequency of clk_in. The divider chain and anything else timed is
		-- derived from it, so retargeting a board is a generic change.
		CLK_HZ : natural := 133_000_000
	);
	port(
		-- Free-running board clock. The oscillator itself is NOT instantiated
		-- here any more: it is device-specific and lives in the board wrapper
		-- (Board_MachXO2.vhd). That is what makes this file portable and
		-- simulatable without a vendor primitive model.
		clk_in : in std_logic;
		reset : in std_logic;
		buttons : in std_logic_vector(4 downto 0) := (others => '0');
		ext_osc : in std_logic := '0';

		-- Bring-up switch. Low: the display shows what the PROGRAM wrote. High:
		-- it shows the processor's internal state instead. One bitstream serves
		-- both, so diagnosing a stall costs a switch flip rather than a rebuild
		-- and a reflash -- which matters, because the only failure that has
		-- actually bitten this design so far is one simulation cannot see.
		dbg_mode : in std_logic := '0';
        DISPLAY_SELECTOR: out std_logic_vector(3 downto 0);
		DISPLAY: out std_logic_vector(6 downto 0);
		synchronization_signals: out std_logic_vector(4 downto 0);
		src_reg_led: out std_logic_vector(4 downto 0);
        trg_reg_led: out std_logic_vector(4 downto 0);
        des_reg_led: out std_logic_vector(4 downto 0)

		-- The character-LCD bundle that used to be declared here is gone
		-- (2026-08-01). The board's multiplexed 7-segment display is the
		-- output, it was already wired and validated on hardware, and the LCD
		-- controller cost 302 LUT4 (measured) on a part the design did not fit.
		-- LCD_Controller.vhd stays in the tree, unused, for whenever a display
		-- is connected again.
	);
end Top_Level_Unit;

architecture A_Top_Level_Unit of Top_Level_Unit is

	-- Display polarity select. A constant, not a signal: nothing drives it and
	-- leaving it as an undriven signal only produced a synthesis warning.
	constant internal_dmode : std_logic := '1';
	signal internal_alu_result : std_logic_vector(31 downto 0) := (others => '0');
	signal internal_digits : std_logic_vector(15 downto 0) := (others => '1');
	signal internal_debug  : std_logic_vector(15 downto 0) := (others => '0');
	signal shown_digits    : std_logic_vector(15 downto 0) := (others => '1');

	-- The reset everything downstream actually uses. NOT the pin.
	signal internal_reset  : std_logic;

begin

	-- Reset the design at power-up instead of trusting a switch to have been
	-- flipped. The pin is still honoured, so a manual restart still works, but
	-- nothing depends on it any more. Without this the processor started in an
	-- illegal state and stayed there -- see power_on_reset.vhd.
	Power_On_Reset_Inst: entity work.power_on_reset(rtl)
		generic map (HOLD_CYCLES => 1024)
		port map (
			clk       => clk_in,
			reset_in  => reset,
			reset_out => internal_reset
		);

	-- The multiplexer selects between two wires; it does not compute either of
	-- them. Same rule as everywhere else in this design.
	shown_digits <= internal_debug when dbg_mode = '1' else internal_digits;

	-- Clock.vhd is no longer instantiated. Its whole purpose was to hand the
	-- CPU a 24 Hz debug clock and the display a 400 Hz sweep; the CPU now runs
	-- at the full board clock, and the display derives its own sweep from
	-- CLK_HZ. Six 32-bit divider counters measured 600 cells for one signal
	-- that a single prescaler inside Display now produces.

    Display_Inst: entity work.Display(A_Display)
		generic map(
			CLK_HZ  => CLK_HZ,
			STEP_HZ => 400
		)
		port map(
			clk         => clk_in,
			reset       => internal_reset,
			digits      => shown_digits,
			dmode       => internal_dmode,
			DISPLAY_SELECTOR => DISPLAY_SELECTOR,
			DISPLAY     => DISPLAY
		);

	-- The CPU runs at the FULL board clock, not at the 24 Hz divider it used
	-- to. That divider was a debug aid for watching the state machine by eye;
	-- at 1.2 instructions per second the machine cannot drive anything.
	Central_Processing_Unit_inst: entity work.Central_Processing_Unit(A_Central_Processing_Unit)
		generic map(
			CLK_HZ => CLK_HZ
		)
		port map(
			clk => clk_in,
			reset => internal_reset,
			alu_result => internal_alu_result,
			synchronization_signals => synchronization_signals,
			src_reg => src_reg_led,
			trg_reg => trg_reg_led,
			des_reg => des_reg_led,
			buttons => buttons,
			ext_osc => ext_osc,
			digits  => internal_digits,
			debug   => internal_debug
		);

	-- The LCD bundle is no longer parked: the CPU drives it through the
	-- memory-mapped peripheral block. RW is still held low inside
	-- LCD_Controller, so the display remains write-only, its D0..D7 drivers
	-- stay in high impedance, and no 5 V signal is ever presented to a MachXO2
	-- pin. The direction that could damage the FPGA does not exist here.
	--
	-- The remaining direction, FPGA -> LCD, is still the one to check before
	-- wiring a 5 V module: an HD44780-class part typically wants
	-- VIH >= 0.7 x VDD = 3.5 V, which a 3.3 V bank cannot reach. It usually
	-- works and is out of spec regardless; the clean options are the 3.0 V
	-- variant of the display or level shifters on RS/E/D0..D7.
	-- [GK, unverified: 0.7 x VDD is the usual HD44780 family figure, not read
	--  from the WH1602W datasheet.]

end A_Top_Level_Unit;

-- Made with my soul - Swately <3