# Complete PS7 + AXI DMA + Sam NPU block design for Vivado 2020.2.
# Assumes the project already contains rtl/*.v, including npu_bd_top.v.
# A known-good EBAZ4205 PS7/DDR board preset is strongly recommended.

set bd_name "npu_system"
if {[llength [get_bd_designs -quiet $bd_name]]} {
    close_bd_design [get_bd_designs $bd_name]
    catch {remove_files [get_files -quiet ${bd_name}.bd]}
}
create_bd_design $bd_name
current_bd_design $bd_name

# --- Processing System ---
set ps7 [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7_0]

# Apply board preset when Vivado knows an EBAZ board part. If not, keep going
# with the PS shell but refuse to pretend DDR electrical configuration is known.
set board_part [get_property -quiet BOARD_PART [current_project]]
set have_board_preset 0
if {$board_part ne ""} {
    puts "INFO: project BOARD_PART=$board_part"
    if {![catch {
        apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
            -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} \
            [get_bd_cells ps7_0]
    } preset_msg]} {
        set have_board_preset 1
        puts "INFO: PS7 board preset applied."
    } else {
        puts "WARNING: board preset automation failed: $preset_msg"
    }
}

if {!$have_board_preset} {
    puts "WARNING: No confirmed EBAZ4205 board preset was applied."
    puts "WARNING: DDR/MIO values are NOT being guessed. Apply your known-good EBAZ4205 PS7 preset before bitstream generation."
    # Export DDR/FIXED_IO so the design structure is still complete.
    if {[llength [get_bd_intf_ports -quiet DDR]] == 0} {
        make_bd_intf_pins_external [get_bd_intf_pins ps7_0/DDR]
        set_property name DDR [get_bd_intf_ports DDR_0]
    }
    if {[llength [get_bd_intf_ports -quiet FIXED_IO]] == 0} {
        make_bd_intf_pins_external [get_bd_intf_pins ps7_0/FIXED_IO]
        set_property name FIXED_IO [get_bd_intf_ports FIXED_IO_0]
    }
}

# Required fabric ports: GP0 control, HP0 DDR traffic, FCLK0 100 MHz.
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100.000000} \
] $ps7

# --- EBAZ4205 Ethernet PHY (PS GEM0 through EMIO, 4-bit MII) ---
# The board preset enables ENET0/MDIO on EMIO.  Zynq PS exposes an 8-bit
# GMII-style data bus; the EBAZ4205 IP101GA is wired as a 4-bit MII bus.
# Match the known-working Vivado 2020.2 EBAZ4205 reference design:
#   RX: PHY[3:0] -> low nibble, high nibble tied to zero
#   TX: low nibble of PS TXD -> PHY[3:0]
# RX/TX clocks and MDIO/MDC are passed directly.
set_property -dict [list \
    CONFIG.PCW_EN_ENET0 {1} \
    CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_ENET0_ENET0_IO {EMIO} \
    CONFIG.PCW_ENET0_GRP_MDIO_ENABLE {1} \
    CONFIG.PCW_ENET0_GRP_MDIO_IO {EMIO} \
    CONFIG.PCW_ENET0_PERIPHERAL_CLKSRC {External} \
] $ps7

# Some EBAZ4205 revisions omit the 25 MHz PHY crystal (Y3).  Do NOT
# blindly drive U18 on every board.  Enable this only when the board needs
# the PHY reference clock from PL:
#   EBAZ_PHY_CLOCK_FROM_PL=1
set phy_clock_from_pl 0
if {[info exists ::env(EBAZ_PHY_CLOCK_FROM_PL)] && $::env(EBAZ_PHY_CLOCK_FROM_PL) eq "1"} {
    set phy_clock_from_pl 1
    set_property -dict [list \
        CONFIG.PCW_EN_CLK1_PORT {1} \
        CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ {25.000000} \
    ] $ps7
    set phy_refclk [create_bd_port -dir O -type clk EBAZ_PHY_CLK_25M]
    connect_bd_net [get_bd_pins ps7_0/FCLK_CLK1] $phy_refclk
    puts "INFO: EBAZ PHY 25 MHz reference clock enabled on PL FCLK1 (constraint U18)."
} else {
    puts "INFO: EBAZ PHY reference clock output disabled (assumes onboard Y3/oscillator is present)."
}

# The EBAZ4205 PHY is wired as 4-bit MII (100 Mbit/s). PS7 defaults ENET0 to
# 1000 Mbps; select 100 Mbps explicitly so the GEM clock dividers/speed match.
# The board preset may already do this; do not fail the build if the property
# value is rejected by a different PS7 version, but make the problem visible.
if {[catch {set_property CONFIG.PCW_ENET0_PERIPHERAL_FREQMHZ {100 Mbps} $ps7} enet_speed_msg]} {
    puts "WARNING: could not set PCW_ENET0_PERIPHERAL_FREQMHZ=100 Mbps: $enet_speed_msg"
    puts "WARNING: verify ENET0 speed in the generated PS7 configuration before bitstream use."
}

