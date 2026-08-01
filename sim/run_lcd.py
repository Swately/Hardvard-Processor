#!/usr/bin/env python3
"""run_lcd.py -- build and run the self-checking LCD bench.

Simulates Top_LCD_Test whole (oscillator included, via the behavioural OSCH
model) against a behavioural HD44780 that reconstructs the 16x2 screen, and
exits non-zero if the rendered screen is not the expected one.

Usage:
    python sim/run_lcd.py

Made with my soul - Swately <3
"""
import glob
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIM = os.path.join(ROOT, "sim")
WORK = os.path.join(SIM, "work")

# OSCH_sim.vhd must come first: Top_LCD_Test binds the OSCH component to it.
FILES = [
    os.path.join(SIM, "OSCH_sim.vhd"),
    os.path.join(ROOT, "LCD_Controller.vhd"),
    os.path.join(ROOT, "Top_LCD_Test.vhd"),
    os.path.join(SIM, "tb_lcd.vhd"),
]


def find_ghdl():
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


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def main():
    ghdl = find_ghdl()
    os.makedirs(WORK, exist_ok=True)
    print(f"GHDL: {ghdl}\n")

    print("=== ANALYSE ===")
    for f in FILES:
        r = run([ghdl, "-a", "--std=08", f"--workdir={WORK}", f])
        if r.returncode != 0:
            print(f"FAIL  {os.path.basename(f)}\n{r.stdout}{r.stderr}")
            return 1
        print(f"OK    {os.path.basename(f)}")

    print("\n=== ELABORATE ===")
    r = run([ghdl, "-e", "--std=08", f"--workdir={WORK}", "tb_lcd"])
    if r.returncode != 0:
        print(r.stdout + r.stderr)
        return 1
    print("OK")

    # The HD44780 power-on wait alone is 15 ms, so the bench needs tens of
    # milliseconds of modelled time.
    print("\n=== RUN ===")
    r = run([ghdl, "-r", "--std=08", f"--workdir={WORK}", "tb_lcd",
             "--stop-time=40ms"])
    out = r.stdout + r.stderr
    # Strip GHDL's file:line:time prefix so the rendered screen lines up.
    for line in out.splitlines():
        if "(report note):" in line:
            print(line.split("(report note):", 1)[1])
        elif line.strip():
            print(line)

    if "RESULT: PASS" in out and r.returncode == 0:
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
