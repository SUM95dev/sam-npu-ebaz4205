# EBAZ4205 onboard IP101GA Ethernet PHY
# Known-working EBAZ4205 Vivado reference pin mapping.
# PS GEM0 is routed through EMIO and exposed as a 4-bit MII-style bus.

set_property IOSTANDARD LVCMOS33 [get_ports ENET0_GMII_RX_CLK_0]
set_property IOSTANDARD LVCMOS33 [get_ports ENET0_GMII_TX_CLK_0]
set_property PACKAGE_PIN U14 [get_ports ENET0_GMII_RX_CLK_0]
set_property PACKAGE_PIN U15 [get_ports ENET0_GMII_TX_CLK_0]

set_property IOSTANDARD LVCMOS33 [get_ports {ENET0_GMII_RXD_0[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ENET0_GMII_TXD_0[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ENET0_GMII_TX_EN_0[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports ENET0_GMII_RX_DV_0]
set_property IOSTANDARD LVCMOS33 [get_ports MDIO_ETHERNET_0_0_mdc]
set_property IOSTANDARD LVCMOS33 [get_ports MDIO_ETHERNET_0_0_mdio_io]

set_property PACKAGE_PIN Y17 [get_ports {ENET0_GMII_RXD_0[3]}]
set_property PACKAGE_PIN V17 [get_ports {ENET0_GMII_RXD_0[2]}]
set_property PACKAGE_PIN V16 [get_ports {ENET0_GMII_RXD_0[1]}]
set_property PACKAGE_PIN Y16 [get_ports {ENET0_GMII_RXD_0[0]}]
set_property PACKAGE_PIN W19 [get_ports {ENET0_GMII_TX_EN_0[0]}]
set_property PACKAGE_PIN W18 [get_ports {ENET0_GMII_TXD_0[0]}]
set_property PACKAGE_PIN Y18 [get_ports {ENET0_GMII_TXD_0[1]}]
set_property PACKAGE_PIN V18 [get_ports {ENET0_GMII_TXD_0[2]}]
set_property PACKAGE_PIN Y19 [get_ports {ENET0_GMII_TXD_0[3]}]
set_property PACKAGE_PIN W15 [get_ports MDIO_ETHERNET_0_0_mdc]
set_property PACKAGE_PIN Y14 [get_ports MDIO_ETHERNET_0_0_mdio_io]
set_property PACKAGE_PIN W16 [get_ports ENET0_GMII_RX_DV_0]

# MII is 25 MHz at 100 Mb/s (2.5 MHz at 10 Mb/s).  Constrain for the
# faster case; board/PHY-specific I/O delays should be added after timing
# validation against the exact IP101GA datasheet and board revision.
create_clock -name ebaz_mii_rx_clk -period 40.000 [get_ports ENET0_GMII_RX_CLK_0]
create_clock -name ebaz_mii_tx_clk -period 40.000 [get_ports ENET0_GMII_TX_CLK_0]
