# One-command project + block-design builder for Vivado 2020.2.
# Usage from project root:
#   vivado -mode batch -source scripts/build_ebaz4205_system.tcl
# Optional environment:
#   EBAZ_BOARD_PART=<vendor:board:name:version>
#   EBAZ_BOARD_REPO=<path containing board_files/>
#   RUN_SYNTH=1
#   RUN_IMPL=1

set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]
set proj_dir   [file join $root_dir vivado_ebaz4205]
set part_name  "xc7z010clg400-1"
# Low-RAM safe default for Sam's 4 GiB laptop. Override explicitly only on a
# machine with enough memory: VIVADO_JOBS=2 (or higher).
set_param general.maxThreads 1
set vivado_jobs 1
if {[info exists ::env(VIVADO_JOBS)] && [string is integer -strict $::env(VIVADO_JOBS)] && $::env(VIVADO_JOBS) > 0} {
    set vivado_jobs $::env(VIVADO_JOBS)
}
puts "INFO: Vivado parallel jobs = $vivado_jobs"


# Load project-local board files without modifying the Vivado installation.
set board_repo ""
if {[info exists ::env(EBAZ_BOARD_REPO)] && $::env(EBAZ_BOARD_REPO) ne ""} {
    set board_repo [file normalize $::env(EBAZ_BOARD_REPO)]
} else {
    set local_repo [file join $root_dir third_party EBAZ4205_BoardSupport board_files]
    if {[file isdirectory $local_repo]} { set board_repo $local_repo }
}
if {$board_repo ne ""} {
    if {![file isdirectory $board_repo]} { error "EBAZ_BOARD_REPO does not exist: $board_repo" }
    puts "INFO: adding board repository: $board_repo"
    set_param board.repoPaths [list $board_repo]
}

create_project Sam_NPU_EBAZ4205 $proj_dir -part $part_name -force

# If board files are installed/loaded, either use EBAZ_BOARD_PART explicitly or
# select the first board whose part name contains ebaz4205.
set chosen_board ""
if {[info exists ::env(EBAZ_BOARD_PART)] && $::env(EBAZ_BOARD_PART) ne ""} {
    set chosen_board $::env(EBAZ_BOARD_PART)
} else {
    set candidates [get_board_parts -quiet *ebaz4205*]
    if {[llength $candidates] > 0} { set chosen_board [lindex $candidates 0] }
}
if {$chosen_board ne ""} {
    puts "INFO: using board part $chosen_board"
    set_property BOARD_PART $chosen_board [current_project]
} else {
    puts "WARNING: no EBAZ4205 BOARD_PART found. Project uses raw part $part_name."
    puts "WARNING: project-local board.repoPaths did not expose EBAZ4205 in this Vivado session."
    puts "WARNING: run scripts/install_ebaz4205_board_support_vivado.sh, then re-run this build."
}

set rtl_files [glob -nocomplain [file join $root_dir rtl *.v]]
if {[llength $rtl_files] == 0} { error "No RTL files found under $root_dir/rtl" }
add_files -norecurse $rtl_files

# Board-level PL constraints.  The PHY reference-clock constraint is optional
# because EBAZ4205 boards exist both with and without the 25 MHz crystal Y3.
set eth_xdc [file join $root_dir constraints ebaz4205_ethernet.xdc]
if {![file exists $eth_xdc]} { error "Missing Ethernet XDC: $eth_xdc" }
add_files -fileset constrs_1 -norecurse $eth_xdc

set phy_clock_from_pl 0
if {[info exists ::env(EBAZ_PHY_CLOCK_FROM_PL)] && $::env(EBAZ_PHY_CLOCK_FROM_PL) eq "1"} {
    set phy_clock_from_pl 1
    set phy_clk_xdc [file join $root_dir constraints ebaz4205_phy_clock_from_pl.xdc]
    if {![file exists $phy_clk_xdc]} { error "Missing optional PHY clock XDC: $phy_clk_xdc" }
    add_files -fileset constrs_1 -norecurse $phy_clk_xdc
}
update_compile_order -fileset sources_1

source [file join $script_dir create_ebaz4205_full_bd.tcl]

set bd_file [get_files -quiet ${bd_name}.bd]
if {[llength $bd_file] != 1} { error "Could not locate generated block design ${bd_name}.bd" }
generate_target all $bd_file
make_wrapper -files $bd_file -top

# Vivado 2020.2 writes the wrapper here. Add it explicitly; merely setting TOP
# is not sufficient if the file has not been added to sources_1.
set wrapper_path [file join $proj_dir Sam_NPU_EBAZ4205.gen sources_1 bd $bd_name hdl ${bd_name}_wrapper.v]
if {![file exists $wrapper_path]} {
    error "Generated wrapper not found at expected Vivado 2020.2 path: $wrapper_path"
}
add_files -norecurse $wrapper_path
update_compile_order -fileset sources_1
set_property top ${bd_name}_wrapper [current_fileset]

