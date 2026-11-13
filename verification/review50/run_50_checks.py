#!/usr/bin/env python3
"""50 directed checks of current host code. Not 50 whole-project reviews.
Optional --source points at a previous tree to reproduce pre-fix failures.
"""
import argparse,importlib.util,json,pathlib,struct,subprocess,tempfile,unittest
from unittest.mock import patch
p=argparse.ArgumentParser();p.add_argument('--source');p.add_argument('--report');args=p.parse_args()
root=pathlib.Path(args.source).resolve() if args.source else pathlib.Path(__file__).resolve().parents[2]
here=pathlib.Path(__file__).resolve().parent

def load(name,path):
 s=importlib.util.spec_from_file_location(name,root/path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
net=load('net50','sw/host/npu_net_client.py');inspect=load('inspect50','sw/snpu_inspect.py');mm=load('mm50','sw/pack_matmul_stream.py');cv=load('cv50','sw/pack_conv_stream.py')
class Sock:
 def __init__(self,blob=b'',timeout_error=False):self.blob=blob;self.closed=False;self.sent=[];self.timeout_error=timeout_error
 def recv(self,n):b=self.blob[:min(n,3)];self.blob=self.blob[len(b):];return b
 def sendall(self,b):self.sent.append(b)
 def close(self):self.closed=True
 def settimeout(self,t):
  if self.timeout_error:raise OSError('injected settimeout failure')
def reply(rid=1,n=4,body=b'abcd',magic=b'SNPR',status=0):return net.REP.pack(magic,rid,status,n)+body
class Checks(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.tmp=tempfile.TemporaryDirectory();td=pathlib.Path(cls.tmp.name);source=(root/'sw/linux/npu_net_server.c').read_text()
  setup='return install_signal_handlers();' if 'static int install_signal_handlers(' in source else 'signal(SIGTERM,on_signal);return 0;'
  c=(here/'check_shutdown.c.in').read_text().replace('SOURCE',str(root/'sw/linux/npu_net_server.c')).replace('SETUP_SIGNALS',setup)
  (td/'test.c').write_text(c);cls.shutdown=str(td/'test')
  subprocess.run(['gcc','-std=c11','-D_DEFAULT_SOURCE','-Wall','-Wextra','-Werror',str(td/'test.c'),'-o',cls.shutdown],check=True)
 @classmethod
 def tearDownClass(cls):cls.tmp.cleanup()
 def reject_header(self,kw):
  sock=Sock(reply());s=net.NpuSession('unused');calls=[]
  def connect():calls.append(1);s.sock=sock;return s
  s.connect=connect
  with self.assertRaises((ValueError,TypeError,struct.error,OverflowError)):s.request(**kw)
  self.assertEqual(calls,[], 'invalid local header opened a network session')
 def test_19_timeout_setup_closes_socket(self):
  sock=Sock(timeout_error=True);s=net.NpuSession('unused')
  with patch.object(net.socket,'create_connection',return_value=sock):
   with self.assertRaises(OSError):s.connect()
  self.assertTrue(sock.closed);self.assertIsNone(s.sock)
 def test_20_reconnect_after_bad_reply(self):
  a=Sock(reply(magic=b'FAIL'));b=Sock(reply(rid=2));s=net.NpuSession('unused')
  with patch.object(net.socket,'create_connection',side_effect=[a,b]):
   with self.assertRaises(RuntimeError):s.request(net.OP_ADD,out_bytes=4)
   self.assertTrue(a.closed);self.assertEqual(s.request(net.OP_ADD,out_bytes=4),b'abcd');s.close();self.assertTrue(b.closed)
 def test_21_request_id_wrap(self):
  sock=Sock(reply(rid=0xffffffff)+reply(rid=1));s=net.NpuSession('unused');s.sock=sock;s._next_id=0xffffffff
  self.assertEqual(s.request(net.OP_ADD,out_bytes=4),b'abcd');self.assertEqual(s.request(net.OP_ADD,out_bytes=4),b'abcd');self.assertEqual(s._next_id,2)
 def test_22_fragmented_body(self):
  sock=Sock(reply(n=12,body=b'abcdefghijkl'));s=net.NpuSession('unused');s.sock=sock;self.assertEqual(s.request(net.OP_ADD,out_bytes=12),b'abcdefghijkl')
 def test_23_wrapper_validates_before_connect(self):
  with patch.object(net.socket,'create_connection',return_value=Sock(reply())) as connect:
   with self.assertRaises((ValueError,TypeError,struct.error)):net.request('unused',opcode=-1)
   connect.assert_not_called()
 def test_24_wire_signed_extremes(self):
  sock=Sock(reply());s=net.NpuSession('unused');s.sock=sock;s.request(net.OP_MATMUL,M=1,N=1,K=1,out_bytes=4,qmul=-(1<<31),qshift=63,zp=-128,relu=True,extra_flags=2)
  header=net.REQ.unpack(sock.sent[0]);self.assertEqual(header[6:10],(3,-(1<<31),63,-128))
 def malformed(self,blob):
  with tempfile.NamedTemporaryFile() as f:
   f.write(blob);f.flush()
   with self.assertRaises(ValueError):inspect.inspect(f.name)
 def test_49_server_SIGTERM_idle_accept(self):subprocess.run([self.shutdown,'0'],check=True,timeout=3)
 def test_50_server_SIGTERM_partial_request(self):subprocess.run([self.shutdown,'1'],check=True,timeout=3)
invalid=[('opcode_negative',{'opcode':-1}),('opcode_overflow',{'opcode':65536}),('M_negative',{'opcode':1,'M':-1}),('N_overflow',{'opcode':1,'N':65536}),('K_overflow',{'opcode':1,'K':65536}),('out_bytes_negative',{'opcode':1,'out_bytes':-1}),('id_negative',{'opcode':1,'request_id':-1}),('id_overflow',{'opcode':1,'request_id':1<<32}),('flags_fractional',{'opcode':1,'extra_flags':1.9}),('shift_fractional',{'opcode':1,'qshift':1.9}),('multiplier_fractional',{'opcode':1,'qmul':1.9}),('zero_point_fractional',{'opcode':1,'zp':1.9})]
for i,(name,kw) in enumerate(invalid,1):
 def test(self,kw=kw):self.reject_header(kw)
 setattr(Checks,f'test_{i:02d}_{name}',test)
replies=[('bad_magic',reply(magic=b'WRNG')),('bad_id',reply(rid=7)),('server_error',reply(status=-11,n=0,body=b'')),('oversize_body',reply(n=0xffffffff,body=b'')),('header_truncated',b'SNPR'),('body_truncated',reply(body=b'a'))]
for i,(name,blob) in enumerate(replies,13):
 def test(self,blob=blob):
  sock=Sock(blob);s=net.NpuSession('unused');s.sock=sock
  with self.assertRaises((RuntimeError,ConnectionError)):s.request(net.OP_ADD,out_bytes=4)
  self.assertTrue(sock.closed);self.assertIsNone(s.sock)
 setattr(Checks,f'test_{i:02d}_{name}',test)
head=b'SNPU'+struct.pack('<HH',2,1)
def mat(M=1,N=1,K=1,nw=1,nb=1):return head+struct.pack('<BHHHI',1,M,N,K,nw)+bytes(nw)+struct.pack('<I',nb)+bytes(nb*4)
def conv(H=1,W=1,C=1,O=1,G=1,Kh=1,Kw=1,S=1,P=0):
 nw=O*Kh*Kw*(C//G) if G else 0
 return head+struct.pack('<BHHHHHBBBBI',2,H,W,C,O,G,Kh,Kw,S,P,nw)+bytes(nw)+struct.pack('<I',O)+bytes(O*4)
malformed=[('bad_magic',b'NOPE'+head[4:]),('version',b'SNPU'+struct.pack('<HH',99,0)),('empty_layers',b'SNPU'+struct.pack('<HH',2,0)),('unknown_op',head+b'\xff'),('truncated_header',b'SNPU\x02'),('M_zero',mat(M=0)),('N_zero',mat(N=0)),('K_zero',mat(K=0)),('weight_count',mat(nw=2)),('bias_count',mat(nb=2)),('conv_H_zero',conv(H=0)),('conv_W_zero',conv(W=0)),('conv_C_zero',conv(C=0)),('conv_O_zero',conv(O=0)),('conv_stride_zero',conv(S=0)),('conv_kernel_too_large',conv(Kh=2))]
for i,(name,blob) in enumerate(malformed,25):
 def test(self,blob=blob):self.malformed(blob)
 setattr(Checks,f'test_{i:02d}_snpu_{name}',test)
packers=[('ragged_A',lambda:mm.make_feed([[1],[2,3]],[[1]])),('ragged_B',lambda:mm.make_feed([[1]],[[1],[2]])),('empty_matrix',lambda:mm.make_feed([],[[1]])),('i8_overflow',lambda:mm.make_feed([[128]],[[1]])),('i8_underflow',lambda:mm.make_feed([[-129]],[[1]])),('bias_overflow',lambda:mm.make_feed([[1]],[[1]],bias=[1<<31])),('bias_count',lambda:mm.make_feed([[1]],[[1]],bias=[])),('conv_group_mismatch',lambda:cv.pack_conv_nhwc([[[1]]],[[[[1]]]],groups=2))]
for i,(name,fn) in enumerate(packers,41):
 def test(self,fn=fn):
  with self.assertRaises((ValueError,TypeError)):fn()
 setattr(Checks,f'test_{i:02d}_packer_{name}',test)
class Result(unittest.TextTestResult):
 def __init__(self,*a,**kw):super().__init__(*a,**kw);self.rows=[]
 def addSuccess(self,t):super().addSuccess(t);self.rows.append({'check':t.id().split('.')[-1],'passed':True})
 def addFailure(self,t,e):super().addFailure(t,e);self.rows.append({'check':t.id().split('.')[-1],'passed':False,'kind':'failure'})
 def addError(self,t,e):super().addError(t,e);self.rows.append({'check':t.id().split('.')[-1],'passed':False,'kind':'error'})
suite=unittest.defaultTestLoader.loadTestsFromTestCase(Checks);assert suite.countTestCases()==50
r=unittest.TextTestRunner(verbosity=2,resultclass=Result).run(suite)
if args.report:pathlib.Path(args.report).write_text(json.dumps({'source':str(root),'run':r.testsRun,'passed':sum(x['passed'] for x in r.rows),'checks':r.rows},indent=2))
raise SystemExit(0 if r.wasSuccessful() else 1)
