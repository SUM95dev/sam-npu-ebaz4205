# SNPU model package v2

The project includes a deliberately small custom `.snpu` package format. It is
intended as a stable intermediate format for the ARM runtime, not as a claim of
a full ONNX/TFLite compiler.

Header:
- magic: four bytes `SNPU`
- little-endian `uint16` version (`2` in this release)
- little-endian `uint16` layer count

Supported layer records:
- MatMul/Dense
- Conv2D
- grouped Conv2D and depthwise Conv2D (`groups`)
- ReLU
- MaxPool2x2
- elementwise/residual Add

`sw/model_packer.py` writes v2 packages. `sw/onnx_to_snpu.py` performs a strict
conversion for the supported ONNX subset and rejects unsupported operators or
ambiguous quantization cases rather than silently producing a wrong model.

## Network Conv stream contract

The integrated network Conv path uses one 128-bit AXI beat per MAC sample:
- bits `[7:0]`: signed INT8 activation
- bits `[15:8]`: signed INT8 weight
- bit `16`: last MAC sample for this output scalar
- bits `[63:32]`: signed INT32 bias, meaningful on the first beat of each output scalar
- AXI `TLAST`: only on the final beat of the complete Conv job

This format lets the same streaming hardware execute normal, grouped and
depthwise Conv. Group selection/window expansion is performed by the host/ARM
packer; the hardware consumes the resulting dot-product stream.

## Network MatMul / Dense bias stream contract

MatMul/Dense bias is integrated without exposing the internal 2048-bit bias bus
in the block design. When CONTROL bit4 (`MATMUL_BIAS_STREAM`) is set, each 8x8
output tile starts with a 32-byte bias preamble:

- two 128-bit AXI beats
- eight little-endian signed INT32 values, one per output column of the tile
- columns outside a partial final N tile are padded with zero
- the same column-bias vector is repeated for each M tile, matching normal Dense
  bias semantics
- after the 32-byte preamble, the usual `K+7` 128-bit skewed A/B feed beats
  follow

With bit4 clear, the legacy no-bias MatMul stream is byte-for-byte unchanged.
The integrated EBAZ wrapper keeps its wide legacy `bias_flat` input tied to zero;
streamed column bias is selected internally when bit4 is enabled. Arbitrary
per-element MxN bias matrices are not a network protocol feature; the supported
form is the usual one INT32 bias per output column.

## Strict packaging rules

`model_packer.py` rejects malformed dimensions, incorrect weight/bias counts,
out-of-range INT8 weights and out-of-range INT32 biases. `snpu_inspect.py` can
parse and structurally validate a package before deployment. The ONNX converter
uses shape inference and intentionally rejects floating-point weights; it is not
a hidden quantizer. Quantization/scales must be chosen explicitly before this
conversion stage.


## Version 3 (REVIEW51): per-layer quantization and skip-Add

Version 3 is written automatically by `model_packer.py` when any layer carries
`qmul`, `qshift`, `zero_point`, `relu` or (for Add) `src`; otherwise a v2 file is
produced exactly as before. Differences from v2:

- MatMul and Conv2D records: after the opcode byte, a 7-byte quantization block
  `<i B b B` = int32 `qmul`, uint8 `qshift` (0..63), int8 `zero_point`, uint8 flags (bit0 = fused ReLU).
  Requantization is `sat8(((acc+bias)*qmul >> qshift) [ReLU] + zero_point)`, floor shift, per tensor.
- Add record: `<B h B` = opcode, int16 `src` (-1 = model input, otherwise the index of an earlier
  layer whose output is the second operand; the first operand is the previous layer's output), flags (bit0 = ReLU).
- ReLU and MaxPool2x2 records are unchanged. A v2 Add has no operand reference and is rejected by the runtime.

## Runtime (`sw/host/npu_runtime.py`)

`python3 sw/host/npu_runtime.py model.snpu input.json --host 192.168.50.2` runs a model on the board;
`--soft` runs the bit-exact software reference. Activations are NHWC. Conv runs either on the streaming
MAC engine or, via host im2col, as MatMul on the 8x8 array (`--conv-mode auto|stream|matmul`).
`sw/host/npu_emulator.py` emulates the TCP server and the RTL data path for board-less testing.
Standalone ReLU is host-side max(x,0); MaxPool windows and skip-Add operands are gathered on the host.
