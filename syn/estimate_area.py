#!/usr/bin/env python3
"""estimate_area.py -- device-independent area estimate for the PHarvard core.

Synthesises the CPU with GHDL, maps it to 4-input LUTs with yosys, and reports
the cell counts. This exists because the vendor flow is not always available,
and because "does it fit" deserves a number rather than an opinion.

WHAT THIS IS: a technology-independent LUT4 estimate from an open-source
mapper. Use it to compare two configurations of the same design against each
other, quickly, with no vendor licence. Its output is a RANKING.

WHAT THIS IS NOT: a fitting result. **This has now been measured against the
real flow and the gap is large.** Same design, same day (see
syn/VENDOR_VS_ESTIMATE.md):

    this script          2,354 LUT4   (34% of a MachXO2-7000HE)
    Synplify + Lattice   1,092 LUT4   (16%)        <- the truth

and on the older design that still had a combinational multiplier and divider,
this script said 20,442 LUT4 where the vendor reported 2,613 plus 1,706 carry
cells -- off by roughly 8x.

The reason is structural, not a calibration constant: yosys's generic mapping
cannot use the part's hardened carry chains, and does not infer block RAM.
The error therefore SCALES with how arithmetic- and memory-heavy the design is,
so multiplying this output by a fudge factor would be worse than quoting it
raw.

For any number that will be written down or quoted, run syn/build_vendor.py
instead: it drives the actual Lattice toolchain and reports real utilisation
and post-route Fmax.

Usage:
    python syn/estimate_area.py              # both configurations
    python syn/estimate_area.py --mul-div    # only with MUL/DIV
    python syn/estimate_area.py --no-mul-div # only without

Made with my soul - Swately <3
"""
import glob
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIM = os.path.join(ROOT, "sim")
OUT = os.path.join(ROOT, "syn", "estimate")

RTL_ORDER = [
    "primitives/mem_pkg", "primitives/dff", "primitives/mux2",
    "primitives/mux2_n", "primitives/register_n", "primitives/ram_dp",
    "Full_Adder_1bit", "Full_Adder", "shifter_32", "lfsr_32", "edge_counter",
    "memory_image_pkg", "Memory_System",
    "Peripherals",
    "Arithmetic_Logic_Unit",
    "Register_File", "Program_Counter", "Control_Unit",
    "Central_Processing_Unit",
]

# Reference parts, for scale only. Add your own target here.
PARTS = [
    ("Lattice MachXO2-7000HE", 6_864),
    ("Lattice ECP5-25 (LUT4)", 24_000),
    ("Lattice ECP5-85 (LUT4)", 84_000),
]


def find_tool(name, winget_glob=None, scripts=True):
    exe = shutil.which(name)
    if exe:
        return exe
    if winget_glob:
        hits = glob.glob(os.path.join(
            os.environ.get("LOCALAPPDATA", ""), "Microsoft", "WinGet",
            "Packages", winget_glob, "bin", name + ".exe"))
        if hits:
            return hits[0]
    if scripts:
        hits = glob.glob(os.path.join(
            os.environ.get("LOCALAPPDATA", ""), "Programs", "Python",
            "Python*", "Scripts", name + "*.exe"))
        if hits:
            return hits[0]
    return None


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def synth(ghdl, work, vfile):
    for name in RTL_ORDER:
        r = run([ghdl, "-a", "--std=08", f"--workdir={work}",
                 os.path.join(ROOT, name + ".vhd")])
        if r.returncode != 0:
            print(r.stdout + r.stderr)
            return False
    r = run([ghdl, "--synth", "--std=08", f"--workdir={work}",
             "--out=verilog", "Central_Processing_Unit"])
    if r.returncode != 0:
        print("ghdl --synth failed:")
        print(r.stderr[-4000:])
        return False
    with open(vfile, "w", encoding="ascii", errors="replace") as fh:
        fh.write(r.stdout)
    return True


def area(yosys, vfile, logfile):
    script = os.path.join(OUT, "area.ys")
    with open(script, "w") as fh:
        fh.write(
            f"read_verilog {os.path.basename(vfile)}\n"
            "hierarchy -top Central_Processing_Unit\n"
            "proc\nopt\nmemory -nomap\nopt\ntechmap\nopt\n"
            "flowmap -maxlut 4\nopt\n"
            "stat -top Central_Processing_Unit\n")
    r = run([yosys, "-s", os.path.basename(script)], cwd=OUT)
    with open(logfile, "w", encoding="utf-8", errors="replace") as fh:
        fh.write(r.stdout + r.stderr)
    text = r.stdout

    # The last "Count including submodules" block is the whole-design total.
    blocks = text.split("Count including submodules")
    if len(blocks) < 2:
        return None
    tail = blocks[-1]
    def grab(pat):
        m = re.search(pat, tail)
        return int(m.group(1)) if m else 0
    luts = grab(r"(\d+)\s+\$lut")
    cells = grab(r"(\d+)\s+cells")
    ffs = sum(int(n) for n in re.findall(r"(\d+)\s+\$_DFF\w*", tail))
    mems = grab(r"(\d+)\s+\$mem")
    return dict(luts=luts, cells=cells, ffs=ffs, mems=mems)


def main():
    ghdl = find_tool("ghdl", "ghdl.ghdl*")
    if not ghdl:
        sys.exit("ghdl not found: winget install ghdl.ghdl.ucrt64.mcode")
    yosys = find_tool("yowasp-yosys") or find_tool("yosys")
    if not yosys:
        sys.exit("yosys not found: pip install yowasp-yosys")

    os.makedirs(OUT, exist_ok=True)
    work = os.path.join(SIM, "work_area")
    if os.path.isdir(work):
        shutil.rmtree(work)
    os.makedirs(work)

    vfile = os.path.join(OUT, "cpu.v")
    print("synthesising the core with GHDL...")
    if not synth(ghdl, work, vfile):
        return 1
    print(f"  verilog: {os.path.getsize(vfile):,} bytes")
    print("  mapping to LUT4 with yosys...")
    st = area(yosys, vfile, os.path.join(OUT, "area.log"))
    if st is None:
        print("  could not parse yosys statistics")
        return 1

    print("\n" + "=" * 62)
    print("LUT4 ESTIMATE (open-source mapper, NOT a vendor fitting result)")
    print("=" * 62)
    print(f"  LUT4        : {st['luts']:,}")
    print(f"  flip-flops  : {st['ffs']:,}")
    print(f"  total cells : {st['cells']:,}")

    print("\n  against reference parts:")
    for name, cap in PARTS:
        pct = 100.0 * st["luts"] / cap
        verdict = "FITS" if pct <= 100 else "DOES NOT FIT"
        print(f"    {name:<26} {cap:>7,} LUT4  -> {pct:>5.0f}%  {verdict}")

    print("\n  For scale: the combinational MUL and DIV that used to live in "
          "the ALU\n  measured 14,899 LUT4 on their own. They are software "
          "routines now.")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
