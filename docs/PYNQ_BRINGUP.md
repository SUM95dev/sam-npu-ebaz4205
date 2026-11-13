# Sam NPU on PYNQ (EBAZ4205) - verified bring-up

Status: bitstream (Vivado 2020.2, routed WNS +0.593 ns / WHS +0.019 ns) loaded on a real EBAZ4205
running PYNQ 2.4 (Ubuntu 18.04, Python 3.6, kernel 4.19).

## What was verified on hardware
- `npu_board_selftest.py`: MatMul, Add, MaxPool, Conv+bias, depthwise Conv (tiny vectors) - PASS
- `npu_hw_compare.py`: 13 cases (MatMul up to 64x64x128 +/- bias, Conv incl. grouped) vs soft reference - ALL MATCH
- `npu_np_check.py`: 14 MatMul cases vs an independent numpy model incl. extremes (-128/+127) + 300-job stress,
  errors delta = 0 - ALL OK
- `demo/digits_all.py`: trained 64-32-10 digit MLP (INT8), 117/120 correct, outputs bit-identical to soft model
- Auto-start via systemd (`scripts/npu.service`) works after reboot.

## Not verified / known limits
- Only MatMul was checked against an independent (numpy) model; Conv/Pool/Add only against the project's soft model.
- Stress test ~18 s only; no long-duration or thermal test. FCLK0 frequency not read back (100 MHz assumed in GOPS numbers).
- Server is Python: end-to-end ~28 ms for a 64x128x64 MatMul vs 0.18 ms hardware (~5.8 GOPS at 100 MHz assumed).
- ONNX converter incomplete (quantization, NCHW/NHWC).
- Board Ethernet (eth0) does NOT come up with the stock PYNQ image: macb reports "MDIO device at address 0 is
  missing". Suspected cause: no 25 MHz PHY crystal (Y3) and clock from PL not enabled in this build
  (`scripts/build_ebaz4205_no_y3.sh`, needs R1485 bridged). Not tested.

## Procedure (no network: UART + SD card)
1. Copy `sam_npu.bit`, `sam_npu.hwh` (from the .xsa), `sw/` to the SD FAT partition.
2. On the board: `sudo mount /dev/mmcblk0p1 /mnt; cp -r /mnt/sam_npu.* /mnt/sw ~/`
3. Put `sw/host/npu_pynq_server.py` and `npu_pynq_server2.py` in `~` (server2 drives the AXI DMA registers directly;
   the PYNQ DMA driver fails with KeyError '' because this design has no axi_intc).
4. `sudo -E python3 npu_pynq_server2.py sam_npu.bit 9505 127.0.0.1`
5. `python3 sw/host/npu_board_selftest.py 127.0.0.1`
6. Autostart: install `scripts/npu.service` to /etc/systemd/system/, `systemctl daemon-reload; systemctl enable npu`.
   (Do not add `After=multi-user.target` - it creates an ordering cycle and the service may not start.)

Python 3.6 note: `time.perf_counter_ns` and `statistics.fmean` do not exist there (benchmark patched).
