#!/usr/bin/env python3
"""Sam NPU server for PYNQ. Same TCP protocol v1 as sw/linux/npu_net_server.c,
so npu_board_selftest.py / npu_runtime.py work unchanged from a PC.

Run ON THE BOARD (PYNQ image), as root:
    sudo -E python3 npu_pynq_server.py sam_npu.bit [port] [bind_ip]
sam_npu.hwh must sit next to sam_npu.bit.

UNTESTED ON HARDWARE. Registers/sequence mirror npu_net_server.c.
"""
import socket, struct, sys, time, threading
import numpy as np

REQ = struct.Struct('!4sHHHHHHiBbhIII'); REP = struct.Struct('!4sIiI')
NPU_BASE = 0x43C00000
REG_CTRL, REG_M, REG_N, REG_K, REG_ACT, REG_CMD = 0x00, 0x04, 0x08, 0x0C, 0x10, 0x14
REG_QMUL, REG_QSHIFT, REG_ZP, REG_VERSION, REG_CAPS = 0x18, 0x1C, 0x20, 0x24, 0x28
REG_TOTAL, REG_BUSY, REG_JOBS, REG_ERRORS, REG_LASTJOB = 0x2C, 0x30, 0x34, 0x38, 0x3C
CMD_IRQ_EN, CMD_ACK_DONE, CMD_ACK_ERROR, CMD_ABORT = 1, 2, 4, 16
BUF = 4 * 1024 * 1024
TIMEOUT_S = 5.0


