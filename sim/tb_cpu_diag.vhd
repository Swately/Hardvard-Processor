-- tb_cpu_diag.vhd -- Diagnostic testbench for Central_Processing_Unit.
--
-- Purpose: run the CPU as-is against the program already sitting in
-- Instruction_Memory and dump every internal signal to VCD, so that the
-- failure can be MEASURED rather than inferred from reading the source.
--
-- This bench asserts nothing. It is an observation instrument: it drives
-- clk/reset and lets the design run. The verdict is produced by parsing
-- the VCD (see sim/diag_vcd.py).
--
-- Run:
--   ghdl -a --std=08 --workdir=sim/work sim/tb_cpu_diag.vhd
--   ghdl -r --std=08 --workdir=sim/work tb_cpu_diag --vcd=sim/work/cpu.vcd \
--        --stop-time=2us --stop-delta=1000

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_cpu_diag is
end tb_cpu_diag;

architecture A_tb_cpu_diag of tb_cpu_diag is

    constant clk_period : time := 10 ns;

    signal clk   : std_logic := '0';
    signal reset : std_logic := '1';
    signal halt  : boolean   := false;

    signal alu_result              : std_logic_vector(31 downto 0);
    signal synchronization_signals : std_logic_vector(4 downto 0);
    signal src_reg                 : std_logic_vector(4 downto 0);
    signal trg_reg                 : std_logic_vector(4 downto 0);
    signal des_reg                 : std_logic_vector(4 downto 0);

begin

    DUT: entity work.Central_Processing_Unit(A_Central_Processing_Unit)
        port map(
            clk                     => clk,
            reset                   => reset,
            alu_result              => alu_result,
            synchronization_signals => synchronization_signals,
            src_reg                 => src_reg,
            trg_reg                 => trg_reg,
            des_reg                 => des_reg
        );

    clk_process : process
    begin
        while not halt loop
            clk <= '0';
            wait for clk_period / 2;
            clk <= '1';
            wait for clk_period / 2;
        end loop;
        wait;
    end process;

    stim_proc : process
    begin
        report "---------- reset asserted ----------";
        reset <= '1';
        wait for clk_period * 3;

        report "---------- reset released ----------";
        reset <= '0';

        -- The window has to be wide enough for the program to reach HALT. It
        -- now calls the software divider twice, and each division is 32 rounds
        -- of about eleven instructions at roughly 20 cycles each -- the
        -- software MUL/DIV are cheap in gates and not in time.
        wait for clk_period * 60000;

        report "---------- end of observation window ----------";
        halt <= true;
        wait;
    end process;

end A_tb_cpu_diag;

-- Made with my soul - Swately <3
