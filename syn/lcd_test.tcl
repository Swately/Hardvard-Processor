# lcd_test.tcl -- build the LCD bring-up bitstream (no CPU).
#
# Produces syn/work_lcd_test/LCD_Test.ldf plus a .jed to flash. Its only job is
# to confirm the LCD wiring and the pin numbers in lcd_test.lpf, which are
# transcribed from the Holith board notes and marked there as unconfirmed.
#
# RUN WITH AN ABSOLUTE PATH -- the script self-locates:
#
#   G:\LatticeDiamond\bin\nt64\pnmainc.exe G:\phyriad\projects\PHarvard\syn\lcd_test.tcl
#
# Then flash the .jed the same way the Holith bring-up did:
#
#   pgrcmd -infile <project>.xcf -cabletype USB2 -portaddress FTUSB-0
#
# MachXO2 flash needs the .jed, which comes from the Jedecgen task -- Bitgen
# alone produces only a .bit and there is nothing to program with it.
#
# Made with my soul - Swately <3

set script_dir [file dirname [file normalize [info script]]]
set root       [file dirname $script_dir]
set work       [file join $script_dir work_lcd_test]

set PART "LCMXO2-7000HE-4TG144C"
set TOP  "Top_LCD_Test"

# OSCH is a Lattice primitive supplied by Diamond. sim/OSCH_sim.vhd is the
# simulation stand-in and must NOT be added here, or it would shadow the real
# one and synthesise a toggling signal with no oscillator behind it.
set SOURCES {
    LCD_Controller.vhd
    Top_LCD_Test.vhd
}

proc fail {msg} {
    puts "=========================================================="
    puts "FAILED: $msg"
    puts "=========================================================="
    exit 1
}

puts "INFO: sources = $root"
puts "INFO: work    = $work"

foreach f $SOURCES {
    if {![file exists [file join $root $f]]} {
        fail "missing source [file join $root $f]"
    }
}
if {![file exists [file join $script_dir lcd_test.lpf]]} {
    fail "missing [file join $script_dir lcd_test.lpf]"
}

file mkdir $work
cd $work

set ldf [file join $work LCD_Test.ldf]
if {[file exists $ldf]} {
    puts "INFO: opening existing project"
    if {[catch {prj_project open $ldf} err]} { fail "prj_project open: $err" }
} else {
    puts "INFO: creating project for $PART"
    if {[catch {prj_project new -name "LCD_Test" -impl "impl1" \
                    -dev $PART -synthesis "synplify"} err]} {
        fail "prj_project new: $err"
    }
}

set added 0
foreach f $SOURCES {
    if {[catch {prj_src add [file join $root $f]} err]} {
        puts "NOTE: prj_src add $f -> $err"
    } else {
        incr added
    }
}
puts "INFO: $added of [llength $SOURCES] sources added this run"

if {[catch {prj_impl option top $TOP} err]} { fail "prj_impl option top: $err" }
if {[catch {prj_project save} err]}         { fail "prj_project save: $err" }

# Write the constraints into the ACTIVE .lpf. A second .lpf added as a source
# gets auto-disabled by Diamond and the pins then place themselves silently --
# that is how the Holith blinky ended up on pin 89 instead of 55.
set found [glob -nocomplain [file join $work impl1 *.lpf]]
if {[llength $found] == 0} {
    set found [glob -nocomplain [file join $work *.lpf]]
}
if {[llength $found] == 0} {
    set active_lpf [file join $work impl1 LCD_Test.lpf]
    file mkdir [file join $work impl1]
    file copy -force [file join $script_dir lcd_test.lpf] $active_lpf
    if {[catch {prj_src add $active_lpf} err]} {
        puts "NOTE: prj_src add lpf -> $err"
    }
    puts "INFO: created and registered $active_lpf"
} else {
    set active_lpf [lindex $found 0]
    file copy -force [file join $script_dir lcd_test.lpf] $active_lpf
    puts "INFO: constraints written into [file tail $active_lpf]"
}

if {[catch {prj_project save} err]} { fail "prj_project save (2): $err" }

puts "INFO: === synthesis ==="
if {[catch {prj_run Synthesis -impl impl1 -forceOne} err]} { fail "Synthesis: $err" }
puts "INFO: === map ==="
if {[catch {prj_run Map -impl impl1 -forceOne} err]}       { fail "Map: $err" }
puts "INFO: === place and route ==="
if {[catch {prj_run PAR -impl impl1 -forceOne} err]}       { fail "PAR: $err" }
puts "INFO: === JEDEC ==="
if {[catch {prj_run Export -impl impl1 -task Jedecgen -forceOne} err]} {
    fail "Jedecgen: $err  (needed to flash a MachXO2)"
}

catch {prj_project save}
catch {prj_project close}

puts ""
puts "=========================================================="
puts "DONE. Flash the .jed in [file join $work impl1]"
puts ""
puts "Expected on the display:"
puts "  +----------------+"
puts "  |PHARVARD LCD OK |"
puts "  |0123456789ABCDEF|"
puts "  +----------------+"
puts ""
puts "LED on pin 55 blinks ~1 Hz whatever the LCD does."
puts "=========================================================="
