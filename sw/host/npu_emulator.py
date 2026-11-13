#!/usr/bin/env python3
"""Hardware-faithful emulator of the Sam NPU TCP server (protocol v1).

It speaks exactly the wire protocol of sw/linux/npu_net_server.c and executes the
*raw DMA byte streams* the way the RTL does: the 8x8 systolic array is simulated
register-by-register (skewed feed, N-1 flush beats, per-tile bias preamble),
Conv consumes 16-byte MAC beats, MaxPool/Add consume 16-byte beats. Replies are
32-bit sign-extended words in row-major MatMul order. Use it to test host
software without a board. It does not model timing or the DMA engine.
"""
import socket, socketserver, struct, threading

REQ = struct.Struct('!4sHHHHHHiBbhIII'); REP = struct.Struct('!4sIiI')
N = 8; BUF = 4 * 1024 * 1024
CAPS = (32 << 24) | (8 << 16) | (N << 8) | 0xFF

def sat8(v): return max(-128, min(127, v))
def requant(acc, mul, shift, relu, zp):
    y = (acc * mul) >> shift
    if relu and y < 0: y = 0
    return sat8(y + zp)

def array_tile(beats):
    """Cycle-level model of systolic_array.v: K+N-1 feed beats then N-1 zero flush beats."""
    a_reg = [[0] * N for _ in range(N)]; b_reg = [[0] * N for _ in range(N)]
    acc = [[0] * N for _ in range(N)]
    def step(al, bt):
        nonlocal a_reg, b_reg, acc
        na = [[0] * N for _ in range(N)]; nb = [[0] * N for _ in range(N)]
        nacc = [[0] * N for _ in range(N)]
        for r in range(N):
            for c in range(N):
                a_in = al[r] if c == 0 else a_reg[r][c - 1]
                b_in = bt[c] if r == 0 else b_reg[r - 1][c]
                nacc[r][c] = acc[r][c] + a_in * b_in; na[r][c] = a_in; nb[r][c] = b_in
        a_reg, b_reg, acc = na, nb, nacc
    for beat in beats: step(struct.unpack('8b', beat[:8]), struct.unpack('8b', beat[8:16]))
    for _ in range(N - 1): step([0] * N, [0] * N)
    return acc

def run_matmul(payload, M, Nn, K, relu, mul, shift, zp, bias_stream):
    mt, nt = -(-M // N), -(-Nn // N)
    pre = 32 if bias_stream else 0
    per = pre + (K + N - 1) * 16
    if len(payload) != mt * nt * per: raise ValueError('matmul payload size')
    out = [[0] * Nn for _ in range(M)]; pos = 0
    for tm in range(mt):
        for tn in range(nt):
            blk = payload[pos:pos + per]; pos += per
            bias = list(struct.unpack('<8i', blk[:32])) if bias_stream else [0] * N
            beats = [blk[pre + i * 16: pre + (i + 1) * 16] for i in range(K + N - 1)]
            acc = array_tile(beats)
            for r in range(N):
                for c in range(N):
                    row, col = tm * N + r, tn * N + c
                    if row < M and col < Nn:
                        out[row][col] = requant(acc[r][c] + bias[c], mul, shift, relu, zp)
    return [v for row in out for v in row]

def run_conv(payload, relu, mul, shift, zp):
    outs = []; acc = 0; bias = 0; first = True
    for i in range(0, len(payload), 16):
        w, b = struct.unpack_from('<Ii', payload, i)
        a = struct.unpack('b', bytes([w & 0xFF]))[0]; wt = struct.unpack('b', bytes([(w >> 8) & 0xFF]))[0]
        if first: acc = 0; bias = b; first = False
        acc += a * wt
        if (w >> 16) & 1:
            outs.append(requant(acc + bias, mul, shift, relu, zp)); first = True
    return outs

def run_pool(payload):
    v = [struct.unpack_from('b', payload, i)[0] for i in range(0, len(payload), 16)]
    return [max(v[i:i + 4]) for i in range(0, len(v), 4)]

def run_add(payload, relu):
    out = []
    for i in range(0, len(payload), 16):
        a, b = struct.unpack_from('bb', payload, i); s = a + b
        if relu and s < 0: s = 0
        out.append(sat8(s))
    return out

class Handler(socketserver.BaseRequestHandler):
    def recv(self, n):
        buf = bytearray()
        while len(buf) < n:
            x = self.request.recv(n - len(buf))
            if not x: raise ConnectionError
            buf += x
        return bytes(buf)
    def reply(self, rid, status, body=b''):
        self.request.sendall(REP.pack(b'SNPR', rid, status, len(body)) + body)
    def handle(self):
        self.server.requests = getattr(self.server, 'requests', [])
        try:
            while True:
                (magic, ver, op, M, Nn, K, flags, mul, shift, zp, _r, inb, outb, rid) = REQ.unpack(self.recv(REQ.size))
                if magic != b'SNPU' or ver != 1: self.reply(rid, -10); return
                if op == 0:
                    if inb or outb: self.reply(rid, -11); return
                    self.reply(rid, 0, struct.pack('!7I', 0x00020000, CAPS, 0, 0, 0, 0, 0)); continue
                relu = bool(flags & 1); bias = bool(flags & 2)
                bad = (flags & ~3) or (bias and op != 1) or op < 1 or op > 4 or not inb or not outb or \
                      inb > BUF or outb > BUF or shift > 63 or inb & 15 or outb & 3 or (op == 1 and not (M and Nn and K))
                if bad: self.reply(rid, -11); return
                payload = self.recv(inb)
                self.server.requests.append((op, M, Nn, K, inb, outb))
                try:
                    if op == 1:
                        per = (32 if bias else 0) + (K + 7) * 16
                        if (-(-M // 8)) * (-(-Nn // 8)) * per != inb or M * Nn * 4 != outb: self.reply(rid, -12); return
                        res = run_matmul(payload, M, Nn, K, relu, mul, shift, zp, bias)
                    elif op == 2:
                        res = run_conv(payload, relu, mul, shift, zp)
                        if len(res) * 4 != outb or struct.unpack_from('<I', payload, inb - 16)[0] >> 16 & 1 == 0:
                            self.reply(rid, -13); return
                    elif op == 3:
                        if inb != outb * 16: self.reply(rid, -12); return
                        res = run_pool(payload)
                    else:
                        if inb != outb * 4: self.reply(rid, -12); return
                        res = run_add(payload, relu)
                except ValueError:
                    self.reply(rid, -12); return
                self.reply(rid, 0, b''.join(struct.pack('<i', v) for v in res))
        except (ConnectionError, OSError):
            return

class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True; daemon_threads = True

def start(port=0):
    srv = Server(('127.0.0.1', port), Handler); srv.requests = []
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv

if __name__ == '__main__':
    import sys
    s = start(int(sys.argv[1]) if len(sys.argv) > 1 else 9505)
    print('emulator on 127.0.0.1:%d' % s.server_address[1]); threading.Event().wait()
