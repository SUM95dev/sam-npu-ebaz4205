import os, sys, time
import numpy as np
sys.path[:0] = [os.path.dirname(os.path.abspath(__file__)), os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')]
import npu_net_client as cli
host = sys.argv[1]; iters = int(sys.argv[2]) if len(sys.argv) > 2 else 300
rng = np.random.RandomState(11)

def ref(A, B, bias, qm, qs, zp, relu):
    acc = A.astype(np.int64) @ B.astype(np.int64)
    if bias is not None: acc = acc + bias.astype(np.int64)[None, :]
    y = (acc * qm) >> qs
    if relu: y = np.maximum(y, 0)
    return np.clip(y + zp, -128, 127)

def run(s, A, B, bias, qm, qs, zp, relu):
    M, K = A.shape; N = B.shape[1]
    payload, (m, n, k) = cli.pack_matmul(A.tolist(), B.tolist(), bias=None if bias is None else bias.tolist())
    flags = cli.FLAG_MATMUL_BIAS if bias is not None else 0
    raw = s.request(cli.OP_MATMUL, m, n, k, payload, M * N * 4, relu=relu, qmul=qm, qshift=qs, zp=zp, extra_flags=flags)
    return np.array(cli.decode_i8_words(raw), dtype=np.int64).reshape(M, N), payload, (m, n, k, flags)

bad = 0
s = cli.NpuSession(host, 9505, timeout=60)
print('--- 1) independent numpy check ---')
cases = []
for (M, N, K) in [(32, 32, 64), (64, 64, 128), (100, 100, 100), (128, 64, 256)]:
    cases.append(('rand %dx%dx%d' % (M, N, K), rng.randint(-128, 128, (M, K)), rng.randint(-128, 128, (K, N))))
cases.append(('all -128', np.full((16, 64), -128), np.full((64, 16), -128)))
cases.append(('all +127', np.full((16, 64), 127), np.full((64, 16), 127)))
cases.append(('-128 x +127', np.full((16, 64), -128), np.full((64, 16), 127)))
for name, A, B in cases:
    N = B.shape[1]
    for relu in (False, True):
        bias = rng.randint(-20000, 20000, N)
        qm = int(rng.randint(1, 2000)); qs = int(rng.randint(8, 24)); zp = int(rng.randint(-30, 30))
        got = run(s, A, B, bias, qm, qs, zp, relu)[0]
        ok = np.array_equal(got, ref(A, B, bias, qm, qs, zp, relu)); bad += not ok
        print('PASS' if ok else 'FAIL', name, 'relu=%s qm=%d qs=%d zp=%d' % (relu, qm, qs, zp))
print('--- 3) stress: %d jobs ---' % iters)
pre = []
for i in range(8):
    A = rng.randint(-128, 128, (32, 64)); B = rng.randint(-128, 128, (64, 32)); bias = rng.randint(-9999, 9999, 32)
    qm, qs, zp = int(rng.randint(1, 500)), 12, 0
    _, payload, (m, n, k, fl) = run(s, A, B, bias, qm, qs, zp, False)
    pre.append((payload, (m, n, k, fl), ref(A, B, bias, qm, qs, zp, False), qm, qs, zp))
info0 = cli.parse_info(s.request(cli.OP_INFO)); t0 = time.time(); fails = 0
for i in range(iters):
    payload, (m, n, k, fl), want, qm, qs, zp = pre[i % 8]
    raw = s.request(cli.OP_MATMUL, m, n, k, payload, 32 * 32 * 4, qmul=qm, qshift=qs, zp=zp, extra_flags=fl)
    if not np.array_equal(np.array(cli.decode_i8_words(raw), dtype=np.int64).reshape(32, 32), want):
        fails += 1; print('FAIL iter', i)
    if (i + 1) % 100 == 0: print('  %d jobs, %d fails, %.1fs' % (i + 1, fails, time.time() - t0))
info1 = cli.parse_info(s.request(cli.OP_INFO))
print('hw jobs delta=%d errors delta=%d' % ((info1['jobs'] - info0['jobs']) & 0xffffffff, (info1['errors'] - info0['errors']) & 0xffffffff))
bad += fails
print('ALL OK' if not bad else '%d FAILURES' % bad)
