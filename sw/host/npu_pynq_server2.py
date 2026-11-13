#!/usr/bin/env python3
"""PYNQ server v2: drives AXI DMA registers directly (polling), bypassing the
PYNQ DMA driver (it needs an axi_intc that this design does not have).
Needs npu_pynq_server.py in the same directory.
Run: sudo -E python3 npu_pynq_server2.py sam_npu.bit [port] [bind_ip]"""
import socket, sys, time, threading
import numpy as np
import npu_pynq_server as b

DMA_BASE = 0x40400000
MM2S_CR, MM2S_SR, MM2S_SA, MM2S_LEN = 0x00, 0x04, 0x18, 0x28
S2MM_CR, S2MM_SR, S2MM_DA, S2MM_LEN = 0x30, 0x34, 0x48, 0x58


class Dev2(b.Dev):
    def __init__(self, bit):
        from pynq import Overlay, MMIO, allocate
        self.ol = Overlay(bit)
        self.mmio = MMIO(b.NPU_BASE, 0x1000)
        self.dma = MMIO(DMA_BASE, 0x1000)
        self.tx = allocate(shape=(b.BUF,), dtype=np.uint8)
        self.rx = allocate(shape=(b.BUF,), dtype=np.uint8)
        self.lock = threading.Lock()
        self.dma_reset()
        print('overlay loaded (direct DMA); NPU version 0x%08x caps 0x%08x' %
              (self.rd(b.REG_VERSION), self.rd(b.REG_CAPS)))

    def dma_reset(self):
        self.dma.write(MM2S_CR, 4); self.dma.write(S2MM_CR, 4)
        t0 = time.time()
        while self.dma.read(MM2S_CR) & 4 or self.dma.read(S2MM_CR) & 4:
            if time.time() - t0 > 1: break
        self.dma.write(MM2S_CR, 1); self.dma.write(S2MM_CR, 1)

    def abort(self):
        self.wr(b.REG_CMD, (self.rd(b.REG_CMD) & b.CMD_IRQ_EN) | b.CMD_ABORT | b.CMD_ACK_DONE | b.CMD_ACK_ERROR)
        self.dma_reset()

    def _wait(self, sr_off, t0):
        while True:
            sr = self.dma.read(sr_off)
            if sr & 0x70: return -40 if sr_off == MM2S_SR else -41   # DMA error bits
            if sr & 0x1000: return 0                                   # IOC
            if time.time() - t0 > b.TIMEOUT_S: return -42
            time.sleep(0.0002)

    def run(self, op, M, N, K, flags, qmul, qshift, zp, payload, outb):
        caps = self.rd(b.REG_CAPS)
        bit = {1: 0, 2: 1, 3: 2, 4: 3}[op]
        if not (caps >> bit) & 1 or ((flags & 2) and not (caps >> 7) & 1): return -14, b''
        inb = len(payload)
        self.tx[:inb] = np.frombuffer(payload, dtype=np.uint8)
        self.rx[:outb] = 0
        if self.rd(b.REG_CTRL) & 1:
            self.abort()
            if self.rd(b.REG_CTRL) & 1: return -15, b''
        self.wr(b.REG_CMD, (self.rd(b.REG_CMD) & b.CMD_IRQ_EN) | b.CMD_ACK_DONE | b.CMD_ACK_ERROR)
        self.wr(b.REG_M, M); self.wr(b.REG_N, N); self.wr(b.REG_K, K)
        self.wr(b.REG_ACT, 1 if flags & 1 else 0)
        self.wr(b.REG_QMUL, qmul); self.wr(b.REG_QSHIFT, qshift); self.wr(b.REG_ZP, zp & 0xFF)
        self.dma.write(MM2S_SR, 0x7000); self.dma.write(S2MM_SR, 0x7000)   # clear IOC/Dly/Err
        self.dma.write(S2MM_DA, self.rx.physical_address); self.dma.write(S2MM_LEN, outb)
        self.dma.write(MM2S_SA, self.tx.physical_address); self.dma.write(MM2S_LEN, inb)
        mode = {1: 0, 2: 1 << 1, 3: 1 << 2, 4: 1 << 3}[op]
        if op == 1 and (flags & 2): mode |= 1 << 4
        self.wr(b.REG_CTRL, 1 | mode)
        t0 = time.time()
        while True:
            s = self.rd(b.REG_CTRL)
            if s & 4: self.abort(); return -30, b''
            if s & 2: break
            if time.time() - t0 > b.TIMEOUT_S: self.abort(); return -31, b''
        st = self._wait(MM2S_SR, t0)
        if st == 0: st = self._wait(S2MM_SR, t0)
        if st: self.abort(); return st, b''
        out = np.array(self.rx[:outb], dtype=np.uint8)
        if op == 1:
            out = b.tile_to_row_major(out.view(np.uint32), M, N).view(np.uint8)
        return 0, out.tobytes()


def main():
    if len(sys.argv) < 2: sys.exit(__doc__)
    bit = sys.argv[1]; port = int(sys.argv[2]) if len(sys.argv) > 2 else 9505
    ip = sys.argv[3] if len(sys.argv) > 3 else '0.0.0.0'
    dev = Dev2(bit)
    s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((ip, port)); s.listen(4); print('listening on %s:%d' % (ip, port), flush=True)
    while True:
        c, _ = s.accept()
        threading.Thread(target=b.handle, args=(c, dev), daemon=True).start()


if __name__ == '__main__':
    main()
