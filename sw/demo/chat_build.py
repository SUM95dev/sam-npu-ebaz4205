#!/usr/bin/env python3
"""Build a tiny intent-chat model for the Sam NPU and write a single self-contained chat_all.py.
Needs numpy + sklearn (run on the laptop / sandbox, not on the board)."""
import base64, math, os, random, re, sys, zlib, json, struct
import numpy as np
from sklearn.neural_network import MLPClassifier
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.join(HERE, '..'))
import model_packer
D = 128; HID = 32; XS = 16.0
DATA = {
 'greet': (["hi", "hello", "hey", "salam", "hello there", "hi npu", "hey there", "good morning", "yo", "slm", "hola"],
           ["Hello! I'm a tiny chatbot. My brain is a 128-32-18 neural network running on an 8x8 INT8 NPU in the FPGA.", "Hi! Ask me about the NPU, the board, or just say hi."]),
 'howare': (["how are you", "how are you doing", "whats up", "how is it going", "are you ok", "hale shoma chetore", "chetori", "khobi", "how do you feel"],
            ["I'm a few thousand integer weights, so: stable. Thanks for asking!", "Running at about 100 MHz and feeling quantized."]),
 'name': (["what is your name", "who are you", "whats your name", "introduce yourself", "tell me about yourself", "esmet chiye", "to ki hasti", "are you a robot"],
          ["I'm Sam NPU chat, a small intent-classifier running on a Zynq-7010 (EBAZ4205).", "Just a tiny neural network. I pick the best answer from a short list."]),
 'npu': (["what is an npu", "what is npu", "explain the npu", "how does the npu work", "what is a systolic array", "tell me about the accelerator", "npu chiye", "how does the hardware work"],
         ["The NPU is an 8x8 systolic array of INT8 multiply-accumulate units. Data flows through it in waves, 64 MACs per cycle.", "It multiplies INT8 matrices with 32-bit accumulation, then requantizes the result back to INT8."]),
 'speed': (["how fast are you", "what is your speed", "how many gops", "how fast is the npu", "performance", "how much throughput", "chand gops", "are you fast"],
           ["Hardware peak is about 12.8 GOPS at an assumed 100 MHz. I measured about 5.8 GOPS on a 64x128x64 matrix multiply. The Python server is much slower."]),
 'board': (["what board is this", "which fpga", "what chip are you on", "tell me about the board", "what is ebaz4205", "which hardware", "bord chie", "what fpga do you use"],
           ["An EBAZ4205 with a Xilinx Zynq XC7Z010: dual ARM Cortex-A9 plus FPGA fabric. The NPU lives in the fabric."]),
 'accuracy': (["how accurate are you", "how correct are you", "what is your accuracy", "do you make mistakes", "are you always right", "dagheghi", "how good are you"],
              ["On digit recognition the INT8 model got about 96 percent. As a chatbot I only know a few topics, and I do make mistakes."]),
 'can': (["what can you do", "help", "what can i ask", "commands", "what do you know", "options", "chi midooni", "what are your features"],
         ["Ask me about the NPU, the board, speed, accuracy, who made me, or say hi, thanks, bye, or ask for a joke."]),
 'joke': (["tell me a joke", "joke", "say something funny", "make me laugh", "know any jokes", "yek jok bego", "funny"],
          ["Why did the neural network cross the road? Because it was quantized to the other side.", "I would tell you a UDP joke, but you might not get it. Also I have no network."]),
 'thanks': (["thanks", "thank you", "thx", "merci", "mersi", "ty", "thank you so much", "many thanks", "mamnoon"],
            ["You're welcome!", "Anytime."]),
 'bye': (["bye", "goodbye", "see you", "exit", "quit", "good night", "khodahafez", "cya", "later"],
         ["Goodbye!", "Bye! Powering down my attention, which I never had."]),
 'maker': (["who made you", "who built you", "who created you", "who trained you", "who wrote the code", "kie sakhte", "who is your creator"],
           ["The NPU and tooling were written with ChatGPT and reviewed and debugged with Claude, and the board owner ran it on real hardware."]),
 'limits': (["are you an llm", "are you chatgpt", "are you smart", "can you think", "do you understand me", "are you intelligent", "can you learn"],
            ["No. I'm a very small classifier. I match your sentence to the closest topic I was trained on. I don't understand language, and I can't learn at runtime."]),
 'time': (["what time is it", "what is the time", "tell me the time", "current time", "saat chande", "date and time", "what day is it"],
          ["@TIME"]),
 'power': (["how much power do you use", "power consumption", "how many watts", "are you energy efficient", "battery", "mesrafe bargh"],
           ["I haven't measured power on this board, so I won't invent a number. The Zynq-7010 is a small, low-power device."]),
 'love': (["i love you", "you are great", "you are awesome", "good job", "well done", "nice", "great work", "love you", "afarin"],
          ["Thank you! That's very kind for a pile of integers."]),
 'sad': (["i am sad", "i feel bad", "im tired", "i am bored", "i am stressed", "this is hard", "i am angry", "khaste am", "bad day"],
         ["Sorry to hear that. Take a break, drink some water. I'm a small bot, but I hope your day gets better."]),
}
OOD_WORDS = "pizza weather football bitcoin recipe tomorrow movie politics sport car elephant galaxy history capital price guitar vaccine airport holiday mountain novel election salary".split()
def feats(text):
    t = re.sub(r"[^a-z0-9 ]", " ", text.lower()); v = np.zeros(D)
    for w in t.split():
        s = "^" + w + "$"; v[zlib.crc32(("w:" + w).encode()) % D] = 1
        for i in range(len(s) - 2): v[zlib.crc32(s[i:i + 3].encode()) % D] = 1
    return v
