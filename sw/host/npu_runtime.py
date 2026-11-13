#!/usr/bin/env python3
"""Multi-layer SNPU model runtime.

Executes a .snpu (v2/v3) model layer by layer on either
  * NetBackend  - the EBAZ4205 TCP accelerator (MatMul/Conv/MaxPool/Add ops), or
  * SoftBackend - a bit-exact pure-Python reference of the hardware arithmetic.

Tensors are (flat_list, shape). Activations are NHWC; MatMul layers see a
(M,K) matrix; Conv layers see (H,W,C). Standalone ReLU is done on the host
(max(x,0)); MaxPool2x2 windows and skip-Add operands are gathered on the host.
Conv can run on the streaming MAC engine (1 MAC/cycle) or be lowered to MatMul
(im2col) so that the 8x8 systolic array does the work; 'auto' picks the
estimated-cheaper path. Both paths are bit-identical.
"""
import argparse, json, struct, sys
from pathlib import Path
_SW = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(_SW)); sys.path.insert(0, str(Path(__file__).resolve().parent))
from snpu_loader import load_snpu

LIMIT = 4 * 1024 * 1024  # server DMA buffer
TILE = 8

def _ceil(a, b): return -(-a // b)
def _sat8(v): return max(-128, min(127, v))

def requant(acc, qmul, qshift, zp, relu):
    y = (acc * qmul) >> qshift          # arithmetic (floor) shift, as in RTL
    if relu and y < 0: y = 0
    return _sat8(y + zp)

def flatten(x):
    if isinstance(x, (list, tuple)):
        out = []
        for e in x: out.extend(flatten(e))
        return out
    return [x]

# ----------------------------------------------------------------- geometry
def conv_geometry(H, W, C, O, G, Kh, Kw, S, P):
    Oh = (H + 2 * P - Kh) // S + 1; Ow = (W + 2 * P - Kw) // S + 1
    if Oh <= 0 or Ow <= 0: raise ValueError('invalid convolution geometry')
    return Oh, Ow

def _nhwc(flat, H, W, C):
    return [[[flat[(y * W + x) * C + c] for c in range(C)] for x in range(W)] for y in range(H)]

def _ohwi(flat, O, Kh, Kw, Cpg):
    return [[[[flat[((o * Kh + ky) * Kw + kx) * Cpg + c] for c in range(Cpg)]
              for kx in range(Kw)] for ky in range(Kh)] for o in range(O)]

def im2col_group(inp, Kh, Kw, S, P, Oh, Ow, ic0, Cpg):
    H = len(inp); W = len(inp[0]); rows = []
    for oy in range(Oh):
        for ox in range(Ow):
            r = []
            for ky in range(Kh):
                iy = oy * S + ky - P
                for kx in range(Kw):
                    ix = ox * S + kx - P
                    if 0 <= iy < H and 0 <= ix < W: r.extend(inp[iy][ix][ic0:ic0 + Cpg])
                    else: r.extend([0] * Cpg)
            rows.append(r)
    return rows

def weights_matrix(w, g, Opg, Kh, Kw, Cpg):
    """B[k][o], k=(ky,kx,lic), o = output channel inside group g."""
    return [[w[g * Opg + o][ky][kx][lic] for o in range(Opg)]
            for ky in range(Kh) for kx in range(Kw) for lic in range(Cpg)]

def conv_via_matmul(backend, inp, w, S, P, G, bias, qp):
    H = len(inp); W = len(inp[0]); C = len(inp[0][0]); O = len(w)
    Kh = len(w[0]); Kw = len(w[0][0]); Cpg = C // G; Opg = O // G
    Oh, Ow = conv_geometry(H, W, C, O, G, Kh, Kw, S, P)
    out = [0] * (Oh * Ow * O)
    for g in range(G):
        A = im2col_group(inp, Kh, Kw, S, P, Oh, Ow, g * Cpg, Cpg)
        B = weights_matrix(w, g, Opg, Kh, Kw, Cpg)
        bg = bias[g * Opg:(g + 1) * Opg] if bias is not None else None
        res = backend.matmul(A, B, bg, qp)                  # (Oh*Ow) x Opg row-major
        for pos in range(Oh * Ow):
            base = pos * O + g * Opg
            out[base:base + Opg] = res[pos * Opg:(pos + 1) * Opg]
    return out, (Oh, Ow, O)

# ----------------------------------------------------------------- backends
class SoftBackend:
    name = 'soft'
    def matmul(self, A, B, bias, qp):
        qm, qs, zp, relu = qp; M = len(A); K = len(A[0]); N = len(B[0]); out = []
        for i in range(M):
            for j in range(N):
                s = sum(A[i][k] * B[k][j] for k in range(K)) + (bias[j] if bias else 0)
                out.append(requant(s, qm, qs, zp, relu))
        return out
    def conv_stream(self, inp, w, S, P, G, bias, qp):
        qm, qs, zp, relu = qp
        H = len(inp); W = len(inp[0]); C = len(inp[0][0]); O = len(w)
        Kh = len(w[0]); Kw = len(w[0][0]); Cpg = C // G; Opg = O // G
        Oh, Ow = conv_geometry(H, W, C, O, G, Kh, Kw, S, P); out = []
        for oy in range(Oh):
            for ox in range(Ow):
                for oc in range(O):
                    g = oc // Opg; s = bias[oc] if bias else 0
                    for ky in range(Kh):
                        for kx in range(Kw):
                            iy = oy * S + ky - P; ix = ox * S + kx - P
                            if 0 <= iy < H and 0 <= ix < W:
                                for l in range(Cpg): s += inp[iy][ix][g * Cpg + l] * w[oc][ky][kx][l]
                    out.append(requant(s, qm, qs, zp, relu))
        return out, (Oh, Ow, O)
    def pool(self, groups): return [max(g) for g in groups]
    def add(self, a, b, relu):
        out = []
        for x, y in zip(a, b):
            z = x + y
            if relu and z < 0: z = 0
            out.append(_sat8(z))
        return out

class NetBackend:
    name = 'net'
    def __init__(self, session, limit=LIMIT):
        import npu_net_client as cli
        self.cli = cli; self.s = session; self.limit = limit
    def _req(self, op, payload, out_n, qp, M=0, N=0, K=0, bias=False):
        qm, qs, zp, relu = qp
        raw = self.s.request(op, M, N, K, payload, out_n * 4, relu=relu, qmul=qm, qshift=qs, zp=zp,
                             extra_flags=self.cli.FLAG_MATMUL_BIAS if bias else 0)
        return self.cli.decode_i8_words(raw)
    def matmul(self, A, B, bias, qp):
        M = len(A); K = len(A[0]); N = len(B[0])
        per_tile = (K + TILE - 1) * 16 + (32 if bias else 0)
        cols = N
        while _ceil(cols, TILE) * per_tile > self.limit and cols > TILE:
            cols = max(TILE, (cols // 2 + TILE - 1) // TILE * TILE)
        nt = _ceil(cols, TILE)
        if nt * per_tile > self.limit: raise ValueError('matmul K too large for one DMA buffer')
        row_tiles = min(self.limit // (nt * per_tile), self.limit // (4 * TILE * cols), 65528 // TILE)
        if row_tiles < 1: raise ValueError('matmul chunk does not fit DMA buffer')
        rows = row_tiles * TILE
        out = [0] * (M * N)
        for n0 in range(0, N, cols):
            n1 = min(N, n0 + cols)
            Bc = [r[n0:n1] for r in B]
            bc = bias[n0:n1] if bias else None
            for m0 in range(0, M, rows):
                m1 = min(M, m0 + rows)
                payload, (mm, nn, kk) = self.cli.pack_matmul(A[m0:m1], Bc, bias=bc)
                res = self._req(self.cli.OP_MATMUL, payload, mm * nn, qp, mm, nn, kk, bias=bc is not None)
                for i in range(mm):
                    out[(m0 + i) * N + n0:(m0 + i) * N + n1] = res[i * nn:(i + 1) * nn]
        return out
    def conv_stream(self, inp, w, S, P, G, bias, qp):
        from pack_conv_stream import pack_conv_nhwc
        H = len(inp); W = len(inp[0]); C = len(inp[0][0]); O = len(w)
        Kh = len(w[0]); Kw = len(w[0][0]); Cpg = C // G
        Oh, Ow = conv_geometry(H, W, C, O, G, Kh, Kw, S, P)
        zero = [0] * C
        padded = [[zero] * (W + 2 * P) for _ in range(P)] + \
                 [[zero] * P + row + [zero] * P for row in inp] + \
                 [[zero] * (W + 2 * P) for _ in range(P)]
        per_row = Ow * O * Kh * Kw * Cpg * 16
        rows = min(self.limit // per_row if per_row else Oh, self.limit // (Ow * O * 4))
        if rows < 1: raise ValueError('one conv output row does not fit the DMA buffer')
        out = []
        for r0 in range(0, Oh, rows):
            r1 = min(Oh, r0 + rows)
            sub = padded[r0 * S: (r1 - 1) * S + Kh]
            payload, shape = pack_conv_nhwc(sub, w, stride=S, pad=0, groups=G, bias=bias)
            assert shape == (r1 - r0, Ow, O), shape
            out.extend(self._req(self.cli.OP_CONV, payload, shape[0] * shape[1] * shape[2], qp))
        return out, (Oh, Ow, O)
    def pool(self, groups):
        out = []; step = min(self.limit // 64, self.limit // 4)
        for i in range(0, len(groups), step):
            part = groups[i:i + step]
            out.extend(self._req(self.cli.OP_MAXPOOL, self.cli.pack_pool_groups(part), len(part), (1, 0, 0, False)))
        return out
    def add(self, a, b, relu):
        out = []; step = self.limit // 16
        for i in range(0, len(a), step):
            pa, pb = a[i:i + step], b[i:i + step]
            out.extend(self._req(self.cli.OP_ADD, self.cli.pack_add(pa, pb), len(pa), (1, 0, 0, relu)))
        return out

# ----------------------------------------------------------------- runtime
class Runtime:
    def __init__(self, backend, conv_mode='auto'):
        if conv_mode not in ('auto', 'stream', 'matmul'): raise ValueError('conv_mode')
        self.b = backend; self.conv_mode = conv_mode; self.log = []

    def _pick_conv(self, P, O, G, Kc):
        if self.conv_mode != 'auto': return self.conv_mode
        Opg = O // G
        if Kc > 65535 or P > 65535 * 64: return 'stream'
        stream = P * O * (Kc + 8)
        mm = G * _ceil(P, TILE) * _ceil(Opg, TILE) * (Kc + 222)
        return 'matmul' if mm < stream else 'stream'

    def run(self, model, x, shape=None):
        layers = model['layers'] if isinstance(model, dict) else model
        flat = [int(v) for v in flatten(x)]
        if shape is None:
            L0 = layers[0]
            shape = (L0['in_h'], L0['in_w'], L0['in_c']) if L0['type'] == 'conv2d' else \
                    (L0['M'], L0['K']) if L0['type'] == 'matmul' else (len(flat),)
        if any(v < -128 or v > 127 for v in flat): raise ValueError('input must be INT8')
        cur = (flat, tuple(shape)); outs = []; inp = cur
        for idx, L in enumerate(layers):
            t = L['type']; v, sh = cur
            if t == 'matmul':
                M, N, K = L['M'], L['N'], L['K']
                if len(v) != M * K: raise ValueError(f'layer {idx}: matmul expects {M*K} values, got {len(v)}')
                A = [v[i * K:(i + 1) * K] for i in range(M)]
                w = L['weights']; B = [w[k * N:(k + 1) * N] for k in range(K)]
                bias = L['bias'] if any(L['bias']) else None
                qp = (L['qmul'], L['qshift'], L['zero_point'], L['relu'])
                cur = (self.b.matmul(A, B, bias, qp), (M, N))
            elif t == 'conv2d':
                H, W, C, O, G = L['in_h'], L['in_w'], L['in_c'], L['out_c'], L['groups']
                Kh, Kw, S, P = L['k_h'], L['k_w'], L['stride'], L['pad']
                if len(v) != H * W * C: raise ValueError(f'layer {idx}: conv expects {H*W*C} values, got {len(v)}')
                img = _nhwc(v, H, W, C); w = _ohwi(L['weights'], O, Kh, Kw, C // G)
                bias = L['bias'] if any(L['bias']) else None
                qp = (L['qmul'], L['qshift'], L['zero_point'], L['relu'])
                Oh, Ow = conv_geometry(H, W, C, O, G, Kh, Kw, S, P)
                mode = self._pick_conv(Oh * Ow, O, G, Kh * Kw * (C // G))
                self.log.append((idx, 'conv', mode))
                if mode == 'matmul': res, osh = conv_via_matmul(self.b, img, w, S, P, G, bias, qp)
                else: res, osh = self.b.conv_stream(img, w, S, P, G, bias, qp)
                cur = (res, osh)
            elif t == 'relu':
                cur = ([max(0, e) for e in v], sh)
            elif t == 'maxpool2':
                if len(sh) != 3: raise ValueError(f'layer {idx}: maxpool needs an (H,W,C) tensor')
                H, W, C = sh; Oh, Ow = H // 2, W // 2
                if not (Oh and Ow): raise ValueError(f'layer {idx}: maxpool input too small')
                g = [[v[((2 * y + dy) * W + (2 * x + dx)) * C + c] for dy in (0, 1) for dx in (0, 1)]
                     for y in range(Oh) for x in range(Ow) for c in range(C)]
                cur = (self.b.pool(g), (Oh, Ow, C))
            elif t == 'add':
                if L['src'] is None: raise ValueError(f'layer {idx}: v2 Add has no operand reference; repack as v3 with src')
                other = inp if L['src'] == -1 else outs[L['src']]
                if len(other[0]) != len(v):
                    raise ValueError(f'layer {idx}: add operand shape mismatch {other[1]} vs {sh}')
                cur = (self.b.add(v, other[0], L['relu']), sh)
            else:
                raise ValueError(f'layer {idx}: unsupported {t}')
            outs.append(cur)
        return cur

def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('model'); ap.add_argument('input_json')
    ap.add_argument('--host'); ap.add_argument('--port', type=int, default=9505)
    ap.add_argument('--soft', action='store_true'); ap.add_argument('--conv-mode', default='auto')
    ap.add_argument('-o', '--output')
    a = ap.parse_args()
    d = json.load(open(a.input_json)); x = d['input'] if isinstance(d, dict) else d
    if a.soft: be = SoftBackend()
    elif a.host:
        import npu_net_client as cli
        be = NetBackend(cli.NpuSession(a.host, a.port, timeout=30))
    else: ap.error('give --host IP or --soft')
    rt = Runtime(be, a.conv_mode)
    out, shape = rt.run(load_snpu(a.model), x, d.get('shape') if isinstance(d, dict) else None)
    print('shape', shape); print('output', out)
    if a.output: json.dump({'shape': list(shape), 'output': out}, open(a.output, 'w'))
if __name__ == '__main__': main()
