#!/usr/bin/env python3
"""Train a tiny digit MLP (64-32-10) on sklearn's built-in 8x8 digits (no download),
quantize it to INT8 for the Sam NPU and write digits_demo.snpu + digits_test.json.
usage: python3 digits_train.py [outdir]"""
import json, math, os, sys
import numpy as np
from sklearn.datasets import load_digits
from sklearn.model_selection import train_test_split
from sklearn.neural_network import MLPClassifier
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))
import model_packer

out = sys.argv[1] if len(sys.argv) > 1 else HERE
BATCH = 60; XS = 7.0
d = load_digits()
Xtr, Xte, ytr, yte = train_test_split(d.data, d.target, test_size=360, random_state=0, stratify=d.target)
clf = MLPClassifier(hidden_layer_sizes=(32,), activation='relu', max_iter=800, random_state=0).fit(Xtr, ytr)
W1, W2 = clf.coefs_; b1, b2 = clf.intercepts_
print('float accuracy train=%.4f test=%.4f' % (clf.score(Xtr, ytr), clf.score(Xte, yte)))

def mq(m):
    """(qmul, qshift) with qmul in [2^12, 2^20) approximating m."""
    sh = 12 - math.floor(math.log2(m)) if m > 0 else 12
    sh = max(0, min(63, sh)); q = int(round(m * 2 ** sh))
    while q >= 2 ** 20 and sh > 0: sh -= 1; q = int(round(m * 2 ** sh))
    return q, sh

sw1 = 127.0 / np.abs(W1).max(); sw2 = 127.0 / np.abs(W2).max()
H = np.maximum(Xtr @ W1 + b1, 0); sh_ = 127.0 / H.max()
L = H @ W2 + b2; so = 127.0 / np.abs(L).max()
S1 = XS * sw1; S2 = sh_ * sw2
q1, s1 = mq(sh_ / S1); q2, s2 = mq(so / S2)
W1q = np.clip(np.round(W1 * sw1), -128, 127).astype(int); W2q = np.clip(np.round(W2 * sw2), -128, 127).astype(int)
b1q = np.round(b1 * S1).astype(int); b2q = np.round(b2 * S2).astype(int)
layers = [
 {'type': 'matmul', 'M': BATCH, 'N': 32, 'K': 64, 'weights': W1q.flatten().tolist(), 'bias': b1q.tolist(),
  'qmul': q1, 'qshift': s1, 'zero_point': 0, 'relu': True},
 {'type': 'matmul', 'M': BATCH, 'N': 10, 'K': 32, 'weights': W2q.flatten().tolist(), 'bias': b2q.tolist(),
  'qmul': q2, 'qshift': s2, 'zero_point': 0, 'relu': False}]
model_packer.pack_model({'layers': layers}, os.path.join(out, 'digits_demo.snpu'))
Xq = np.clip(np.round(Xte * XS), -128, 127).astype(int)
# int8 reference computed with plain numpy (floor shift, saturation) -> accuracy of the quantized model
def qrun(xq):
    a = xq @ W1q + b1q; h = np.clip((a * q1) >> s1, 0, 127)
    a = h @ W2q + b2q; return np.clip((a * q2) >> s2, -128, 127)
qa = (qrun(Xq).argmax(1) == yte).mean()
print('int8 (numpy) test accuracy=%.4f  (layer1 qmul=%d qshift=%d, layer2 qmul=%d qshift=%d)' % (qa, q1, s1, q2, s2))
json.dump({'batch': BATCH, 'x': Xq.tolist(), 'y': yte.tolist(), 'raw': Xte.tolist(),
           'float_acc': float(clf.score(Xte, yte)), 'int8_acc': float(qa)}, open(os.path.join(out, 'digits_test.json'), 'w'))
print('wrote digits_demo.snpu and digits_test.json in', out)
