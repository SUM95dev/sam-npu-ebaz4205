#!/bin/sh
set -eu
IFACE="${1:-eth0}"
ADDR="${2:-192.168.50.2/24}"
ip link set "$IFACE" up
ip addr flush dev "$IFACE"
ip addr add "$ADDR" dev "$IFACE"
echo "NPU Ethernet configured: $IFACE $ADDR"
ip -brief addr show "$IFACE"
