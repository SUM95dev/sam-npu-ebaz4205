#!/usr/bin/env python3
"""Run additional host checks. --onnx opts into its optional dependencies."""
import argparse,subprocess,sys
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--onnx',action='store_true');a=p.parse_args()
root=Path(__file__).resolve().parents[2]
for name in ['test_dma_proxy.py','test_server.py','test_bd_contract.py']:
 subprocess.run([sys.executable,str(root/'verification/deep'/name)],check=True)
if a.onnx:subprocess.run([sys.executable,str(root/'verification/deep/test_onnx_integration.py')],check=True)
else:print('ONNX integration SKIPPED (use --onnx with onnx/numpy installed)')
print('PASS requested additional host checks; no board or Vivado execution implied')
