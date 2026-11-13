# Sam NPU full-system block-design skeleton for Vivado 2020.2.
# IMPORTANT: PS7 DDR/MIO must be configured from a KNOWN-GOOD EBAZ4205 PS config.
# This script does not invent DDR electrical parameters.

set bd_name "npu_system"
create_bd_design $bd_name

create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7_0
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0

set_property -dict [list \
  CONFIG.c_include_sg {0} \
    CONFIG.c_sg_length_width {23} \
  CONFIG.c_sg_include_stscntrl_strm {0} \
  CONFIG.c_m_axi_mm2s_data_width {128} \
  CONFIG.c_m_axis_mm2s_tdata_width {128} \
  CONFIG.c_s_axis_s2mm_tdata_width {32} \
] [get_bd_cells axi_dma_0]

# Add RTL top to project before running this script, then package it as IP
# or instantiate it as a module reference named npu_axis_system_top_0.
#
# Recommended topology:
# ps7_0/M_AXI_GP0 -> NPU AXI-Lite control
# axi_dma_0/M_AXIS_MM2S -> NPU S_AXIS
# NPU M_AXIS -> axi_dma_0/S_AXIS_S2MM
# axi_dma_0/M_AXI_MM2S + M_AXI_S2MM -> ps7_0/S_AXI_HP0 via AXI interconnect
#
# Run connection automation after applying your known-good PS7 DDR/MIO setup.
save_bd_design
puts "Created PS7 + AXI DMA skeleton. Apply known-good EBAZ4205 PS configuration before validation."