def noisy(t, r):
    t = list(t)
    if len(t) > 3 and r.random() < .5:
        i = r.randrange(len(t)); op = r.random()
        if op < .4: del t[i]
        elif op < .7 and i < len(t) - 1: t[i], t[i + 1] = t[i + 1], t[i]
        else: t.insert(i, r.choice("abcdefghijklmnopqrstuvwxyz"))
    return "".join(t)
R = random.Random(3); names = list(DATA); X = []; y = []
for ci, k in enumerate(names):
    for ph in DATA[k][0]:
        for rep in range(8): X.append(feats(noisy(ph, R) if rep else ph)); y.append(ci)
for _ in range(250):  # out-of-domain -> 'unknown' class
    X.append(feats(" ".join(R.sample(OOD_WORDS, R.randint(1, 4))))); y.append(len(names))
X = np.array(X); y = np.array(y)
clf = MLPClassifier(hidden_layer_sizes=(HID,), max_iter=1500, random_state=1, alpha=1e-3).fit(X, y)
print('train acc %.4f, classes=%d' % (clf.score(X, y), len(names) + 1))
W1, W2 = clf.coefs_; b1, b2 = clf.intercepts_
def mq(m):
    sh = max(0, min(63, 12 - math.floor(math.log2(m)))); q = int(round(m * 2 ** sh))
    while q >= 2 ** 20 and sh > 0: sh -= 1; q = int(round(m * 2 ** sh))
    return q, sh
sw1 = 127.0 / np.abs(W1).max(); sw2 = 127.0 / np.abs(W2).max()
Xin = X * 1.0
H = np.maximum(Xin @ W1 + b1, 0); sh_ = 127.0 / H.max(); L = H @ W2 + b2; so = 127.0 / np.abs(L).max()
q1, s1 = mq(sh_ / (XS * sw1)); q2, s2 = mq(so / (sh_ * sw2))
W1q = np.clip(np.round(W1 * sw1), -128, 127).astype(int); W2q = np.clip(np.round(W2 * sw2), -128, 127).astype(int)
b1q = np.round(b1 * XS * sw1).astype(int); b2q = np.round(b2 * sh_ * sw2).astype(int)
N = len(names) + 1
layers = [{'type': 'matmul', 'M': 1, 'N': HID, 'K': D, 'weights': W1q.flatten().tolist(), 'bias': b1q.tolist(), 'qmul': q1, 'qshift': s1, 'zero_point': 0, 'relu': True},
          {'type': 'matmul', 'M': 1, 'N': N, 'K': HID, 'weights': W2q.flatten().tolist(), 'bias': b2q.tolist(), 'qmul': q2, 'qshift': s2, 'zero_point': 0, 'relu': False}]
