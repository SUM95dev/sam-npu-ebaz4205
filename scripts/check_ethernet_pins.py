#!/usr/bin/env python3
from pathlib import Path
import re, sys
xdc=Path(__file__).resolve().parents[1]/'constraints'/'ebaz4205_ethernet.xdc'
t=xdc.read_text()
expected={
'ENET0_GMII_RX_CLK_0':'U14','ENET0_GMII_TX_CLK_0':'U15',
'ENET0_GMII_RXD_0[0]':'Y16','ENET0_GMII_RXD_0[1]':'V16','ENET0_GMII_RXD_0[2]':'V17','ENET0_GMII_RXD_0[3]':'Y17',
'ENET0_GMII_RX_DV_0':'W16',
'ENET0_GMII_TXD_0[0]':'W18','ENET0_GMII_TXD_0[1]':'Y18','ENET0_GMII_TXD_0[2]':'V18','ENET0_GMII_TXD_0[3]':'Y19',
'ENET0_GMII_TX_EN_0[0]':'W19','MDIO_ETHERNET_0_0_mdc':'W15','MDIO_ETHERNET_0_0_mdio_io':'Y14',
}
fail=[]
for port,pin in expected.items():
    # tolerate Tcl braces around bus ports
    pat=rf'PACKAGE_PIN\s+{re.escape(pin)}\s+\[get_ports\s+\{{?{re.escape(port)}\}}?\]'
    if not re.search(pat,t): fail.append(f'{port}: expected {pin}')
# Check duplicate package assignments in Ethernet XDC.
pairs=re.findall(r'PACKAGE_PIN\s+(\S+)\s+\[get_ports\s+([^\]]+)\]',t)
pins={}
for pin,port in pairs:
    pins.setdefault(pin,[]).append(port)
for pin,ports in pins.items():
    if len(ports)>1: fail.append(f'duplicate PACKAGE_PIN {pin}: {ports}')
if fail:
    print('ETHERNET PIN AUDIT FAIL')
    print('\n'.join(fail))
    sys.exit(1)
print(f'ETHERNET PIN AUDIT PASS: {len(expected)}/{len(expected)} mapped pins match known EBAZ4205 map')