def tile_to_row_major(src, M, N, T=8):
    """src: uint32 words in tile order -> row-major MxN uint32 array."""
    out = np.zeros(M * N, dtype=np.uint32); si = 0
    for tm in range((M + T - 1) // T):
        for tn in range((N + T - 1) // T):
            for r in range(T):
                row = tm * T + r
                if row >= M: continue
                for c in range(T):
                    col = tn * T + c
                    if col >= N: continue
                    out[row * N + col] = src[si]; si += 1
    return out


class Dev:
    def __init__(self, bit):
        from pynq import Overlay, MMIO, allocate
        self.ol = Overlay(bit)
        dma_name = [k for k in self.ol.ip_dict if 'axi_dma' in k][0]
        self.dma = getattr(self.ol, dma_name)
        self.mmio = MMIO(NPU_BASE, 0x1000)
        self.tx = allocate(shape=(BUF,), dtype=np.uint8)
        self.rx = allocate(shape=(BUF,), dtype=np.uint8)
        self.lock = threading.Lock()
        print('overlay loaded; DMA =', dma_name, '; NPU version 0x%08x caps 0x%08x' %
              (self.rd(REG_VERSION), self.rd(REG_CAPS)))

    def rd(self, o): return self.mmio.read(o)
    def wr(self, o, v): self.mmio.write(o, v & 0xFFFFFFFF)

    def abort(self):
        for ch in (self.dma.sendchannel, self.dma.recvchannel):
            try: ch.stop()
            except Exception: pass
        self.wr(REG_CMD, (self.rd(REG_CMD) & CMD_IRQ_EN) | CMD_ABORT | CMD_ACK_DONE | CMD_ACK_ERROR)
        try: self.dma.sendchannel.start(); self.dma.recvchannel.start()
        except Exception: pass

    def info(self):
        return struct.pack('!7I', *[self.rd(r) for r in
               (REG_VERSION, REG_CAPS, REG_TOTAL, REG_BUSY, REG_JOBS, REG_ERRORS, REG_LASTJOB)])

    def run(self, op, M, N, K, flags, qmul, qshift, zp, payload, outb):
        """returns (status, bytes)"""
        caps = self.rd(REG_CAPS)
        bit = {1: 0, 2: 1, 3: 2, 4: 3}[op]
        if not (caps >> bit) & 1 or ((flags & 2) and not (caps >> 7) & 1): return -14, b''
        inb = len(payload)
        self.tx[:inb] = np.frombuffer(payload, dtype=np.uint8)
        self.rx[:outb] = 0
        if self.rd(REG_CTRL) & 1:
            self.abort()
            if self.rd(REG_CTRL) & 1: return -15, b''
        self.wr(REG_CMD, (self.rd(REG_CMD) & CMD_IRQ_EN) | CMD_ACK_DONE | CMD_ACK_ERROR)
        self.wr(REG_M, M); self.wr(REG_N, N); self.wr(REG_K, K)
        self.wr(REG_ACT, 1 if flags & 1 else 0)
        self.wr(REG_QMUL, qmul); self.wr(REG_QSHIFT, qshift); self.wr(REG_ZP, zp & 0xFF)
        self.dma.recvchannel.transfer(self.rx[:outb])
        self.dma.sendchannel.transfer(self.tx[:inb])
        mode = {1: 0, 2: 1 << 1, 3: 1 << 2, 4: 1 << 3}[op]
        if op == 1 and (flags & 2): mode |= 1 << 4
        self.wr(REG_CTRL, 1 | mode)
        t0 = time.time()
        while True:
            s = self.rd(REG_CTRL)
            if s & 4: self.abort(); return -30, b''
            if s & 2: break
            if time.time() - t0 > TIMEOUT_S: self.abort(); return -31, b''
        self.dma.sendchannel.wait(); self.dma.recvchannel.wait()
        out = np.array(self.rx[:outb], dtype=np.uint8)
        if op == 1:
            w = tile_to_row_major(out.view(np.uint32), M, N)
            out = w.view(np.uint8)
        return 0, out.tobytes()


def recv_exact(c, n):
    b = bytearray()
    while len(b) < n:
        x = c.recv(n - len(b))
        if not x: raise ConnectionError
        b += x
    return bytes(b)


def handle(c, dev):
    def reply(rid, st, body=b''): c.sendall(REP.pack(b'SNPR', rid, st, len(body)) + body)
    try:
        while True:
            (magic, ver, op, M, N, K, flags, mul, shift, zp, _r, inb, outb, rid) = REQ.unpack(recv_exact(c, REQ.size))
            if magic != b'SNPU' or ver != 1: reply(rid, -10); return
            if op == 0:
                if inb or outb: reply(rid, -11); return
                with dev.lock: reply(rid, 0, dev.info())
                continue
            bias = bool(flags & 2)
            if (flags & ~3) or (bias and op != 1) or op < 1 or op > 4 or not inb or not outb or inb > BUF or \
               outb > BUF or shift > 63 or inb & 15 or outb & 3 or (op == 1 and not (M and N and K)):
                reply(rid, -11); return
            if op == 1:
                per = (K + 7) * 16 + (32 if bias else 0)
                if (-(-M // 8)) * (-(-N // 8)) * per != inb or M * N * 4 != outb: reply(rid, -12); return
            elif op == 3 and inb != outb * 16: reply(rid, -12); return
            elif op == 4 and inb != outb * 4: reply(rid, -12); return
            payload = recv_exact(c, inb)
            if op == 2 and not (struct.unpack_from('<I', payload, inb - 16)[0] >> 16) & 1: reply(rid, -13); return
            with dev.lock:
                st, body = dev.run(op, M, N, K, flags, mul, shift, zp, payload, outb)
            if st: reply(rid, st); return
            reply(rid, 0, body)
    except (ConnectionError, OSError):
        return
    finally:
        c.close()


def main():
    if len(sys.argv) < 2: sys.exit(__doc__)
    bit = sys.argv[1]; port = int(sys.argv[2]) if len(sys.argv) > 2 else 9505
    ip = sys.argv[3] if len(sys.argv) > 3 else '0.0.0.0'
    dev = Dev(bit)
    s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((ip, port)); s.listen(4); print('listening on %s:%d (no authentication!)' % (ip, port))
    while True:
        c, _ = s.accept()
        threading.Thread(target=handle, args=(c, dev), daemon=True).start()


if __name__ == '__main__':
    main()
