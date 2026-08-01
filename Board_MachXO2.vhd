library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Board_MachXO2
--
-- THE ONLY DEVICE-SPECIFIC FILE IN THIS PROJECT.
--
-- It supplies a MachXO2 with its internal oscillator and hands the resulting
-- clock to the portable Top_Level_Unit. Everything else in the repository is
-- plain VHDL that simulates and synthesises anywhere; retargeting means
-- writing a sibling of this file, not touching the core.
--
-- To target something else:
--   * a board with an external crystal -> a wrapper with a `clk` input port
--     and no oscillator primitive at all, with CLK_HZ set to the crystal;
--   * another vendor -> a wrapper instantiating that vendor's oscillator or
--     PLL.
--
-- AREA, MEASURED BY THE VENDOR FLOW 2026-08-01 -- the real thing, not an
-- estimate: 1,400 LUT4 of 6,864 (20%), 625 registers (9%), 12 of 26 block RAMs
-- (46%), post-route Fmax 21.716 MHz with zero timing errors.
-- Reproduce with: python syn/build_vendor.py
--
-- An earlier version of this comment said the design was 298% of the part with
-- hardware MUL and DIV and did not fit. That came from an open-source
-- estimator that cannot use the part's carry chains and does not infer block
-- RAM; it was roughly 8x pessimistic. The design fitted all along. See
-- syn/VENDOR_VS_ESTIMATE.md.
--
-- OSCH at 2.08 MHz is the setting already proven on this board during the
-- Holith bring-up. The CPU retires an instruction every 20.3 clock cycles
-- (measured), so 2.08 MHz is about 102,000 instructions per second.

entity Board_MachXO2 is
    port(
        reset : in std_logic;
        buttons : in std_logic_vector(4 downto 0);
        -- Second oscillator for the entropy experiment, fed in on a pin. It
        -- was reaching the CPU and the portable top but had never been added
        -- HERE, so on the real board it went nowhere: the vendor map reported
        -- `COMP "ext_osc" cannot be found in design` and quietly disabled the
        -- constraint. A port that exists everywhere except at the boundary is
        -- a port that does not exist.
        ext_osc : in std_logic := '0';
        -- S1-2: flip up to read the processor's internals on the display.
        dbg_mode : in std_logic := '0';
        DISPLAY_SELECTOR : out std_logic_vector(3 downto 0);
        DISPLAY : out std_logic_vector(6 downto 0);
        synchronization_signals : out std_logic_vector(4 downto 0);
        src_reg_led : out std_logic_vector(4 downto 0);
        trg_reg_led : out std_logic_vector(4 downto 0);
        des_reg_led : out std_logic_vector(4 downto 0)
    );
end Board_MachXO2;

architecture A_Board_MachXO2 of Board_MachXO2 is

    -- Lattice MachXO2 internal oscillator. Diamond supplies the real thing;
    -- sim/OSCH_sim.vhd is the behavioural stand-in and must never be added to
    -- a synthesis project.
    component OSCH
        generic (NOM_FREQ : string := "2.08");
        port (
            STDBY    : in  std_logic;
            OSC      : out std_logic;
            SEDSTDBY : out std_logic
        );
    end component;

    constant CLK_HZ : natural := 2_080_000;

    signal clk : std_logic;

begin

    OSC_Inst : OSCH
        generic map (NOM_FREQ => "2.08")
        port map (
            STDBY    => '0',
            OSC      => clk,
            SEDSTDBY => open
        );

    Core : entity work.Top_Level_Unit(A_Top_Level_Unit)
        generic map (
            CLK_HZ => CLK_HZ
        )
        port map (
            clk_in                  => clk,
            reset                   => reset,
            buttons                 => buttons,
            ext_osc                 => ext_osc,
            dbg_mode                => dbg_mode,
            DISPLAY_SELECTOR        => DISPLAY_SELECTOR,
            DISPLAY                 => DISPLAY,
            synchronization_signals => synchronization_signals,
            src_reg_led             => src_reg_led,
            trg_reg_led             => trg_reg_led,
            des_reg_led             => des_reg_led
        );

end A_Board_MachXO2;

-- Made with my soul - Swately <3