set eth_rx_concat [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 eth_rx_concat]
set_property -dict [list CONFIG.IN0_WIDTH {4} CONFIG.IN1_WIDTH {4}] $eth_rx_concat
set eth_rx_hi_zero [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 eth_rx_hi_zero]
set_property -dict [list CONFIG.CONST_WIDTH {4} CONFIG.CONST_VAL {0}] $eth_rx_hi_zero
set eth_tx_slice [create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 eth_tx_slice]
set_property -dict [list CONFIG.DIN_WIDTH {8} CONFIG.DIN_FROM {3} CONFIG.DIN_TO {0} CONFIG.DOUT_WIDTH {4}] $eth_tx_slice

set eth_mdio [create_bd_intf_port -mode Master -vlnv xilinx.com:interface:mdio_rtl:1.0 MDIO_ETHERNET_0_0]
set eth_rxd  [create_bd_port -dir I -from 3 -to 0 ENET0_GMII_RXD_0]
set eth_rxck [create_bd_port -dir I -type clk ENET0_GMII_RX_CLK_0]
set eth_rxdv [create_bd_port -dir I ENET0_GMII_RX_DV_0]
set eth_txd  [create_bd_port -dir O -from 3 -to 0 ENET0_GMII_TXD_0]
set eth_txck [create_bd_port -dir I -type clk ENET0_GMII_TX_CLK_0]
set eth_txen [create_bd_port -dir O -from 0 -to 0 ENET0_GMII_TX_EN_0]

connect_bd_intf_net $eth_mdio [get_bd_intf_pins ps7_0/MDIO_ETHERNET_0]
connect_bd_net $eth_rxck [get_bd_pins ps7_0/ENET0_GMII_RX_CLK]
connect_bd_net $eth_rxdv [get_bd_pins ps7_0/ENET0_GMII_RX_DV]
connect_bd_net $eth_txck [get_bd_pins ps7_0/ENET0_GMII_TX_CLK]
connect_bd_net $eth_rxd [get_bd_pins eth_rx_concat/In0]
connect_bd_net [get_bd_pins eth_rx_hi_zero/dout] [get_bd_pins eth_rx_concat/In1]
connect_bd_net [get_bd_pins eth_rx_concat/dout] [get_bd_pins ps7_0/ENET0_GMII_RXD]
connect_bd_net [get_bd_pins ps7_0/ENET0_GMII_TXD] [get_bd_pins eth_tx_slice/Din]
connect_bd_net [get_bd_pins eth_tx_slice/Dout] $eth_txd
connect_bd_net [get_bd_pins ps7_0/ENET0_GMII_TX_EN] $eth_txen

# --- NPU module reference ---
set npu [create_bd_cell -type module -reference npu_bd_top npu_0]

# --- AXI DMA ---
set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0]
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_sg_length_width {23} \
    CONFIG.c_include_mm2s {1} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_m_axi_mm2s_data_width {128} \
    CONFIG.c_m_axis_mm2s_tdata_width {128} \
    CONFIG.c_m_axi_s2mm_data_width {64} \
    CONFIG.c_s_axis_s2mm_tdata_width {32} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
] $dma
# The stream width of an AXI DMA channel must not exceed its memory-map width,
# so the 128-bit MM2S stream needs a >=128-bit M_AXI_MM2S (the interconnect
# narrows it to the 64-bit HP0 port).  S2MM streams 32 bits into a 64-bit port.

# --- AXI interconnects ---
# GP0: PS master -> {NPU AXI-Lite, DMA AXI-Lite}
set ctrl_ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_ctrl_ic]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2}] $ctrl_ic

# HP0: {DMA MM2S master, DMA S2MM master} -> PS DDR slave
set mem_ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_hp0_ic]
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1}] $mem_ic

# Reset synchronizer.
set rst0 [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_fclk0]
# PS FCLK_RESET0_N is active-low; do not depend on IP defaults/propagation.
set_property CONFIG.C_EXT_RESET_HIGH {0} $rst0
set locked [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_locked]
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] $locked

# --- AXI interface connections ---
connect_bd_intf_net [get_bd_intf_pins ps7_0/M_AXI_GP0] [get_bd_intf_pins axi_ctrl_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_ctrl_ic/M00_AXI] [get_bd_intf_pins npu_0/S_AXI_CTRL]
connect_bd_intf_net [get_bd_intf_pins axi_ctrl_ic/M01_AXI] [get_bd_intf_pins axi_dma_0/S_AXI_LITE]

connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_MM2S] [get_bd_intf_pins axi_hp0_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] [get_bd_intf_pins axi_hp0_ic/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_hp0_ic/M00_AXI] [get_bd_intf_pins ps7_0/S_AXI_HP0]

connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] [get_bd_intf_pins npu_0/S_AXIS_IN]
connect_bd_intf_net [get_bd_intf_pins npu_0/M_AXIS_OUT] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

