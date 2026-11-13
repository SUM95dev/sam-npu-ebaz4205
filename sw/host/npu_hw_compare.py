#!/usr/bin/env python3
"""Compare real NPU (over TCP) against the bit-exact soft reference.
usage: python3 npu_hw_compare.py HOST [port]"""
import os, random, sys
sys.path[:0] = [os.path.dirname(os.path.abspath(__file__)), os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')]
import npu_net_client as cli, npu_runtime as rt
R = random.Random(7)
def rnd(n): return [R.randint(-128, 127) for _ in range(n)]
host = sys.argv[1]; port = int(sys.argv[2]) if len(sys.argv) > 2 else 9505
soft = rt.SoftBackend(); net = rt.NetBackend(cli.NpuSession(host, port, timeout=60))
bad = 0
def check(name, a, b):
    global bad
    ok = a == b; bad += (not ok); print('PASS' if ok else 'FAIL', name)
for (M, N, K) in [(8, 8, 8), (9, 9, 7), (16, 24, 40), (64, 64, 128), (33, 17, 100)]:
    A = [rnd(K) for _ in range(M)]; B = [rnd(N) for _ in range(K)]
    for use_bias in (False, True):
        bias = [R.randint(-5000, 5000) for _ in range(N)] if use_bias else None
        qp = (R.randint(1, 1000), R.randint(0, 20), R.randint(-20, 20), R.random() < .5)
        check('matmul %dx%dx%d bias=%s' % (M, N, K, use_bias), net.matmul(A, B, bias, qp), soft.matmul(A, B, bias, qp))
cases = [(5, 5, 3, 4, 1, 3, 3, 1, 1), (6, 5, 4, 4, 4, 3, 3, 2, 1), (8, 8, 8, 16, 1, 3, 3, 1, 1)]
for (H, W, C, O, G, Kh, Kw, S, P) in cases:
    Cpg = C // G
    inp = [[[R.randint(-128, 127) for _ in range(C)] for _ in range(W)] for _ in range(H)]
    w = [[[[R.randint(-128, 127) for _ in range(Cpg)] for _ in range(Kw)] for _ in range(Kh)] for _ in range(O)]
    bias = [R.randint(-999, 999) for _ in range(O)]; qp = (3, 12, 0, False)
    try:
        check('conv_stream H%dW%dC%dO%dG%d' % (H, W, C, O, G), net.conv_stream(inp, w, S, P, G, bias, qp), soft.conv_stream(inp, w, S, P, G, bias, qp))
    except Exception as e:
        bad += 1; print('FAIL conv', e)
print('ALL MATCH' if not bad else '%d MISMATCHES' % bad)
