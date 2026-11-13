#!/usr/bin/env python3
"""Runtime/emulator tests: net path (protocol + packers + emulated RTL) vs bit-exact soft reference."""
import os, random, sys, tempfile, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / 'sw'), str(ROOT / 'sw' / 'host')]
import npu_emulator as emu, npu_net_client as cli, npu_runtime as rt
import model_packer, snpu_loader, golden_model

R = random.Random(12345)
def rnd(n): return [R.randint(-128, 127) for _ in range(n)]
def small(n): return [R.randint(-8, 8) for _ in range(n)]

class T(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srv = emu.start(); cls.port = cls.srv.server_address[1]
    @classmethod
    def tearDownClass(cls): cls.srv.shutdown()
    def net(self, limit=rt.LIMIT):
        return rt.NetBackend(cli.NpuSession('127.0.0.1', self.port, timeout=60), limit=limit)

    def test_info(self):
        info = cli.parse_info(cli.request('127.0.0.1', self.port, cli.OP_INFO))
        self.assertEqual((info['array_n'], info['data_w'], info['acc_w']), (8, 8, 32))

    def test_matmul_matches_soft(self):
        soft, net = rt.SoftBackend(), self.net()
        for (M, N, K) in [(1, 1, 1), (3, 5, 4), (9, 9, 7), (8, 8, 8), (13, 3, 10)]:
            A = [rnd(K) for _ in range(M)]; B = [rnd(N) for _ in range(K)]
            for bias in (None, [R.randint(-5000, 5000) for _ in range(N)]):
                qp = (R.randint(1, 1000), R.randint(0, 20), R.randint(-20, 20), R.random() < .5)
                self.assertEqual(net.matmul(A, B, bias, qp), soft.matmul(A, B, bias, qp), (M, N, K, bias is not None))

    def test_matmul_chunking(self):
        A = [rnd(5) for _ in range(30)]; B = [rnd(21) for _ in range(5)]; bias = [R.randint(-99, 99) for _ in range(21)]
        qp = (3, 4, 1, False)
        full = rt.SoftBackend().matmul(A, B, bias, qp)
        self.srv.requests.clear()
        got = self.net(limit=600).matmul(A, B, bias, qp)   # forces row and column chunks
        self.assertEqual(got, full); self.assertGreater(len(self.srv.requests), 4)

    def test_conv_modes_equal_soft_and_golden(self):
        soft, net = rt.SoftBackend(), self.net()
        cases = [(5, 5, 3, 4, 1, 3, 3, 1, 1), (6, 5, 4, 4, 4, 3, 3, 2, 1), (4, 4, 2, 6, 2, 1, 1, 1, 0), (7, 7, 1, 9, 1, 3, 3, 2, 0)]
        for (H, W, C, O, G, Kh, Kw, S, P) in cases:
            img = rt._nhwc(small(H * W * C), H, W, C); w = rt._ohwi(small(O * Kh * Kw * (C // G)), O, Kh, Kw, C // G)
            bias = [R.randint(-300, 300) for _ in range(O)]; qp = (5, 3, 2, True)
            ref, shp = soft.conv_stream(img, w, S, P, G, bias, qp)
            # independent cross-check against the pre-existing golden model
            g = golden_model.conv2d_grouped(img, w, bias, S, P, G)
            gflat = [golden_model.requant(v, 0, 5, 3, True, 2) for row in g for px in row for v in px]
            self.assertEqual(ref, gflat, 'soft conv vs golden_model')
            self.assertEqual(net.conv_stream(img, w, S, P, G, bias, qp)[0], ref, 'stream conv')
            self.assertEqual(rt.conv_via_matmul(net, img, w, S, P, G, bias, qp), (ref, shp), 'conv via 8x8 array')
            self.assertEqual(rt.conv_via_matmul(soft, img, w, S, P, G, bias, qp), (ref, shp))

    def test_conv_stream_chunking(self):
        img = rt._nhwc(small(9 * 9 * 2), 9, 9, 2); w = rt._ohwi(small(3 * 3 * 3 * 2), 3, 3, 3, 2)
        qp = (1, 0, 0, False); ref = rt.SoftBackend().conv_stream(img, w, 1, 1, 1, None, qp)
        self.assertEqual(self.net(limit=8000).conv_stream(img, w, 1, 1, 1, None, qp), ref)

    def test_pool_add(self):
        soft, net = rt.SoftBackend(), self.net()
        g = [[R.randint(-128, 127) for _ in range(4)] for _ in range(37)]
        self.assertEqual(net.pool(g), soft.pool(g))
        a, b = rnd(50), rnd(50)
        for relu in (False, True): self.assertEqual(net.add(a, b, relu), soft.add(a, b, relu))
        self.assertEqual(self.net(limit=256).add(a, b, True), soft.add(a, b, True))

    def test_full_model_v3(self):
        layers = [
            {'type': 'conv2d', 'in_h': 8, 'in_w': 8, 'in_c': 3, 'out_c': 8, 'k_h': 3, 'k_w': 3, 'stride': 1, 'pad': 1,
             'weights': small(8 * 9 * 3), 'bias': [R.randint(-50, 50) for _ in range(8)], 'qmul': 3, 'qshift': 5, 'zero_point': 0, 'relu': True},
            {'type': 'maxpool2'},
            {'type': 'conv2d', 'in_h': 4, 'in_w': 4, 'in_c': 8, 'out_c': 8, 'groups': 8, 'k_h': 3, 'k_w': 3, 'stride': 1, 'pad': 1,
             'weights': small(8 * 9), 'bias': [0] * 8, 'qmul': 7, 'qshift': 4, 'zero_point': -3, 'relu': False},
            {'type': 'add', 'src': 1, 'relu': True},
            {'type': 'relu'},
            {'type': 'matmul', 'M': 1, 'N': 5, 'K': 4 * 4 * 8, 'weights': small(128 * 5), 'bias': [10, -20, 30, 0, 5],
             'qmul': 9, 'qshift': 6, 'zero_point': 2, 'relu': False},
        ]
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, 'm.snpu'); model_packer.pack_model({'layers': layers}, path)
            model = snpu_loader.load_snpu(path)
        self.assertEqual(model['version'], 3)
        x = small(8 * 8 * 3)
        ref = rt.Runtime(rt.SoftBackend(), 'stream').run(model, x)
        self.assertEqual(ref[1], (1, 5))
        for mode in ('stream', 'matmul', 'auto'):
            got = rt.Runtime(self.net(), mode).run(model, x)
            self.assertEqual(got, ref, mode)

    def test_v2_add_rejected_and_validation(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, 'm.snpu')
            model_packer.pack_model({'layers': [{'type': 'add'}]}, path)
            with self.assertRaises(ValueError): rt.Runtime(rt.SoftBackend()).run(snpu_loader.load_snpu(path), [1, 2], (2,))
        with self.assertRaises(ValueError): rt.Runtime(rt.SoftBackend()).run([{'type': 'matmul', 'M': 1, 'N': 1, 'K': 2, 'weights': [1, 1], 'bias': [0], 'qmul': 1, 'qshift': 0, 'zero_point': 0, 'relu': False}], [300, 1], (1, 2))

    def test_auto_prefers_array_for_wide_conv(self):
        r = rt.Runtime(rt.SoftBackend(), 'auto')
        self.assertEqual(r._pick_conv(1024, 64, 1, 288), 'matmul')
        self.assertEqual(r._pick_conv(1024, 64, 64, 9), 'stream')   # depthwise: 1 channel/group

if __name__ == '__main__': unittest.main(verbosity=2)
