#!/usr/bin/env python3
"""area_module.py -- LUT4/FF estimate for ONE module, in isolation.

The whole-core figure from estimate_area.py cannot answer "what does this block
cost", which is exactly the question that decides whether a block is worth
keeping. This synthesises a single entity and reports it alone.

    python syn/area_module.py LCD_Controller
    python syn/area_module.py lfsr_32 Display shifter_32

Same caveat as estimate_area.py: an open-source LUT4 mapping, not a vendor
fitting result. Good for comparing blocks against each other, which is what it
is for.

Made with my soul - Swately <3
"""
import glob
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "syn", "estimate")

# Everything a module might depend on, in dependency order.
DEPS = [
    "primitives/mem_pkg", "primitives/dff", "primitives/mux2",
    "primitives/mux2_n", "primitives/register_n", "primitives/ram_dp",
    "Full_Adder_1bit", "Full_Adder", "shifter_32", "lfsr_32",
    "memory_image_pkg", "Memory_System", "LCD_Controller", "Peripherals",
    "Arithmetic_Logic_Unit", "Register_File", "Program_Counter",
    "Control_Unit", "Central_Processing_Unit", "Clock", "Display",
]


def find(name, pat=None):
    exe = shutil.which(name)
    if exe:
        return exe
    for base in (("Microsoft", "WinGet", "Packages", pat or name + "*", "bin"),):
        hits = glob.glob(os.path.join(os.environ.get("LOCALAPPDATA", ""),
                                      *base, name + ".exe"))
        if hits:
            return hits[0]
    hits = glob.glob(os.path.join(os.environ.get("LOCALAPPDATA", ""),
                                  "Programs", "Python", "Python*", "Scripts",
                                  name + "*.exe"))
    return hits[0] if hits else None


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def measure(ghdl, yosys, top, work):
    if os.path.isdir(work):
        shutil.rmtree(work)
    os.makedirs(work)
    for name in DEPS:
        src = os.path.join(ROOT, name + ".vhd")
        if os.path.exists(src):
            run([ghdl, "-a", "--std=08", f"--workdir={work}", src])

    r = run([ghdl, "--synth", "--std=08", f"--workdir={work}",
             "--out=verilog", top])
    if r.returncode != 0:
        return None, r.stderr[-800:]

    vf = os.path.join(OUT, f"mod_{top}.v")
    with open(vf, "w", encoding="ascii", errors="replace") as fh:
        fh.write(r.stdout)

    ys = os.path.join(OUT, f"mod_{top}.ys")
    with open(ys, "w") as fh:
        fh.write(f"read_verilog {os.path.basename(vf)}\n"
                 f"hierarchy -top {top}\nproc\nopt\nmemory -nomap\nopt\n"
                 f"techmap\nopt\nflowmap -maxlut 4\nopt\nstat -top {top}\n")
    r = run([yosys, "-s", os.path.basename(ys)], cwd=OUT)
    text = r.stdout
    # A module with submodules gets an "including submodules" roll-up; a LEAF
    # module never does, and looking only for the roll-up reported every leaf
    # as a failure. Fall back to the local count, which for a leaf IS the total.
    if "Count including submodules" in text:
        tail = text.split("Count including submodules")[-1]
    elif "Local Count, excluding submodules" in text:
        tail = text.split("Local Count, excluding submodules")[-1]
    else:
        return None, "yosys statistics not found"

    def grab(p):
        m = re.search(p, tail)
        return int(m.group(1)) if m else 0

    return dict(
        luts=grab(r"(\d+)\s+\$lut"),
        ffs=sum(int(n) for n in re.findall(r"(\d+)\s+\$_DFF\w*", tail)),
        cells=grab(r"(\d+)\s+cells"),
    ), None


def main():
    tops = sys.argv[1:]
    if not tops:
        sys.exit(__doc__)
    ghdl = find("ghdl", "ghdl.ghdl*")
    yosys = find("yowasp-yosys") or find("yosys")
    if not ghdl or not yosys:
        sys.exit("need ghdl and yosys")
    os.makedirs(OUT, exist_ok=True)

    print(f"{'module':<26} {'LUT4':>8} {'FF':>7} {'cells':>8}")
    print("-" * 53)
    for top in tops:
        st, err = measure(ghdl, yosys, top,
                          os.path.join(ROOT, "sim", "work_mod"))
        if st is None:
            print(f"{top:<26} FAILED: {err.strip()[:60]}")
        else:
            print(f"{top:<26} {st['luts']:>8,} {st['ffs']:>7,} "
                  f"{st['cells']:>8,}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
