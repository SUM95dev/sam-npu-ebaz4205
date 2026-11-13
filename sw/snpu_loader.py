#!/usr/bin/env python3
"""Load SNPU v2/v3 packages into executable layer dictionaries (weights included)."""
import struct
from snpu_inspect import inspect, MAGIC

def _take(data, off, fmt):
    st = struct.Struct(fmt)
    return st.unpack_from(data, off), off + st.size

def load_snpu(path):
    inspect(path)  # strict structural validation first (raises ValueError)
    with open(path, 'rb') as f: data = f.read()
    (ver, n), off = _take(data, 4, '<HH')
    q3 = ver == 3
    layers = []
    for idx in range(n):
        (op,), off = _take(data, off, '<B')
        q = {'qmul': 1, 'qshift': 0, 'zero_point': 0, 'relu': False}
        if q3 and op in (1, 2):
            (qm, qs, zp, fl), off = _take(data, off, '<iBbB')
            q = {'qmul': qm, 'qshift': qs, 'zero_point': zp, 'relu': bool(fl)}
        if op == 1:
            (M, N, K), off = _take(data, off, '<HHH')
            (nw,), off = _take(data, off, '<I')
            w = list(struct.unpack_from(f'<{nw}b', data, off)); off += nw
            (nb,), off = _take(data, off, '<I')
            b = list(struct.unpack_from(f'<{nb}i', data, off)); off += 4 * nb
            layers.append(dict(type='matmul', M=M, N=N, K=K, weights=w, bias=b, **q))
        elif op == 2:
            (H, W, C, O, G, Kh, Kw, S, P), off = _take(data, off, '<HHHHHBBBB')
            (nw,), off = _take(data, off, '<I')
            w = list(struct.unpack_from(f'<{nw}b', data, off)); off += nw
            (nb,), off = _take(data, off, '<I')
            b = list(struct.unpack_from(f'<{nb}i', data, off)); off += 4 * nb
            layers.append(dict(type='conv2d', in_h=H, in_w=W, in_c=C, out_c=O, groups=G,
                               k_h=Kh, k_w=Kw, stride=S, pad=P, weights=w, bias=b, **q))
        elif op == 3:
            layers.append(dict(type='relu'))
        elif op == 4:
            layers.append(dict(type='maxpool2'))
        elif op == 5:
            if q3:
                (src, fl), off = _take(data, off, '<hB')
                layers.append(dict(type='add', src=src, relu=bool(fl)))
            else:
                layers.append(dict(type='add', src=None, relu=False))
    return {'version': ver, 'layers': layers}
