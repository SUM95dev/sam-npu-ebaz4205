# Safe implementation/bitstream entry point for the canonical EBAZ4205 build.
# It intentionally re-runs the canonical project generator so board preset,
# Ethernet constraints, deterministic addresses, synthesis and implementation
# all use one source of truth.
set script_dir [file dirname [file normalize [info script]]]
set ::env(RUN_SYNTH) 1
set ::env(RUN_IMPL) 1
source [file join $script_dir build_ebaz4205_system.tcl]
