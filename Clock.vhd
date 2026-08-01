library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Clock
--
-- Clock divider chain. Takes a free-running input clock and produces the slow
-- enables the rest of the design runs on.
--
-- DEVICE-INDEPENDENT (changed 2026-07-31). The original instantiated Lattice's
-- OSCH primitive directly, which nailed the whole design to a MachXO2 and made
-- it unsimulatable without a vendor model. The oscillator now belongs to the
-- board wrapper (see Board_MachXO2.vhd); this file is plain portable VHDL and
-- runs on any FPGA, or none.
--
-- The divider constants are derived from CLK_HZ instead of being hard-coded
-- for 133 MHz. At CLK_HZ = 133_000_000 the computed values reproduce the
-- original ones exactly (24 Hz -> 2,770,833; 400 Hz -> 166,250), so this is a
-- generalisation and not a retune.
--
-- One original constant is NOT reproduced, deliberately: CLK_1Hz counted to
-- 133,000,000 where every other divider counted a HALF period, so it produced
-- 0.5 Hz. The formula below gives a true 1 Hz.

entity Clock is
    generic (
        -- Frequency of clk_in, in hertz. Everything else follows from it.
        CLK_HZ : natural := 133_000_000
    );
	port(
        clk_in : in std_logic;
		CLK, CLK_1Hz, CLK_24Hz, CLK_60Hz, CLK_120Hz, CLK_360Hz, CLK_400Hz: out std_logic
	);
end Clock;

architecture A_Clock of Clock is

    -- A square wave at f toggles every CLK_HZ/(2f) input cycles.
    function half_period(f : natural) return natural is
        variable n : natural;
    begin
        n := CLK_HZ / (2 * f);
        if n < 1 then
            return 1;
        end if;
        return n - 1;          -- the counter compares against this and resets
    end function;

    constant N_1Hz   : natural := half_period(1);
    constant N_24Hz  : natural := half_period(24);
    constant N_60Hz  : natural := half_period(60);
    constant N_120Hz : natural := half_period(120);
    constant N_360Hz : natural := half_period(360);
    constant N_400Hz : natural := half_period(400);

	signal counter_1Hz, counter_24Hz, counter_60Hz, counter_120Hz,
	       counter_360Hz, counter_400Hz : unsigned(31 downto 0) := (others => '0');
	signal tick_1Hz, tick_24Hz, tick_60Hz, tick_120Hz,
	       tick_360Hz, tick_400Hz : std_logic := '0';

begin

	process(clk_in)
	begin
		if rising_edge(clk_in) then
			if counter_1Hz = N_1Hz then
				tick_1Hz <= not tick_1Hz;
				counter_1Hz <= (others => '0');
			else
				counter_1Hz <= counter_1Hz + 1;
			end if;
			if counter_24Hz = N_24Hz then
				tick_24Hz <= not tick_24Hz;
				counter_24Hz <= (others => '0');
			else
				counter_24Hz <= counter_24Hz + 1;
			end if;
			if counter_60Hz = N_60Hz then
				tick_60Hz <= not tick_60Hz;
				counter_60Hz <= (others => '0');
			else
				counter_60Hz <= counter_60Hz + 1;
			end if;
			if counter_120Hz = N_120Hz then
				tick_120Hz <= not tick_120Hz;
				counter_120Hz <= (others => '0');
			else
				counter_120Hz <= counter_120Hz + 1;
			end if;
			if counter_360Hz = N_360Hz then
				tick_360Hz <= not tick_360Hz;
				counter_360Hz <= (others => '0');
			else
				counter_360Hz <= counter_360Hz + 1;
			end if;
			if counter_400Hz = N_400Hz then
				tick_400Hz <= not tick_400Hz;
				counter_400Hz <= (others => '0');
			else
				counter_400Hz <= counter_400Hz + 1;
			end if;
		end if;
	end process;

	CLK_1Hz   <= tick_1Hz;
	CLK_24Hz  <= tick_24Hz;
	CLK_60Hz  <= tick_60Hz;
	CLK_120Hz <= tick_120Hz;
	CLK_360Hz <= tick_360Hz;
	CLK_400Hz <= tick_400Hz;
	CLK       <= clk_in;

end A_Clock;

-- Made with my soul - Swately <3