# --- Clock: everything uses PS FCLK_CLK0 at 100 MHz for first bring-up ---
set fclk [get_bd_pins ps7_0/FCLK_CLK0]
foreach p [list \
    ps7_0/M_AXI_GP0_ACLK ps7_0/S_AXI_HP0_ACLK \
    axi_ctrl_ic/ACLK axi_ctrl_ic/S00_ACLK axi_ctrl_ic/M00_ACLK axi_ctrl_ic/M01_ACLK \
    axi_hp0_ic/ACLK axi_hp0_ic/S00_ACLK axi_hp0_ic/S01_ACLK axi_hp0_ic/M00_ACLK \
    axi_dma_0/s_axi_lite_aclk axi_dma_0/m_axi_mm2s_aclk axi_dma_0/m_axi_s2mm_aclk \
    npu_0/aclk rst_fclk0/slowest_sync_clk \
] {
    connect_bd_net $fclk [get_bd_pins $p]
}

# --- Reset ---
connect_bd_net [get_bd_pins ps7_0/FCLK_RESET0_N] [get_bd_pins rst_fclk0/ext_reset_in]
connect_bd_net [get_bd_pins const_locked/dout] [get_bd_pins rst_fclk0/dcm_locked]
set periph_rstn [get_bd_pins rst_fclk0/peripheral_aresetn]
set inter_rstn  [get_bd_pins rst_fclk0/interconnect_aresetn]

foreach p [list npu_0/aresetn axi_dma_0/axi_resetn] {
    connect_bd_net $periph_rstn [get_bd_pins $p]
}
foreach p [list \
    axi_ctrl_ic/ARESETN axi_ctrl_ic/S00_ARESETN axi_ctrl_ic/M00_ARESETN axi_ctrl_ic/M01_ARESETN \
    axi_hp0_ic/ARESETN axi_hp0_ic/S00_ARESETN axi_hp0_ic/S01_ARESETN axi_hp0_ic/M00_ARESETN \
] {
    connect_bd_net $inter_rstn [get_bd_pins $p]
}

# Linux DMAengine requires completion interrupts for both directions.
if {[catch {
    set_property -dict [list CONFIG.PCW_USE_FABRIC_INTERRUPT {1} CONFIG.PCW_IRQ_F2P_INTR {1}] $ps7
    set irqcat [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 dma_irq_concat]
    set_property -dict [list CONFIG.NUM_PORTS {3}] $irqcat
    connect_bd_net [get_bd_pins axi_dma_0/mm2s_introut] [get_bd_pins dma_irq_concat/In0]
    connect_bd_net [get_bd_pins axi_dma_0/s2mm_introut] [get_bd_pins dma_irq_concat/In1]
    connect_bd_net [get_bd_pins npu_0/irq] [get_bd_pins dma_irq_concat/In2]
    connect_bd_net [get_bd_pins dma_irq_concat/dout] [get_bd_pins ps7_0/IRQ_F2P]
} irq_msg]} {
    error "Required DMA/NPU interrupt wiring failed: $irq_msg"
}

# Deterministic control-map addresses.  Keep NPU control small (64 KiB) instead
# of allowing IP Integrator to infer a huge 512 MiB/2 GiB window from the
# 32-bit AXI address bus.  These match the Linux UIO example.
set dma_reg_seg [get_bd_addr_segs -quiet {/axi_dma_0/S_AXI_LITE/Reg}]
set npu_reg_seg [get_bd_addr_segs -quiet {/npu_0/S_AXI_CTRL/reg0}]
if {[llength $dma_reg_seg] != 1} { error "Could not resolve AXI DMA control segment" }
if {[llength $npu_reg_seg] != 1} { error "Could not resolve NPU control segment" }
assign_bd_address -offset 0x40400000 -range 64K $dma_reg_seg
assign_bd_address -offset 0x43C00000 -range 64K $npu_reg_seg

# Auto-map the remaining memory-facing segments (DMA MM2S/S2MM -> HP0 DDR).
assign_bd_address

save_bd_design
validate_bd_design
save_bd_design

puts "============================================================"
puts "Sam NPU EBAZ4205 block design created and validated structurally."
puts "Control: PS M_AXI_GP0 -> NPU + AXI DMA S_AXI_LITE"
puts "Data: DDR/HP0 <-> AXI DMA <-> NPU AXI-Stream"
puts "Clock: FCLK_CLK0 = 100 MHz"
puts "Ethernet: PS GEM0/EMIO <-> IP101GA PHY (4-bit MII), TCP/IP handled by ARM/Linux"
puts "PHY 25MHz from PL: $phy_clock_from_pl"
puts "NPU control: 0x43C00000 / 64K"
puts "DMA control: 0x40400000 / 64K"
if {!$have_board_preset} {
    puts "STOP BEFORE BITSTREAM: apply a known-good EBAZ4205 PS7 DDR/MIO preset."
}
puts "============================================================"