tmp = os.path.join(HERE, '_chat.snpu'); model_packer.pack_model({'layers': layers}, tmp); mb = open(tmp, 'rb').read(); os.remove(tmp)
def qrun(x):
    a = (x * XS).astype(int) @ W1q + b1q; h = np.clip((a * q1) >> s1, 0, 127); a = h @ W2q + b2q; return np.clip((a * q2) >> s2, -128, 127)
# held-out paraphrases for a rough accuracy / margin choice
TEST = [("hello how are you today", 'howare'), ("heyy", 'greet'), ("what exactly is the npu", 'npu'), ("how fast can you go", 'speed'), ("which board are you running on", 'board'),
        ("whats your accuracy", 'accuracy'), ("what do you do", 'can'), ("tell me something funny", 'joke'), ("thank u", 'thanks'), ("goodbye now", 'bye'), ("who built this", 'maker'),
        ("are you intelligent", 'limits'), ("what time", 'time'), ("hi there", 'greet'), ("i feel tired", 'sad'), ("you are great", 'love'), ("what chip is this", 'board')]
ok = 0
for t, k in TEST:
    o = qrun(feats(t)[None, :])[0]; ok += (names + ['unknown'])[int(o.argmax())] == k
print('held-out paraphrases %d/%d' % (ok, len(TEST)))
OOD = ["what is the weather tomorrow", "who won the football game", "best pizza recipe", "bitcoin price", "play some guitar", "when is the election"]
rej = sum((names + ['unknown'])[int(qrun(feats(t)[None, :])[0].argmax())] == 'unknown' for t in OOD); print('OOD rejected %d/%d' % (rej, len(OOD)))
meta = {'names': names, 'resp': {k: DATA[k][1] for k in names}}
blob = zlib.compress(struct.pack('<I', len(mb)) + mb + json.dumps(meta).encode(), 9); b64 = base64.b64encode(blob).decode()
lines = '\n'.join(b64[i:i + 100] for i in range(0, len(b64), 100))
code = '''import sys, os, base64, zlib, struct, tempfile, time, re, json, random
sys.path[:0] = [os.path.expanduser('~/sw'), os.path.expanduser('~/sw/host')]
import npu_runtime as rt, snpu_loader
D = %d
BLOB = """
%s
"""
raw = zlib.decompress(base64.b64decode(BLOB)); ml = struct.unpack('<I', raw[:4])[0]
p = os.path.join(tempfile.gettempdir(), 'chat.snpu'); open(p, 'wb').write(raw[4:4 + ml]); model = snpu_loader.load_snpu(p)
meta = json.loads(raw[4 + ml:].decode()); names = meta['names'] + ['unknown']
def feats(text):
    t = re.sub(r"[^a-z0-9 ]", " ", text.lower()); v = [0] * D
    for w in t.split():
        s = "^" + w + "$"; v[zlib.crc32(("w:" + w).encode()) %% D] = 1
        for i in range(len(s) - 2): v[zlib.crc32(s[i:i + 3].encode()) %% D] = 1
    return [int(%d * e) for e in v]
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
        if ans == '@TIME': ans = 'It is ' + time.strftime('%%H:%%M') + ' on my clock, but this board has no RTC, so it may be wrong.'
    print('bot> ' + ans + '   [%%s: intent=%%s, %%.0f ms]' %% (where, name, dt))
    if name == 'bye': break
''' % (D, lines, int(XS))
open(os.path.join(HERE, 'chat_all.py'), 'w').write(code); print('chat_all.py', len(code), 'bytes')
