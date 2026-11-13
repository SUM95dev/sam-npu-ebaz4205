#!/usr/bin/env python3
"""Behavioral checks for malformed models, numeric fidelity and TCP framing."""
import importlib.util, pathlib, struct, tempfile, unittest, sys
ROOT=pathlib.Path(sys.argv.pop(1)).resolve() if len(sys.argv)>1 and not sys.argv[1].startswith('-') else pathlib.Path(__file__).resolve().parents[2]
def load(name,path):
 s=importlib.util.spec_from_file_location(name,ROOT/path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
model=load('model','sw/model_packer.py'); inspect=load('inspect_snpu','sw/snpu_inspect.py')
mm=load('mm','sw/pack_matmul_stream.py'); cv=load('cv','sw/pack_conv_stream.py'); net=load('net','sw/host/npu_net_client.py')
onnx=load('onnx_converter','sw/onnx_to_snpu.py')
class Socket:
 def __init__(self,blob):self.blob=blob;self.closed=False
 def recv(self,n):out=self.blob[:min(n,3)];self.blob=self.blob[len(out):];return out
 def sendall(self,b):pass
 def close(self):self.closed=True
class Tests(unittest.TestCase):
 def reject(self,fn,*args):
  with self.assertRaises((ValueError,TypeError,OverflowError)):fn(*args)
 def inspect_blob(self,b):
  with tempfile.NamedTemporaryFile() as f:f.write(b);f.flush();return inspect.inspect(f.name)
 def test_onnx_spatial_attributes(self):
  for op in ["Conv","MaxPool"]:
   onnx.check_spatial_attrs(op,{})
   for attrs in [{"auto_pad":"SAME_UPPER"},{"auto_pad":"VALID"},{"dilations":[2,1]}]:
    with self.assertRaises(SystemExit):onnx.check_spatial_attrs(op,attrs)
  for attrs in [{"ceil_mode":1},{"storage_order":1}]:
   with self.assertRaises(SystemExit):onnx.check_spatial_attrs("MaxPool",attrs)
 def test_integer_fidelity(self):
  for bad in [1.5,-1.5,float('nan'),float('inf')]:
   for fn in [mm.require_i8,mm.require_i32,cv.i8,cv.i32,net.as_i8,net.as_i32]:
    with self.subTest(fn=fn.__name__,bad=bad):self.reject(fn,bad)
   self.reject(model.as_i8,[bad],'w');self.reject(model.as_i32,[bad],'b');self.reject(model.require_u16,bad,'M')
 def test_integer_boundaries(self):
  for fn in [mm.require_i8,net.as_i8]:
   self.assertEqual(fn(-128),-128);self.assertEqual(fn(127),127);self.reject(fn,-129);self.reject(fn,128)
  for fn in [mm.require_i32,cv.i32,net.as_i32]:
   self.assertEqual(fn(-(1<<31)),-(1<<31));self.assertEqual(fn((1<<31)-1),(1<<31)-1);self.reject(fn,1<<31)
 def test_stream_packers_agree(self):
  for M,N,K in [(1,9,1),(9,1,2),(9,9,8),(3,17,5),(17,3,8)]:
   A=[[(r+k)%9-4 for k in range(K)] for r in range(M)];B=[[(k+c)%7-3 for c in range(N)] for k in range(K)]
   for bias in [None,list(range(N))]:
    self.assertEqual(mm.make_feed(A,B,bias=bias),net.pack_matmul(A,B,bias=bias)[0])
 def test_empty_model(self):self.reject(self.inspect_blob,b'SNPU'+struct.pack('<HH',2,0))
 def test_zero_matmul(self):self.reject(self.inspect_blob,b'SNPU'+struct.pack('<HHBHHHII',2,1,1,0,0,0,0,0))
 def test_conv_geometry(self):
  for dims in [(0,1,1,1,1,1,1,1,0),(1,1,1,1,1,1,1,0,0),(1,1,1,1,1,2,2,1,0)]:
   nw=dims[3]*dims[5]*dims[6];b=b'SNPU'+struct.pack('<HHBHHHHHBBBBI',2,1,2,*dims,nw)+bytes(nw)+struct.pack('<Ii',1,0)
   self.reject(self.inspect_blob,b)
 def test_valid_model_truncation(self):
  with tempfile.TemporaryDirectory() as t:
   p=pathlib.Path(t)/'x.snpu';model.pack_model({'layers':[{'type':'matmul','M':1,'N':1,'K':1,'weights':[-128],'bias':[2147483647]}]},p)
   b=p.read_bytes();self.assertEqual(inspect.inspect(p)['layers'][0]['bias'],1)
   for i in range(len(b)):self.reject(self.inspect_blob,b[:i])
   self.reject(self.inspect_blob,b+b'!')
 def test_reply_size(self):
  for op,size in [(net.OP_INFO,28),(net.OP_ADD,4)]:
   for n in [0,size+1,0xffffffff]:
    sock=Socket(net.REP.pack(b'SNPR',1,0,n));s=net.NpuSession('unused');s.sock=sock
    with self.assertRaisesRegex(RuntimeError,'unexpected reply size'):s.request(op,out_bytes=4)
    self.assertTrue(sock.closed)
 def test_fragmented_reply(self):
  sock=Socket(net.REP.pack(b'SNPR',1,0,4)+b'1234');s=net.NpuSession('unused');s.sock=sock;self.assertEqual(s.request(net.OP_ADD,out_bytes=4),b'1234')
 def test_bad_header_and_disconnect(self):
  for b in [net.REP.pack(b'WRNG',1,0,4),net.REP.pack(b'SNPR',2,0,4),net.REP.pack(b'SNPR',1,-1,0),b'']:
   sock=Socket(b);s=net.NpuSession('unused');s.sock=sock
   with self.assertRaises((RuntimeError,ConnectionError)):s.request(net.OP_ADD,out_bytes=4)
   self.assertTrue(sock.closed)
if __name__=='__main__':unittest.main()
