#!/usr/bin/env python3
"""run_diag.py -- one command that reproduces the whole PHarvard diagnosis.

Analyses every RTL file with GHDL, elaborates and runs the observation-only
bench, then prints the static control-table decode and the measured
instruction-level trace.

Usage:
    python sim/run_diag.py            # full diagnosis
    python sim/run_diag.py --analyze  # stop after the analyse pass

Made with my soul - Swately <3
"""
import glob
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIM = os.path.join(ROOT, "sim")
WORK = os.path.join(SIM, "work")

# Dependency order: an entity must be analysed before anything that
# instantiates it directly with `entity work.X`. Layer 0 first, then the
# blocks built from it, then the machine.
RTL_ORDER = [
    # layer 0 -- the irreducible primitives (see primitives/PRIMITIVES.md)
    "primitives/mem_pkg", "primitives/dff", "primitives/mux2",
    "primitives/mux2_n", "primitives/register_n", "primitives/ram_dp",
    "primitives/power_on_reset",
    # layer 1-2 -- combinational blocks built from layer 0
    "Full_Adder_1bit", "Full_Adder", "shifter_32", "lfsr_32", "edge_counter",
    # the memory image, then the modified-Harvard memory system
    "memory_image_pkg", "Memory_System",
    # peripherals, reached by ordinary LOAD/STORE
    "Peripherals",
    # layer 3+ -- the machine
    "Arithmetic_Logic_Unit",
    "Register_File", "Program_Counter", "Control_Unit",
    "Central_Processing_Unit", "Display", "Top_Level_Unit",
    "interfaz",
]


def check_rtl_order_complete():
    """Fail if a source file on disk is not in RTL_ORDER.

    Kept honest by the same failure that hit syn/build_vendor.py:
    power_on_reset.vhd was written and instantiated but missing from both
    hand-maintained file lists. There the build silently produced a bitstream
    of the PREVIOUS design; here at least the analysis broke loudly. A list
    maintained by hand drifts from the tree it describes, so it is checked
    against the tree.
    """
    listed = {n + ".vhd" for n in RTL_ORDER}
    # Tops and stand-ins that are built by their own projects, with the reason.
    skip = {
        "Clock.vhd", "LCD_Controller.vhd", "Top_Display_Test.vhd",
        "Top_LCD_Test.vhd", "OSCH_sim.vhd", "Board_MachXO2.vhd",
    }
    missing = []
    for sub in ("", "primitives"):
        d = os.path.join(ROOT, sub) if sub else ROOT
        for f in sorted(os.listdir(d)):
            if not f.endswith(".vhd") or f.startswith("tb_") or f.endswith("_tb.vhd"):
                continue
            key = f"{sub}/{f}" if sub else f
            if key in listed or f in listed or f in skip:
                continue
            missing.append(key)
    if missing:
        print("SOURCE FILES NOT IN RTL_ORDER: " + ", ".join(missing))
        sys.exit("refusing to report on an incomplete design")


def find_ghdl():
    """GHDL installed by winget is not on PATH until the shell restarts."""
    from shutil import which
    exe = which("ghdl")
    if exe:
        return exe
    pat = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Microsoft",
                       "WinGet", "Packages", "ghdl.ghdl*", "bin", "ghdl.exe")
    hits = glob.glob(pat)
    if hits:
        return hits[0]
    sys.exit("ghdl not found. Install with: "
             "winget install ghdl.ghdl.ucrt64.mcode")


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def main():
    ghdl = find_ghdl()
    os.makedirs(WORK, exist_ok=True)
    print(f"GHDL: {ghdl}")
    print(run([ghdl, "--version"]).stdout.splitlines()[0])

    # memory_image_pkg.vhd is GENERATED from the assembly source. Rebuilding it
    # here means the image can never silently lag behind sw/demo.s -- editing
    # the program and forgetting to assemble would otherwise verify the old
    # binary and report a pass.
    src = os.path.join(ROOT, "sw", "demo.s")
    if os.path.exists(src):
        print("\n=== ASSEMBLE ===")
        r = run([sys.executable, os.path.join(ROOT, "tools", "pasm.py"), src,
                 "-o", os.path.join(ROOT, "memory_image_pkg.vhd")])
        print((r.stdout + r.stderr).strip())
        if r.returncode != 0:
            return 1

    print("\n=== ANALYSE ===")
    failures = 0
    check_rtl_order_complete()

    for name in RTL_ORDER:
        src = os.path.join(ROOT, name + ".vhd")
        if not os.path.exists(src):
            print(f"SKIP  {name} (missing)")
            continue
        r = run([ghdl, "-a", "--std=08", f"--workdir={WORK}", src])
        if r.returncode == 0:
            print(f"OK    {name}")
        else:
            failures += 1
            print(f"FAIL  {name}\n{r.stdout}{r.stderr}")
    print(f"\nanalysed: {len(RTL_ORDER)}   failures: {failures}")
    if failures or "--analyze" in sys.argv:
        return 1 if failures else 0

    # Synthesis gate. Simulation cannot see an inferred latch: the VHDL
    # simulator happily holds the value, and only a synthesiser objects. Every
    # decoded field in the control unit and all three address registers were
    # latches that passed the full behavioural regression. This gate is why
    # that cannot happen again.
    print("\n=== SYNTHESIS GATE (latch / portability check) ===")
    r = run([ghdl, "--synth", "--std=08", f"--workdir={WORK}",
             "--out=verilog", "Top_Level_Unit"])
    diags = sorted({ln for ln in (r.stdout + r.stderr).splitlines()
                    if "error:" in ln or "warning:" in ln})
    errors = [d for d in diags if "error:" in d]
    for d in diags:
        print("  " + d.strip())
    if r.returncode != 0 or errors:
        print(f"  FAIL: {len(errors)} synthesis error(s) -- the design would "
              f"not build, whatever simulation says")
        return 1
    print(f"  PASS: Top_Level_Unit synthesises clean "
          f"({len(diags)} benign warning(s))")

    print("\n=== STATIC CONTROL-TABLE DECODE ===")
    r = run([sys.executable, os.path.join(SIM, "decode_ctrl.py")])
    print(r.stdout + r.stderr)

    print("=== SIMULATE (observation bench) ===")
    tb = os.path.join(SIM, "tb_cpu_diag.vhd")
    for step in (["-a", "--std=08", f"--workdir={WORK}", tb],
                 ["-e", "--std=08", f"--workdir={WORK}", "tb_cpu_diag"]):
        r = run([ghdl] + step)
        if r.returncode != 0:
            print(r.stdout + r.stderr)
            return 1
    vcd = os.path.join(WORK, "cpu.vcd")
    r = run([ghdl, "-r", "--std=08", f"--workdir={WORK}", "tb_cpu_diag",
             f"--vcd={vcd}", "--stop-time=700us", "--stop-delta=1000"])
    print(r.stdout[-2000:] + r.stderr[-2000:])

    print("=== MEASURED TRACE ===")
    r = run([sys.executable, os.path.join(SIM, "diag_vcd.py"), vcd])
    print(r.stdout + r.stderr)

    print("=== SELF-CHECK vs GOLDEN MODEL ===")
    r = run([sys.executable, os.path.join(SIM, "check_cpu.py"), vcd])
    print(r.stdout + r.stderr)
    return r.returncode


if __name__ == "__main__":
    sys.exit(main())
