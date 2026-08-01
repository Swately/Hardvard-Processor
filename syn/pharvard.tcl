# pharvard.tcl -- build the Lattice Diamond project for PHarvard.
#
# Produces syn/work_pharvard/PHarvard.ldf, which is the project file to open in
# the Diamond IDE. Letting Diamond create the project is deliberate: a
# hand-written .ldf drifts from whatever schema the installed version expects,
# while this always matches.
#
# RUN IT WITH AN ABSOLUTE PATH -- the script self-locates, so the working
# directory does not matter:
#
#   G:\LatticeDiamond\bin\nt64\pnmainc.exe G:\phyriad\projects\PHarvard\syn\pharvard.tcl
#
# Reports land in syn/work_pharvard/impl1/ :
#   *.mrp  -> "Number of LUT4s: X out of Y"   (area)
#   *.twr  -> timing / Fmax
#
# NOTE on the .lpf (lesson carried over from the Holith bring-up on this same
# board): a second .lpf added with `prj_src add` is auto-DISABLED by Diamond and
# the pins then silently auto-place somewhere else. The constraints must land in
# the ACTIVE project .lpf, which is what the copy below does.
#
# This script has NOT been executed end to end: Diamond's pnmainc would not run
# from the session that wrote it (hangs with no output). It reports every step
# and stops on the first real failure rather than pressing on quietly.
#
# Made with my soul - Swately <3

set script_dir [file dirname [file normalize [info script]]]
set root       [file dirname $script_dir]
set work       [file join $script_dir work_pharvard]

set PART "LCMXO2-7000HE-4TG144C"
# Board_MachXO2 is the top on this part: it adds the OSCH oscillator and hands
# the clock to the portable Top_Level_Unit, which has a clk_in port and no
# vendor primitive of its own.
set TOP  "Board_MachXO2"

# Dependency order matters for VHDL elaboration.
# Layer order: primitives, then the blocks built from them, then the machine.
# See primitives/PRIMITIVES.md for what the layers are and where the hierarchy
# deliberately stops.
set SOURCES {
    primitives/dff.vhd
    primitives/mux2.vhd
    primitives/mux2_n.vhd
    primitives/register_n.vhd
    Full_Adder_1bit.vhd
    Full_Adder.vhd
    shifter_32.vhd
    Arithmetic_Logic_Unit.vhd
    Register_File.vhd
    Program_Counter.vhd
    Instruction_Memory.vhd
    Instruction_Memory_Address_Register.vhd
    Data_Memory.vhd
    Data_Memory_Address_Register.vhd
    Control_Unit.vhd
    Central_Processing_Unit.vhd
    Clock.vhd
    Display.vhd
    Top_Level_Unit.vhd
    Board_MachXO2.vhd
}

proc fail {msg} {
    puts "=========================================================="
    puts "FAILED: $msg"
    puts "=========================================================="
    exit 1
}

puts "INFO: script  = [info script]"
puts "INFO: sources = $root"
puts "INFO: work    = $work"

foreach f $SOURCES {
    if {![file exists [file join $root $f]]} {
        fail "missing source [file join $root $f]"
    }
}
if {![file exists [file join $script_dir PHarvard.lpf]]} {
    fail "missing [file join $script_dir PHarvard.lpf]"
}

file mkdir $work
cd $work

set ldf [file join $work PHarvard.ldf]
if {[file exists $ldf]} {
    puts "INFO: opening existing project $ldf"
    if {[catch {prj_project open $ldf} err]} { fail "prj_project open: $err" }
} else {
    puts "INFO: creating project for $PART"
    if {[catch {prj_project new -name "PHarvard" -impl "impl1" \
                    -dev $PART -synthesis "synplify"} err]} {
        fail "prj_project new: $err"
    }
}

# Add the sources. On a re-run Diamond reports that a file is already in the
# project; that message is expected and not fatal, so it is printed rather than
# swallowed -- an add that fails for any OTHER reason would otherwise leave the
# project empty and the failure would only surface much later as an
# unresolvable top level.
set added 0
foreach f $SOURCES {
    set path [file join $root $f]
    if {[catch {prj_src add $path} err]} {
        puts "NOTE: prj_src add $f -> $err"
    } else {
        incr added
    }
}
puts "INFO: $added of [llength $SOURCES] sources added this run"

if {[catch {prj_impl option top $TOP} err]} { fail "prj_impl option top: $err" }
if {[catch {prj_project save} err]}         { fail "prj_project save: $err" }

# ---------------------------------------------------------------- constraints
# Find the .lpf Diamond actually made rather than assuming where it put it;
# the location has moved between Diamond versions.
set found [glob -nocomplain [file join $work impl1 *.lpf]]
if {[llength $found] == 0} {
    set found [glob -nocomplain [file join $work *.lpf]]
}
if {[llength $found] == 0} {
    # No project .lpf exists: create ours at the expected place and register it.
    set active_lpf [file join $work impl1 PHarvard.lpf]
    file mkdir [file join $work impl1]
    file copy -force [file join $script_dir PHarvard.lpf] $active_lpf
    if {[catch {prj_src add $active_lpf} err]} {
        puts "NOTE: prj_src add lpf -> $err"
    }
    puts "INFO: created and registered $active_lpf"
} else {
    set active_lpf [lindex $found 0]
    file copy -force [file join $script_dir PHarvard.lpf] $active_lpf
    puts "INFO: constraints written into the active [file tail $active_lpf]"
    if {[llength $found] > 1} {
        puts "WARN: more than one .lpf present: $found"
        puts "WARN: only [file tail $active_lpf] was written; the others are"
        puts "WARN: probably auto-disabled and would place pins silently."
    }
}

if {[catch {prj_project save} err]} { fail "prj_project save (2): $err" }

# ------------------------------------------------------------------- the flow
puts "INFO: === synthesis ==="
if {[catch {prj_run Synthesis -impl impl1 -forceOne} err]} {
    fail "Synthesis: $err"
}
puts "INFO: === map ==="
if {[catch {prj_run Map -impl impl1 -forceOne} err]} { fail "Map: $err" }
puts "INFO: === place and route ==="
if {[catch {prj_run PAR -impl impl1 -forceOne} err]} { fail "PAR: $err" }

puts "INFO: === JEDEC (MachXO2 flash image) ==="
if {[catch {prj_run Export -impl impl1 -task Jedecgen -forceOne} err]} {
    puts "NOTE: Jedecgen: $err  (area and timing reports are still valid)"
}

catch {prj_project save}
catch {prj_project close}

puts ""
puts "=========================================================="
puts "DONE. Open this in the Diamond IDE:"
puts "  $ldf"
puts ""
puts "Area  -> [file join $work impl1]\\*.mrp   (\"Number of LUT4s\")"
puts "Timing-> [file join $work impl1]\\*.twr"
puts "=========================================================="
