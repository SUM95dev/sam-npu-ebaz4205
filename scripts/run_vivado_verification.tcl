# Run from the root of Sam_NPU_COMPLETE_INTEGRATED:
# vivado -mode batch -source scripts/run_vivado_verification.tcl
#
# This script performs:
# 1) project creation
# 2) behavioral simulation for each listed testbench
# 3) synthesis of the NPU system top
# 4) utilization/timing reports
#
# It intentionally does NOT claim board bitstream success unless a valid EBAZ4205
# PS7 block design / wrapper has already been created.

set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]
set proj_dir   [file join $root_dir vivado_verify]
set part_name  "xc7z010clg400-1"
# Low-RAM safe default for Sam's 4 GiB laptop. Override explicitly only on a
# machine with enough memory: VIVADO_JOBS=2 (or higher).
set_param general.maxThreads 1
set vivado_jobs 1
if {[info exists ::env(VIVADO_JOBS)] && [string is integer -strict $::env(VIVADO_JOBS)] && $::env(VIVADO_JOBS) > 0} {
    set vivado_jobs $::env(VIVADO_JOBS)
}
puts "INFO: Vivado parallel jobs = $vivado_jobs"


create_project Sam_NPU_Verify $proj_dir -part $part_name -force

set rtl_files [glob -nocomplain [file join $root_dir rtl *.v]]
set sim_files [concat [glob -nocomplain [file join $root_dir sim *.v]] [glob -nocomplain [file join $root_dir verification extra *.v]]]
add_files $rtl_files
add_files -fileset sim_1 $sim_files
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# Each testbench should finish itself; keep a finite simulator runtime as a safety net.
set_property xsim.simulate.runtime {200us} [get_filesets sim_1]
# XSim/xelab defaults to aggressive automatic multithreading (the earlier run
# used eight slave threads). On a 4 GiB machine that can amplify memory pressure.
# Vivado 2020.2 supports xsim.elaborate.mt_level; default this release to off and
# allow an explicit override for larger machines.
set xsim_mt_level off
if {[info exists ::env(XSIM_MT_LEVEL)] && $::env(XSIM_MT_LEVEL) ne ""} {
    set xsim_mt_level $::env(XSIM_MT_LEVEL)
}
set_property xsim.elaborate.mt_level $xsim_mt_level [get_filesets sim_1]
puts "INFO: XSim elaboration mt_level = $xsim_mt_level"

set tb_list {
    tb_npu_pe
    tb_systolic_2x2
    tb_pe_clear_pipeline
    tb_postprocess_boundaries
    tb_tile_postprocess
    tb_partial_tile_mask
    tb_matmul_controller_stall
    tb_controller_unsolicited_valid
    tb_controller_flush_cycles
    tb_regs_sticky_done
    tb_regs_invalid_start
    tb_regs_start_lock
    tb_axi_lite_read_write
    tb_matmul_engine_2x2
    tb_matmul_multitile_order
    tb_conv_stream
    tb_conv_config_latch
    tb_npu_top_2x2
    tb_axis_tile_output_backpressure
    tb_matmul_output_backpressure
    tb_system_done_after_stream
    tb_conv_stream_job
    tb_conv_scheduler_invalid_geometry
    tb_regs_extended
    tb_conv_stream_bias
    tb_axis_maxpool
    tb_axis_add
    tb_matmul_bias_feeder
    tb_case_0_0
    tb_case_0_1
    tb_case_1_0
    tb_case_1_1
    tb_case_2_0
    tb_case_2_1
    tb_case_3_0
    tb_case_3_1
    tb_case_4_0
    tb_case_4_1
    tb_case_5_0
    tb_case_5_1
    tb_case_6_0
    tb_case_6_1
    tb_case_7_0
    tb_case_7_1
    tb_case_8_0
    tb_case_8_1
    tb_case_9_0
    tb_case_9_1
    tb_axi_lite_random_stalls
    tb_conv_memory_stall
    tb_conv_memory_stall_c2
    tb_conv_final_fence
    tb_control_wstrb
    tb_dma_continuous
    tb_postprocess_pipe_equivalence
}

set pass_count 0
set fail_count 0
set failed {}

foreach tb $tb_list {
    puts "=== SIMULATING $tb ==="
    set_property top $tb [get_filesets sim_1]
    update_compile_order -fileset sim_1

    if {[catch {
        launch_simulation -simset sim_1 -mode behavioral
        close_sim

        # launch_simulation returning normally only proves XSim did not crash.
        # Every TB in this release emits a line beginning with PASS on success
        # and FAIL on a logical mismatch, so inspect the actual simulator log.
        set sim_logs [glob -nocomplain [file join $proj_dir *.sim sim_1 behav xsim simulate.log]]
        if {[llength $sim_logs] != 1} {
            error "could not locate unique simulate.log for $tb: $sim_logs"
        }
        set fh [open [lindex $sim_logs 0] r]
        set sim_text [read $fh]
        close $fh
        if {[regexp -line {^FAIL} $sim_text]} {
            error "testbench emitted FAIL"
        }
        if {![regexp -line {^PASS} $sim_text]} {
            error "testbench did not emit PASS (timeout or premature finish)"
        }
    } msg]} {
        puts "ERROR: $tb failed: $msg"
        incr fail_count
        lappend failed $tb
        catch {close_sim}
    } else {
        incr pass_count
    }
}

puts "SIM SUMMARY: PASS=$pass_count FAIL=$fail_count"
if {$fail_count > 0} {
    puts "FAILED TESTS: $failed"
    error "Behavioral simulation gate failed; synthesis intentionally skipped."
}

set_property top npu_axis_system_top [current_fileset]
update_compile_order -fileset sources_1

# Core-only synthesis previously had no user timing constraint, so WNS/TNS were
# reported as NA.  Constrain the public aclk port to the same 100 MHz used by
# the EBAZ block design.
set core_xdc [file join $proj_dir core_100mhz.xdc]
set xfh [open $core_xdc w]
puts $xfh {create_clock -period 10.000 -name aclk [get_ports aclk]}
close $xfh
add_files -fileset constrs_1 -norecurse $core_xdc

puts "=== SYNTHESIS ==="
launch_runs synth_1 -jobs $vivado_jobs
wait_on_run synth_1
open_run synth_1

file mkdir [file join $root_dir reports]
report_utilization -file [file join $root_dir reports utilization_synth.rpt]
report_timing_summary -file [file join $root_dir reports timing_synth.rpt]
report_drc -file [file join $root_dir reports drc_synth.rpt]

puts "Verification flow complete."
