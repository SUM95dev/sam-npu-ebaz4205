import sys, os, base64, zlib, struct, tempfile, time, re, json, random
sys.path[:0] = [os.path.expanduser('~/sw'), os.path.expanduser('~/sw/host')]
import npu_runtime as rt, snpu_loader
D = 128
BLOB = """
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
+0ln660sbti3P+QpP/9d2iz1+r90DUbkr3s+dXG3riYYXjebrjdLutQzynbV/dSrkszUmzcjfxd2M/qf/kg3OFkpPf/6Y4Zs6ggV
NeP6mh1PjfFff7J9Sv6RpEkpeHgj+/Oj3d8QP712x5ER/Sh09L/+eDb38/sjvz+jGUr7bBLdLUsx/FuT+Ko8/7/1ts1k/U9jVCh0
W2Ao6eMxmKaTXzz7Q1J/2ho28wzb998H+sOS/368I1U9niK+9TBuLTc0/MGL+P/V/kJF4nL+uMEpyLgtNHV83QN9lnyd8SVO/JOC
0vetOPnHUzGi5+2IO4MFrW1DwsX8FezEGCoz7Z1Vzdrzr4W67o8h2exGt0GnElEAuz4DPLoKWFcD2v9lLxD4CbD4KGjbADM/B0z8
J1BGQfGCda1g/CyYF4D1ErD2Ehgzg7nnoP8bodVcY7ELTdC7wou1FkudUAEJK20N5loL3IIng/XleriyX7ZYKuDGeZu5Ntgwl5fX
15rLG+F2udkKV+/bLgX31FWarZfswdWNwYEa8yVLLdyorqqpqgvO1FUdnH/Z1nA4ZfsgOGA3VwjfA3WtxX4ZgPvNITgYZp6lutom
gPJjaiAzVFdlbYTKK8115211Kuh4I3S+1lxlharsYE6rMyr1OqXWCFktAGQ1qOoabLWXoNp6q7XKehGyWSGzFTJ+aITyT5w0QuBv
RAjsrau0QLnFRzNVMI68KgGUab8E1Vgg83lbfV1wFixUBBtBNyggWy30fr29DrKbG6HKKlUQ+KEPYcAHSC9YGsAeW73dbK0A19RZ
LlpqoQZL1cXKOrsCsttMkL3OfL7aooJOBh0HXQDHmu2XAFABjKT0ELS57hCJVqOBjuf9NQSfd8FiqYYnf11vttZV/bWl4gBEMHxv
IZSZa4Imwt5SAED2GnN1dRCJtU5ZXm2226suVAFMf+kd6Fyj9dfKRI1WA8lysjLPxes0htigYwpggw/9/3+7VwXlQ5eryi8deMgC
L7PaQXihC7U22BH2SlttHVRdZa87BAm4BWM8eeDZYOwOomJvtNfZqqvKIXNtLXCt7cJBnGrqq+uqLlc3KmHygY65zgLVWwGjVNAR
cx3wdLWtwQ5ur7XVX6yEqurgoDaYP7AANyfEQ8czs+3QZQCnvLEceBu2Jb/u7ZlVFvvhHea62qpy0GuoqquEAIvOg3N+vq/KZg0S
wArVWt663B60F/AVnASdN8P224JnHVh5kDpB/gLOwNwAIMyXgtYehFOnMkJHi4rLghEGvrfb62ssFW/DDHu1xmK219eCsYMdhrcb
gpFKiP8QEP5DYGEQ+4c/uwkmlAUqbgTks0J2S+0HwHZwa019eSVkr4YT7wDhQU7DCDOt0NtgH9hvhs5UAX59GKQDdCY78RxghAmq
qAdRzyw9DmWDiFo+VGYmQZer6+3B7IEumM8DDx5cDoe1ugpE4G1+HU4G7/1ZQuCri6xQRdVF4OtaS7ntIggqcHVwx0FUbBWWauii
7W0KJCXAkSwHBFaBLAUwD5UA+MpmrW6ELlltDW9TzwY4CRgAZ0s+VGGDYDWCagALQW0/QAILWND+/1/CB4OpgN4iV0ANlfCBFeBA
S1AODpQA3gOnsgICChgcB/l8kNcQrJIHtwb1Er72dGUjML4ieNH/o1jltTb7IcFs5op0KMtSbq63W2ByN5jtf057mHPwKhv4ASiq
Kg4JDjXY6qvBLJBOqNFWD+4/daQ4iAFgA0bCYzWwFEFW4L2LFpAzsEur7YDCUCXIHTD+c34HUR+qO4z7rK0+BtC5wVJdbquxBMUq
09oIS/shsRoP7Dtqs1WAdnBBFqihYph8sNRU2BqsUE0jYD4sRsHsaqisAvzMB5fCfK00HyrawRvyl3IBB7TOZgvKHzgO4Kitgo85
YG42IMTR4pPBVbWWD6osDXD6gE6F5Xz9xYugc7Cs2lxfYTlgx89xhgAqWA9BMgI/2+BkByGpPEzfAzyHTxkM6IRNdfgoAcSNh/L6
Z10NJrC5DhgFnA1iY4GFt9zyNmLl1TY7rJVBnoKlcFjr4LcMQLRZVUHOWmPqgNBVWGoBaQHQarP1Yr35ouUtqQF9wYJqi7nWCmsI
0PE/xyD40MIoM07mH88JDh28ucHXIRhiePPPChOchIK5B7TiLe1hNjQEYVRZwQb4AbDW15yHjYPD8efHIvj+Bj2ggIDEKA+OqwAB
KH/rOPihP4gjIBLsEwH88NXF2A/cB969isNUuVxVbYHF//DRPExW+AsB3l9mqwXLgRcrgeFwwgHinoRz2wy+BYDCKqAKwLFLADxI
6QbwVtS+DdNBhIBcHOQA8ILtsuUgOhUgf0EWAMstdXVBgfztb/8PxF5KXQ==
"""
raw = zlib.decompress(base64.b64decode(BLOB)); ml = struct.unpack('<I', raw[:4])[0]
p = os.path.join(tempfile.gettempdir(), 'chat.snpu'); open(p, 'wb').write(raw[4:4 + ml]); model = snpu_loader.load_snpu(p)
meta = json.loads(raw[4 + ml:].decode()); names = meta['names'] + ['unknown']
def feats(text):
    t = re.sub(r"[^a-z0-9 ]", " ", text.lower()); v = [0] * D
    for w in t.split():
        s = "^" + w + "$"; v[zlib.crc32(("w:" + w).encode()) % D] = 1
        for i in range(len(s) - 2): v[zlib.crc32(s[i:i + 3].encode()) % D] = 1
    return [int(16 * e) for e in v]
if '--soft' in sys.argv: rtm = rt.Runtime(rt.SoftBackend(), 'auto'); where = 'CPU(soft)'
else:
    import npu_net_client as cli
    rtm = rt.Runtime(rt.NetBackend(cli.NpuSession('127.0.0.1', 9505, timeout=30)), 'auto'); where = 'NPU'
print('Tiny chat on the Sam NPU. Type a message (quit to exit).')
while True:
    try: s = input('you> ')
    except EOFError: break
    if not s.strip(): continue
    t0 = time.time(); out, _ = rtm.run(model, feats(s), (1, D)); dt = (time.time() - t0) * 1000
    k = max(range(len(out)), key=lambda i: out[i]); name = names[k]
    if name == 'unknown': ans = "I don't know that one. I'm a tiny model that only knows a few topics. Try: 'what can you do'."
    else:
        ans = random.choice(meta['resp'][name])
        if ans == '@TIME': ans = 'It is ' + time.strftime('%H:%M') + ' on my clock, but this board has no RTC, so it may be wrong.'
    print('bot> ' + ans + '   [%s: intent=%s, %.0f ms]' % (where, name, dt))
    if name == 'bye': break
