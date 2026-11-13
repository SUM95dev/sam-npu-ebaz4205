#!/usr/bin/env python3
"""Run the quantized digit model on the NPU (over TCP) and compare with soft reference.
usage: python3 digits_run.py HOST [dir-with-digits-files] [--soft]"""
import json, os, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [os.path.join(HERE, '..'), os.path.join(HERE, '..', 'host')]
import npu_runtime as rt, snpu_loader
host = sys.argv[1]
d = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith('--') else HERE
model = snpu_loader.load_snpu(os.path.join(d, 'digits_demo.snpu'))
data = json.load(open(os.path.join(d, 'digits_test.json')))
B = data['batch']; X = data['x']; Y = data['y']
soft = rt.Runtime(rt.SoftBackend(), 'auto')
if '--soft' in sys.argv: net = soft
else:
    import npu_net_client as cli
    net = rt.Runtime(rt.NetBackend(cli.NpuSession(host, 9505, timeout=60)), 'auto')
ok_n = ok_s = same = 0; preds = []; t0 = time.time()
for i in range(0, len(X), B):
    flat = [v for r in X[i:i + B] for v in r]
    on, _ = net.run(model, flat, (B, 64)); os_, _ = soft.run(model, flat, (B, 64))
    for j in range(B):
        pn = max(range(10), key=lambda c: on[j * 10 + c]); ps = max(range(10), key=lambda c: os_[j * 10 + c])
        preds.append(pn); ok_n += pn == Y[i + j]; ok_s += ps == Y[i + j]; same += on[j * 10:(j + 1) * 10] == os_[j * 10:(j + 1) * 10]
n = len(X); dt = time.time() - t0
print('NPU  accuracy: %d/%d = %.2f%%' % (ok_n, n, 100.0 * ok_n / n))
print('soft accuracy: %d/%d = %.2f%%' % (ok_s, n, 100.0 * ok_s / n))
print('outputs bit-identical NPU vs soft: %d/%d samples' % (same, n))
print('float model accuracy %.2f%%, int8 numpy %.2f%%  (%.1fs total)' % (100 * data['float_acc'], 100 * data['int8_acc'], dt))
for k in (0, 1, 2):
    print('\nsample %d  true=%d  NPU says=%d' % (k, Y[k], preds[k]))
    for r in range(8): print(''.join(' .:-=+*#%@'[min(9, int(data['raw'][k][r * 8 + c] * 9 / 16))] * 2 for c in range(8)))