file mkdir [file join $root_dir reports_ebaz]
report_ip_status -file [file join $root_dir reports_ebaz ip_status.rpt]

set run_synth 0
if {[info exists ::env(RUN_SYNTH)] && $::env(RUN_SYNTH) eq "1"} { set run_synth 1 }
set run_impl 0
if {[info exists ::env(RUN_IMPL)] && $::env(RUN_IMPL) eq "1"} { set run_impl 1 }
if {$run_impl} { set run_synth 1 }

if {$run_synth} {
    puts "INFO: launching full-system synthesis"
    launch_runs synth_1 -jobs $vivado_jobs
    wait_on_run synth_1
    set synth_status [get_property STATUS [get_runs synth_1]]
    puts "INFO: synth_1 STATUS=$synth_status"
    if {![string match "*Complete*" $synth_status]} {
        error "synth_1 did not complete successfully: $synth_status"
    }
    open_run synth_1
    report_utilization -file [file join $root_dir reports_ebaz utilization_synth.rpt]
    report_timing_summary -file [file join $root_dir reports_ebaz timing_synth.rpt]
    check_timing -verbose -file [file join $root_dir reports_ebaz check_timing_synth.rpt]
    report_drc -file [file join $root_dir reports_ebaz drc_synth.rpt]
}

if {$run_impl} {
    if {$chosen_board eq "" || !$have_board_preset} {
        error "RUN_IMPL requested without a confirmed EBAZ4205 PS7 DDR/MIO board preset. Refusing to guess DDR/MIO configuration."
    }
    puts "INFO: launching implementation + bitstream"
    launch_runs impl_1 -to_step route_design -jobs $vivado_jobs
    wait_on_run impl_1
    set impl_status [get_property STATUS [get_runs impl_1]]
    puts "INFO: impl_1 STATUS=$impl_status"
    if {![string match "*Complete*" $impl_status]} {
        error "impl_1 did not complete successfully: $impl_status"
    }
    open_run impl_1
    report_utilization -file [file join $root_dir reports_ebaz utilization_impl.rpt]
    report_timing_summary -file [file join $root_dir reports_ebaz timing_impl.rpt]
    check_timing -verbose -file [file join $root_dir reports_ebaz check_timing_impl.rpt]
    report_route_status -file [file join $root_dir reports_ebaz route_status.rpt]
    report_drc -file [file join $root_dir reports_ebaz drc_impl.rpt]

    # A completed implementation run can still violate timing.  Treat both
    # setup and hold slack as release gates instead of merely generating a
    # report that a user might overlook.
    set worst_setup [get_timing_paths -quiet -delay_type max -max_paths 1 -nworst 1]
    set worst_hold  [get_timing_paths -quiet -delay_type min -max_paths 1 -nworst 1]
    if {[llength $worst_setup] == 0} { error "No constrained setup timing path found after implementation" }
    if {[llength $worst_hold] == 0}  { error "No constrained hold timing path found after implementation" }
    set setup_slack [get_property SLACK [lindex $worst_setup 0]]
    set hold_slack  [get_property SLACK [lindex $worst_hold 0]]
    puts "INFO: final setup slack = $setup_slack ns"
    puts "INFO: final hold  slack = $hold_slack ns"
    if {$setup_slack < 0.0} { error "Final implementation fails setup timing: WNS=$setup_slack ns" }
    if {$hold_slack  < 0.0} { error "Final implementation fails hold timing: WHS=$hold_slack ns" }

    # Release a bitstream only after routed setup/hold gates above pass.
    close_design
    launch_runs impl_1 -to_step write_bitstream -jobs $vivado_jobs
    wait_on_run impl_1
    set bit_status [get_property STATUS [get_runs impl_1]]
    if {![string match "*write_bitstream Complete*" $bit_status]} {
        error "Bitstream generation failed: $bit_status"
    }
    open_run impl_1
    write_hw_platform -fixed -include_bit -force -file [file join $root_dir reports_ebaz Sam_NPU_EBAZ4205.xsa]
}

puts "============================================================"
puts "BUILD FLOW COMPLETE"
puts "Project: $proj_dir"
puts "BD: $bd_name"
puts "Board part: $chosen_board"
puts "Board preset applied: $have_board_preset"
puts "NPU control: 0x43C00000 / 64K"
puts "DMA control: 0x40400000 / 64K"
puts "Ethernet: GEM0 EMIO + EBAZ4205 IP101GA pins enabled"
puts "PHY 25MHz from PL: $phy_clock_from_pl"
puts "RUN_SYNTH=$run_synth RUN_IMPL=$run_impl"
puts "============================================================"
