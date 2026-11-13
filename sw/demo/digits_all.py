import sys, os, base64, zlib, struct, tempfile, time
sys.path[:0] = [os.path.expanduser('~/sw'), os.path.expanduser('~/sw/host')]
import npu_runtime as rt, snpu_loader
BLOB = """
eNqFWklw3Oh1/pvdTTQ3qLmAK7iCiwRxAyVxIGqBxjOGPR7Dk9hwlVOoygGn4IaqJFWpysmX5JKTy2eXc5iKU16Sco3j8XgWj3ZR
olZqpbiT4k5xJ0Wy2Xn/ez8oyZdRTReI7h///9bvfe9h1HzG/oXRvx/94G9+HGc5LPb7NGMKi51lDewCYyn2jf9W114UbjPjncQu
Ky0pvDZ0a7X2Rtf0xOXTq633d+4VDz94cexm7S9PZ7vkveuf337y2aw83Ja/8/IzpS9XHmLTw7lftX6Z/7jyg5mSvZzr395tVhYb
k6eO1OW3ps6ll5MXZ9LLRSvXp5OFsfo9djY33lFdfK+j/cJIMVMG9JSyeq9AqmrWugfyatfZ1OhvGwZWeo/dY5m6K+dK13arsitF
9z/q2r4//Hh992RmfPbns4tx5++m2pd/v/sit7K04uTEkaeGPnFGGXsY+wXLblbv1bbc3Pui+FV8amYm+0FVddfnkqSzSdZ/tKSZ
FXy9bzev9F18r67vO16iIsnuX+tN7sa37lb+YWfnWhvrqTq9ML0w9eSROvCD26/uNGdux46Z45cHxkfny5Jj23uln6mNNVNJeXtr
af7Pp56kX212yl9tJwrl8RuLTRO9exud8eLs8cr0XE315AvtQ7mg+VXPer3Wcicvca1wTNs9tRT73db66XtG3+Lycs2nz7Nfjgwt
X7t8Req0k4vl5XtXapJKy7S6l6p7lD+fruq4+kVek9f+o4WTEwPe9LEdpj+8XlMx+zyzeX6mouT4iXb54Cfm1K1nyzsTyeVmfYGp
PbHUi9T+/Oyrxf3qgwZ1/EHi7kgNBMRLVv6ydI2xT6Zj7WOrH8eXt8/JVQv77FeFjLX/rqx2f6V8Atzzm+Sk9IEyZ/VUtBSdaKuu
/uODhROpBxX7x55WxH9TObf/aay+rLW6bva7S/LS+18d1NwvX56Yjq2uTHXfG9xqU3c7U0cqUn1qadXg7afxgZKytsUvJKOppn1p
eqro1Lf797Kry6eGtv608m689NeJ2PWCjfLYSmNipSRfLZ9YLGB7qZ92fq/9vTslWzWL85mdSxtlF7f7d4Zmtq6Mtc+vyJlMpj+Z
29Xb/Qc71VZy4b2dtaL765myqfU19qz7Wn/eJ6zldEWs+OjuY2Xs9n7mzFphXlPP6fFviv+/dGcWulvMy0bpwdpc29DoaKwokzP6
cOZX1pPKnut5A4rSvd17bSWbmtozGtPp8Z2iY8cGwPgfK1dXvqtNvMrtuTPSsNa53JG/u5F778x68USyoyTnlNJ/cnv4yF5BSWt6
72X58/szPzy9t5r7pO5R18W26sxI7ng9K7GL1IqrFWv618vD0kF2lDV9vDFewV7kVbW2D18YnhxfnEy1/XDw4PF63kj13q8T+wvb
rT9ZaNy5qXTUJ9s78ts+Gti7vM2qOrkaR/T/ZsW3vlc/eq1p/usr5dnSzItjvZsvj5z4Jv0nGkoTbZmBTx9czFiVAz/vWx9N/ubO
OyVlk+rXhrt7LdaR3rqjH70rb53fbR6Rb5eeLVu6NJnaSN0em9tUbnY2ZM6YA/sdJ4uzjbszPbsVt9r2Hn/r6825xkW2WzpVfik+
NHWya7TxTvXZkf0zpY9LY+WVT18u7Zk98vC3Ckt705lHxS15544fr8jsJeP63FDx7LHm6opMZd3lnq/OF08Xbj7rP5/z447eK6WX
c04kc798Olt484GR+fzyZ0vF8ZZ8aeab9DsovjG4wgZfPJ5gve27TC+6d/Jmy/TF9tJ32OzxSnYj/eda5fyJrqOL/7df0Hui8dHn
zfemql4V5tv5Q+mxPNZbVnxridU9m+2v2h26Pl+Zrq0fnJtQ3mffUbe/e67/oXyFLY7nP9NiC4u7R/6w89XjqbbW6pVa48PSpztn
/rbyztOO3BlZubt2I/uMVSk3c5+P3iosXzm+tD6VmetKderdsent9Fr/yUS9kZP5+7q12kS8e6D7nFFZ13S3IP87lw7SH2xuxsfi
rUOT8dNdvVttawvZvGX7gz8N/+8nXZk+1s+UJtYtXxkakdl6deuLjsKWZFnL0dHSWPfQR+YTVspY1+wSY89Gn7P8lfeyRsPqlPHk
2lFTq1zSEtNs4uXIRsXQ3M3/eVWZ7dP6sl11NdLwu69YU+781tGFwq6Zjv673R0z+c822nbXITOOnx6eWni6Or/ZbdkH7WUzZZd+
u7SVHUr1PVvbk2suFFzTxqZm5laLS95ZMLvUxdR0vHAlfXWktWxnO1t1sHm3WK5uvDG38nlXWdW5i213BptuViyW1rfVTB0UJYZq
Ts8tXtKGZ8dbi4u6jg/f1senFp/lDUyN9w+NH2tLDJSdGW+olScfPX3ePnnik5z4iXamTuhP01dZ+mzbCstJKHfvSGuPf/ytjYXt
5L3NYz1fszMMEiQLcTB6l/Uy+dlvl9OdLR/ksbV61vnDkgX27bKGM4k/sZnspM7KCnZq77ALSzdka2c7tn8wuv2yp2s50XdX+6+D
1ODWXocqqbHZJUkenJ3+4tTGy1vmpQeNU/n1UnvB7SMNnbvFxW05SznHehqPtQ1ubi6zB/l549dvSve/aEteajx/sH+18MyIenEr
PZvX16rXDN34S06nXL0i3WqRPhyaHDeSD+oLhx7pD9+dP7jKUqvps2Pn5RfvFo4Nz25231cfxpJqRU0xK98sTTUMxcY3LjbMP/6E
qTvpzY6/sLnWk88Sq72LRSfuT7S/37mxfpT9bLX7VT1zG0D3T+Hzy4Ns9t9jjH0E17Nw/X42m70O349kstkfwd8MvluH68/g90/h
+hQ+/8yIYWwzohL/Ct+l4RPja+H+P+DvPriWwn0T/P0lPPsLuMIl+wg+/wa/1cNvsY+LGY/Esyyf8xL45tWoJtWm22erNpeHX17Y
nzqYXD8zu7JU2t2U0/2g+N7Ui4marFw/vaJlH6zVx5e7CjZvlJ9KTg+Wjz8oaV5+vJ9fmDvZWFjUUdx09/bu8lN2/9ReT2nT88Xm
upHEgfHHZuVFu8pYPHOQOYhl4t2J+jO1BZMtNwYHlcEz7XJ+Zv5m7eUTm6Xj+8/nG/c2BipPTPSzvneqZ6YaNgZnZicSjZWj/Quz
le375Z3p1NxGx2KrPLZ3pHB3vHG5fX5ztqJudjN//FVde7oinZ6I7XZ/daro3mJZ4vj2sp6T+ungxrjavvr9sURzwU1roGy3fLFu
7ENtaWm6tPJB5Wf3btU39t2ZOPnl8vH1isa7wxuD17LL0+8NlVhPHi80ry0flJ4aXxgaebh3fHG3uaqg/FkmO/N8Za39MavoOb2W
/OTFUtUroH7s1/D5J/j8I1i6iJcA+PwRPu/DfRyu/wnXf+CeZbIXWhwLXdcIFcYkX2Ghyr9Q7VDnVy+kBZonIWg6eMckWsVUH1cx
O5DxGjqErR5dldA1YVsmh77p8idDT3VduOpB6PINdT8M4Ukt9JyQP2DIgYtPGqE4UA9s2jLgzyuOiXIZYWjiAUEY8HWWY3H5mQRH
Krjc8lG+IMD1shsYuJ9nCrlpd9m2XX6ABYIGsNCzmAqCSaEieVwjjVkGaSLEcemW+aSv7jukp4XiK4ZG4ku+iQvkMBSWYo5JdkVL
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
J8Fy/h83WHtq
"""
raw = zlib.decompress(base64.b64decode(BLOB)); ml, n, _ = struct.unpack('<III', raw[:12])
mb = raw[12:12 + ml]; xs = raw[12 + ml:12 + ml + n * 64]; ys = list(raw[12 + ml + n * 64:])
X = [v - 256 if v > 127 else v for v in xs]
p = os.path.join(tempfile.gettempdir(), 'digits_demo.snpu'); open(p, 'wb').write(mb); model = snpu_loader.load_snpu(p)
host = sys.argv[1] if len(sys.argv) > 1 else '127.0.0.1'
import npu_net_client as cli
net = rt.Runtime(rt.NetBackend(cli.NpuSession(host, 9505, timeout=60)), 'auto'); soft = rt.Runtime(rt.SoftBackend(), 'auto')
B = 60; okn = oks = same = 0; preds = []; t0 = time.time()
for i in range(0, n, B):
    fl = X[i * 64:(i + B) * 64]
    on, _ = net.run(model, fl, (B, 64)); os_, _ = soft.run(model, fl, (B, 64))
    for j in range(B):
        pn = max(range(10), key=lambda c: on[j * 10 + c]); ps = max(range(10), key=lambda c: os_[j * 10 + c])
        preds.append(pn); okn += pn == ys[i + j]; oks += ps == ys[i + j]; same += on[j * 10:(j + 1) * 10] == os_[j * 10:(j + 1) * 10]
print('NPU  accuracy: %d/%d = %.2f%%' % (okn, n, 100.0 * okn / n))
print('soft accuracy: %d/%d = %.2f%%' % (oks, n, 100.0 * oks / n))
print('outputs bit-identical NPU vs soft: %d/%d samples  (%.1fs)' % (same, n, time.time() - t0))
for k in (0, 1, 2):
    print('\nsample %d true=%d NPU says=%d' % (k, ys[k], preds[k]))
    for r in range(8): print(''.join(' .:-=+*#%@'[min(9, X[k * 64 + r * 8 + c] * 9 // 112)] * 2 for c in range(8)))
