#!/usr/bin/env python3
"""Execute BD Tcl against API mocks to check explicit settings/error propagation.
This is not Vivado validation. Set TCLSH to an installed tclsh executable.
"""
from pathlib import Path
import os,subprocess,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parents[2]
script=r'''
set configs [dict create]
set inject 0
proc get_bd_designs {args} {return {}}
proc current_project {} {return mock_project}
proc get_property {args} {return mock:ebaz4205:1.0}
proc create_bd_cell {args} {return [lindex $args end]}
proc get_bd_cells {args} {return [lindex $args end]}
proc get_bd_pins {args} {return [lindex $args end]}
proc get_bd_intf_pins {args} {return [lindex $args end]}
proc get_bd_addr_segs {args} {return [lindex $args end]}
proc set_property {args} {
 global configs
 if {[lindex $args 0] eq "-dict"} {
  dict for {k v} [lindex $args 1] {dict set configs [lindex $args 2] $k $v}
 } else {dict set configs [lindex $args 2] [lindex $args 0] [lindex $args 1]}
}
proc connect_bd_net {args} {
 global inject
 if {$inject && [lsearch -exact $args npu_0/irq]>=0} {error "injected missing IRQ pin"}
}
proc unknown {args} {return [lindex $args end]}
source {SOURCE}
if {![dict exists $configs axi_dma_0 CONFIG.c_sg_length_width] || [dict get $configs axi_dma_0 CONFIG.c_sg_length_width] != 23} {error "FAIL DMA length width not 23"}
if {![dict exists $configs rst_fclk0 CONFIG.C_EXT_RESET_HIGH] || [dict get $configs rst_fclk0 CONFIG.C_EXT_RESET_HIGH] != 0} {error "FAIL reset polarity not explicit active-low"}
set inject 1
if {![catch {source {SOURCE}} msg]} {error "FAIL IRQ connection failure was swallowed"}
if {![string match {*Required DMA/NPU interrupt wiring failed*} $msg]} {error "FAIL unexpected failure: $msg"}
puts "PASS BD explicit 23-bit DMA length, active-low reset and required IRQ fail-fast"
'''.replace('SOURCE',str(root/'scripts/create_ebaz4205_full_bd.tcl'))
# tclsh stdin may return zero on an uncaught interactive error. Use a file.
import tempfile
with tempfile.NamedTemporaryFile(mode='w',suffix='.tcl') as f:
 f.write(script);f.flush();subprocess.run([os.environ.get('TCLSH','tclsh'),f.name],check=True)
