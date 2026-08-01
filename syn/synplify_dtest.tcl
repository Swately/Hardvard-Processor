#-- Synplify project for the CURRENT PHarvard design.
#--
#-- Diamond normally generates this and drives it through pnmainc, which will
#-- not run from an automation shell here (it hangs with no output, even
#-- elevated, even with a console allocated). synpwrap runs Synplify directly
#-- and skips that layer entirely, which is what makes a VENDOR area figure
#-- reachable at all from this side.
#--
#-- Why a vendor figure matters: the open-source estimate in
#-- syn/estimate_area.py cannot use the part's hardened carry chains or infer
#-- distributed RAM, and measured against Synplify's own report on the same
#-- design it came out roughly 3x pessimistic. See syn/VENDOR_VS_ESTIMATE.md.
#--
#-- Run:
#--   G:\LatticeDiamond\bin\nt64\synpwrap.exe -prj syn\synplify_current.tcl
#--
#-- Made with my soul - Swately <3

#device options
set_option -technology MACHXO2
set_option -part LCMXO2_7000HE
set_option -package TG144C
set_option -speed_grade -4

#compilation/mapping options
set_option -symbolic_fsm_compiler true
set_option -resource_sharing true
set_option -vlog_std v2001

#-- The design uses VHDL-2008: unary reduction operators, `else generate`, and
#-- unconstrained array generics for the memory images. Without this the
#-- primitives will not compile.
set_option -vhdl2008 1

#map options
set_option -frequency 100
set_option -maxfan 1000
set_option -auto_constrain_io 0
set_option -disable_io_insertion false
set_option -retiming false
set_option -pipe true
set_option -force_gsr false
set_option -compiler_compatible 0
set_option -dup false
set_option -default_enum_encoding default

set_option -write_apr_constraint 1
set_option -fix_gated_and_generated_clocks 1
set_option -update_models_cp 0
set_option -resolve_multiple_driver 0
set_option -seqshift_no_replicate 0

#-- Lattice primitive library, for OSCH.
add_file -vhdl {G:/LatticeDiamond/cae_library/synthesis/vhdl/machxo2.vhd}
add_file -vhdl -lib "work" {G:/Phyriad/projects/PHarvard/Display.vhd}
add_file -vhdl -lib "work" {G:/Phyriad/projects/PHarvard/Top_Display_Test.vhd}

set_option -top_module Top_Display_Test

project -result_file {G:/Phyriad/projects/PHarvard/syn/dtest/dtest.edi}
project -log_file {dtest.srf}
project -run hdl_info_gen -fileorder
project -run -clean
