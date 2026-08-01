#!/usr/bin/env python3
"""run_slots.py -- assemble and play the slot machine in simulation.

Builds sw/slots.s into its own memory image and its own GHDL work library, so
it does not disturb the demo program that the golden-model regression checks.
Prints the 16x2 screen the processor actually drove.

    python sim/run_slots.py

Made with my soul - Swately <3
"""
import glob
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIM = os.path.join(ROOT, "sim")
WORK = os.path.join(SIM, "work_slots")

RTL = [
    "primitives/mem_pkg", "primitives/dff", "primitives/mux2",
    "primitives/mux2_n", "primitives/register_n", "primitives/ram_dp",
    "Full_Adder_1bit", "Full_Adder", "shifter_32", "lfsr_32", "edge_counter",
    "Memory_System", "Peripherals",
    "Arithmetic_Logic_Unit", "Register_File", "Program_Counter",
    "Control_Unit", "Central_Processing_Unit", "Display",
    "Top_Level_Unit",
]


def find_ghdl():
    exe = shutil.which("ghdl")
    if exe:
        return exe
    hits = glob.glob(os.path.join(
        os.environ.get("LOCALAPPDATA", ""), "Microsoft", "WinGet", "Packages",
        "ghdl.ghdl*", "bin", "ghdl.exe"))
    if hits:
        return hits[0]
    sys.exit("ghdl not found")


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def main():
    ghdl = find_ghdl()
    os.makedirs(WORK, exist_ok=True)
    for f in glob.glob(os.path.join(WORK, "*")):
        os.remove(f)

    print("=== ASSEMBLE ===")
    image = os.path.join(WORK, "memory_image_pkg.vhd")
    r = run([sys.executable, os.path.join(ROOT, "tools", "pasm.py"),
             os.path.join(ROOT, "sw", "slots.s"), "-o", image])
    print((r.stdout + r.stderr).strip())
    if r.returncode != 0:
        return 1

    print("\n=== ANALYSE ===")
    # The generated image goes in before anything that uses it.
    files = ([os.path.join(ROOT, "primitives", "mem_pkg.vhd")]
             + [image]
             + [os.path.join(ROOT, n + ".vhd") for n in RTL
                if n != "primitives/mem_pkg"]
             + [os.path.join(SIM, "tb_slots.vhd")])
    for f in files:
        r = run([ghdl, "-a", "--std=08", f"--workdir={WORK}", f])
        if r.returncode != 0:
            print(f"FAIL {os.path.basename(f)}\n{r.stdout}{r.stderr}")
            return 1
    print(f"OK -- {len(files)} files")

    print("\n=== ELABORATE ===")
    r = run([ghdl, "-e", "--std=08", f"--workdir={WORK}", "tb_slots"])
    if r.returncode != 0:
        print(r.stdout + r.stderr)
        return 1
    print("OK")

    print("\n=== PLAY ===")
    r = run([ghdl, "-r", "--std=08", f"--workdir={WORK}", "tb_slots",
             "--stop-time=1500ms", "--stop-delta=2000"])
    out = r.stdout + r.stderr
    for line in out.splitlines():
        if "(report note):" in line:
            print(line.split("(report note):", 1)[1])
        elif line.strip() and "(report" not in line:
            print(line)
        elif "(report error):" in line:
            print(line.split("(report error):", 1)[1])

    return 0 if "RESULT: PASS" in out else 1


if __name__ == "__main__":
    sys.exit(main())
