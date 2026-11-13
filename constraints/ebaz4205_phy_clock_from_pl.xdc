# OPTIONAL: use only on EBAZ4205 revisions without the 25 MHz PHY crystal Y3.
# Enabled by setting EBAZ_PHY_CLOCK_FROM_PL=1 in the build environment.
set_property PACKAGE_PIN U18 [get_ports EBAZ_PHY_CLK_25M]
set_property IOSTANDARD LVCMOS33 [get_ports EBAZ_PHY_CLK_25M]
