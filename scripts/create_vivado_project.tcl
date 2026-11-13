set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file normalize [file join $script_dir ".."]]
set proj_dir   [file join $root_dir "vivado_project"]

create_project Sam_NPU_CURRENT $proj_dir -part xc7z010clg400-1 -force
add_files [glob [file join $root_dir rtl *.v]]
add_files -fileset sim_1 [glob [file join $root_dir sim *.v]]
# Production RTL top for standalone synthesis; the full system is built by
# scripts/build_ebaz4205_system.tcl (npu_v4_top is a legacy research top).
set_property top npu_axis_system_top [current_fileset]
set_property top tb_npu_top_2x2 [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Project created at $proj_dir"
puts "Run all behavioral testbenches before synthesis."
