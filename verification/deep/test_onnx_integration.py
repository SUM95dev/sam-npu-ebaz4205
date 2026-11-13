#!/usr/bin/env python3
"""Real ONNX parser/shape-inference -> converter -> packer smoke/regression tests.
Requires optional onnx/numpy. This is metadata export, not a full graph executor.
"""
import unittest,tempfile,subprocess,sys,json,importlib.util
from pathlib import Path
import onnx,numpy as np
from onnx import helper as h, TensorProto as T, numpy_helper as nh
root=Path(__file__).resolve().parents[2]
class Tests(unittest.TestCase):
 def convert(self,nodes,inputs,outputs,inits=(),ok=True,reason=''):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t);m=h.make_model(h.make_graph(nodes,'test',inputs,outputs,list(inits)),opset_imports=[h.make_opsetid('',13)])
   onnx.save(m,p/'x.onnx');r=subprocess.run([sys.executable,str(root/'sw/onnx_to_snpu.py'),str(p/'x.onnx'),'-o',str(p/'x.json')],capture_output=True,text=True)
   if not ok:self.assertNotEqual(r.returncode,0);self.assertIn(reason,r.stderr);return
   self.assertEqual(r.returncode,0,r.stderr);d=json.loads((p/'x.json').read_text())
   r=subprocess.run([sys.executable,str(root/'sw/model_packer.py'),str(p/'x.json'),'-o',str(p/'x.snpu')],capture_output=True,text=True);self.assertEqual(r.returncode,0,r.stderr)
   r=subprocess.run([sys.executable,str(root/'sw/snpu_inspect.py'),str(p/'x.snpu')],capture_output=True,text=True);self.assertEqual(r.returncode,0,r.stderr);return d
 def pool(self,**attrs):
  return [h.make_node('MaxPool',['x'],['y'],kernel_shape=[2,2],**attrs)],[h.make_tensor_value_info('x',T.INT8,[1,1,4,4])],[h.make_tensor_value_info('y',T.INT8,[1,1,2,2])]
 def test_matmul_roundtrip(self):
  d=self.convert([h.make_node('MatMul',['x','w'],['y'])],[h.make_tensor_value_info('x',T.INT8,[2,3])],[h.make_tensor_value_info('y',T.INT8,[2,4])],[nh.from_array(np.arange(12,dtype=np.int8).reshape(3,4),'w')]);self.assertEqual(d['layers'][0]['weights'],list(range(12)))
 def test_float_weights_rejected(self):
  self.convert([h.make_node('MatMul',['x','w'],['y'])],[h.make_tensor_value_info('x',T.FLOAT,[2,3])],[h.make_tensor_value_info('y',T.FLOAT,[2,4])],[nh.from_array(np.ones((3,4),dtype=np.float32),'w')],ok=False,reason='will not silently quantize')
 def test_pool_explicit_stride(self):self.convert(*self.pool(strides=[2,2]))
 def test_pool_default_stride_rejected(self):self.convert(*self.pool(),ok=False,reason='Only MaxPool 2x2 stride2')
 def test_pool_autopad_rejected(self):self.convert(*self.pool(strides=[2,2],auto_pad='SAME_UPPER'),ok=False,reason='auto_pad is unsupported')
 def test_pool_ceil_rejected(self):self.convert(*self.pool(strides=[2,2],ceil_mode=1),ok=False,reason='ceil_mode/storage_order')
 def test_conv_weight_order(self):
  w=np.arange(8,dtype=np.int8).reshape(2,1,2,2)
  d=self.convert([h.make_node('Conv',['x','w'],['y'])],[h.make_tensor_value_info('x',T.INT8,[1,1,3,3])],[h.make_tensor_value_info('y',T.INT8,[1,2,2,2])],[nh.from_array(w,'w')]);self.assertEqual(d['layers'][0]['weights'],np.transpose(w,(0,2,3,1)).reshape(-1).tolist())
 def test_conv_dynamic_bias_rejected(self):
  self.convert([h.make_node('Conv',['x','w','b'],['y'])],[h.make_tensor_value_info('x',T.INT8,[1,1,3,3]),h.make_tensor_value_info('b',T.INT32,[1])],[h.make_tensor_value_info('y',T.INT8,[1,1,3,3])],[nh.from_array(np.ones((1,1,1,1),dtype=np.int8),'w')],ok=False,reason='requires constant bias')
if __name__=='__main__':unittest.main(verbosity=2)
