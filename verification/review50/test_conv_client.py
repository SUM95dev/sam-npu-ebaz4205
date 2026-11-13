import unittest
from unittest.mock import patch
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "sw" / "host"))
import npu_net_client as client

class ConvClientTests(unittest.TestCase):
    def test_conv_nhwc_uses_correct_opcode_and_output_size(self):
        with patch.object(client.NpuSession, "request", return_value=(b"\x05\x00\x00\x00")) as req:
            session = client.NpuSession("127.0.0.1")
            values, shape = session.conv_nhwc(
                [[[2]]], [[[[3]]]], bias=[0]
            )
        self.assertEqual(shape, (1, 1, 1))
        self.assertEqual(values, [5])
        args, kwargs = req.call_args
        self.assertEqual(args[0], client.OP_CONV)
        self.assertEqual(kwargs["out_bytes"], 4)
        self.assertEqual(len(kwargs["payload"]), 16)

    def test_grouped_conv_shape(self):
        inp = [[[1, 2], [3, 4]], [[5, 6], [7, 8]]]
        weights = [[[[1]]], [[[1]]]]
        payload, shape = client.pack_conv_nhwc(inp, weights, groups=2)
        self.assertEqual(shape, (2, 2, 2))
        self.assertEqual(len(payload), 2 * 2 * 2 * 16)

    def test_conv_invalid_accumulation_rejected(self):
        inp = [[[1]]]
        weights = [[[[1] * 131072]]]
        with self.assertRaises(ValueError):
            client.pack_conv_nhwc(inp, weights)

if __name__ == "__main__":
    unittest.main(verbosity=2)
