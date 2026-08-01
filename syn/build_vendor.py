#!/usr/bin/env python3
"""build_vendor.py -- the real Lattice flow, end to end, without pnmainc.

Synthesis -> EDIF -> NGO -> NGD -> map -> place&route -> timing -> JEDEC.
Produces a flashable .jed and reports the true device utilisation and the
post-route Fmax.

WHY THIS EXISTS. Diamond's normal driver is pnmainc, a TCL console that will
not run from an automation shell on this machine: it hangs with no output, as
a plain argument and on stdin, unelevated and elevated, and with a real console
allocated. Every one of those was tried. But pnmainc is only a driver -- the
tools underneath it are ordinary executables, and calling them directly works
perfectly. That is the whole trick here.

WHY IT MATTERS MORE THAN THE ESTIMATE. syn/estimate_area.py maps to LUT4 with
an open-source mapper that cannot use the part's hardened carry chains and does
not infer block RAM. Measured against this flow on the same design it came out
about 2x pessimistic, and on the older design with a hardware multiplier and
divider it was off by roughly 8x. Use this for any number that will be quoted;
use the estimate only to compare configurations against each other.

    python syn/build_vendor.py

Made with my soul - Swately <3
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "syn", "vendor")
DIAMOND = r"G:\LatticeDiamond"
ISP = os.path.join(DIAMOND, "ispfpga")
BIN = os.path.join(ISP, "bin", "nt64")

PART = "LCMXO2-7000HE"
ARCH = "MachXO2"
PKG = "TQFP144"
SPEED = "4"
NAME = "PHarvard_current"


def tool(name):
    return os.path.join(BIN, name + ".exe")


def run(cmd, cwd=OUT, timeout=1800):
    env = dict(os.environ)
    env["FOUNDRY"] = ISP.replace("\\", "/")
    return subprocess.run(cmd, cwd=cwd, env=env, capture_output=True,
                          text=True, timeout=timeout)


def step(label, cmd, produces):
    print(f"\n=== {label} ===")
    r = run(cmd)
    made = os.path.join(OUT, produces)
    if not os.path.exists(made):
        print((r.stdout + r.stderr)[-2500:])
        print(f"FAILED: {produces} was not produced")
        return False
    print(f"  ok -> {produces} ({os.path.getsize(made):,} bytes)")
    return True


# Synthesisable sources that are deliberately NOT in the build, with the
# reason. Anything else found on disk and missing from the project file is an
# error, not an omission to shrug at.
NOT_BUILT = {
    "Clock.vhd": "retired; Display derives its own sweep",
    "LCD_Controller.vhd": "no LCD connected; kept for when one is",
    "Top_Display_Test.vhd": "standalone bring-up top, built by its own project",
    "OSCH_sim.vhd": "behavioural stand-in; must never reach synthesis",
    "Top_LCD_Test.vhd": "bring-up top for the LCD that is not connected",
    "interfaz.vhd": "original project's testbench; empty entity, no ports",
}


def check_project_complete(prj):
    """Fail if a source file exists but was never added to the project.

    This is not hypothetical. power_on_reset.vhd was written, instantiated and
    committed, and the build reported byte-identical utilisation to the run
    before it -- because the file was never added here, so Synplify never saw
    it and quietly used the pre-existing entity-less design. Identical area
    after adding a 16-bit counter is impossible, which is the only reason it
    was caught. A build that silently ignores a source file is a build that
    cannot be trusted to have built what was asked for.
    """
    listed = set()
    for line in open(prj, encoding="utf-8"):
        m = re.search(r"add_file[^{]*\{([^}]+)\}", line)
        if m:
            listed.add(os.path.basename(m.group(1)))

    missing = []
    for sub in ("", "primitives"):
        d = os.path.join(ROOT, sub)
        for f in sorted(os.listdir(d)):
            if not f.endswith(".vhd"):
                continue
            if f.startswith("tb_") or f.endswith("_tb.vhd"):
                continue
            if f in listed or f in NOT_BUILT:
                continue
            missing.append(os.path.join(sub, f) if sub else f)

    if missing:
        print("\nSOURCE FILES NOT IN THE SYNTHESIS PROJECT:")
        for f in missing:
            print(f"    {f}")
        print(f"\nAdd them to {os.path.relpath(prj, ROOT)}, or list them in")
        print("NOT_BUILT with the reason they are excluded.")
        sys.exit("refusing to build an incomplete design")


def main():
    os.makedirs(OUT, exist_ok=True)
    if not os.path.exists(tool("map")):
        sys.exit(f"Diamond backend not found under {BIN}")
    check_project_complete(os.path.join(ROOT, "syn", "synplify_current.tcl"))

    # 1. Synthesis. synpwrap runs Synplify directly; the project file lists the
    #    current sources and sets VHDL-2008, which the design needs.
    print("=== SYNTHESIS (synpwrap -> Synplify) ===")
    r = run([os.path.join(DIAMOND, "bin", "nt64", "synpwrap.exe"),
             "-prj", os.path.join(ROOT, "syn", "synplify_current.tcl")],
            cwd=ROOT)
    edi = os.path.join(OUT, NAME + ".edi")
    if not os.path.exists(edi):
        print((r.stdout + r.stderr)[-2500:])
        sys.exit("synthesis produced no EDIF")
    print(f"  ok -> {NAME}.edi ({os.path.getsize(edi):,} bytes)")

    # The constraints the design is built against.
    lpf_src = os.path.join(ROOT, "syn", "PHarvard.lpf")
    lpf_dst = os.path.join(OUT, NAME + ".lpf")
    if os.path.exists(lpf_src):
        with open(lpf_src) as a, open(lpf_dst, "w") as b:
            b.write(a.read())

    ok = (
        step("EDIF -> NGO",
             [tool("edif2ngd"), "-l", ARCH, "-d", PART,
              NAME + ".edi", NAME + ".ngo"], NAME + ".ngo")
        and step("NGO -> NGD",
                 [tool("ngdbuild"), "-a", ARCH, "-d", PART,
                  "-p", os.path.join(ISP, ARCH.lower(), "data"),
                  NAME + ".ngo", NAME + ".ngd"], NAME + ".ngd")
        and step("MAP",
                 [tool("map"), "-a", ARCH, "-p", PART, "-t", PKG, "-s", SPEED,
                  NAME + ".ngd", "-pr", NAME + ".prf",
                  "-o", NAME + "_map.ncd", NAME + ".lpf"], NAME + "_map.mrp")
        and step("PLACE & ROUTE",
                 [tool("par"), "-w", "-l", "5", "-n", "1", "-s", "1",
                  NAME + "_map.ncd", NAME + ".ncd", NAME + ".prf"],
                 NAME + ".ncd")
        and step("TIMING (trce)",
                 [tool("trce"), "-v", "1", "-o", NAME + ".twr",
                  NAME + ".ncd", NAME + ".prf"], NAME + ".twr")
        and step("BITGEN -> JEDEC",
                 [tool("bitgen"), "-w", "-jedec",
                  NAME + ".ncd", NAME + ".jed", NAME + ".prf"], NAME + ".jed")
    )
    if not ok:
        return 1

    # ---- report the numbers that matter --------------------------------
    print("\n" + "=" * 64)
    print("DEVICE UTILISATION -- vendor map report, the real thing")
    print("=" * 64)
    mrp = open(os.path.join(OUT, NAME + "_map.mrp"),
               encoding="utf-8", errors="replace").read()
    for pat in (r"Number of registers:.*", r"Number of SLICEs:.*",
                r"Number of LUT4s:.*", r"Number of block RAMs:.*",
                r"Number of PIO sites used:.*"):
        m = re.search(pat, mrp)
        if m:
            print("  " + m.group(0).strip())

    twr = open(os.path.join(OUT, NAME + ".twr"),
               encoding="utf-8", errors="replace").read()
    m = re.search(r"Report:\s+([\d.]+MHz) is the maximum frequency", twr)
    if m:
        print(f"\n  post-route Fmax : {m.group(1)}")
    m = re.search(r"Timing errors: (\d+)\s+Score: (\d+)", twr)
    if m:
        print(f"  timing errors   : {m.group(1)}  (score {m.group(2)})")

    print(f"\n  flashable image : syn/vendor/{NAME}.jed")
    print("\n  To flash (the cable is the FT2232H already on this machine):")
    print(r"    G:\LatticeDiamond\bin\nt64\pgrcmd.exe -infile <project>.xcf"
          r" -cabletype USB2 -portaddress FTUSB-0")
    print("\n  Check the pin assignments in syn/PHarvard.lpf against the board")
    print("  before flashing: several are transcribed from photographs and")
    print("  have never been exercised.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
