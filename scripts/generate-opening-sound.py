"""Original Adê sound signature: D/A/E glass tones over a soft, filtered water-like bed.
Offline, deterministic PCM synthesis. No samples, model output or third-party recordings.
"""
from pathlib import Path
import math, random, struct, wave
rng = random.Random(20261026)
rate, duration = 44100, 8.4
notes = [(0.2, 293.665, -.45), (1.1, 440, .35), (2.7, 587.33, -.25),
         (3.5, 659.255, .4), (5.0, 440, -.3), (6.15, 293.665, 0), (6.18, 587.33, .25)]
frames = bytearray(); low = 0
for n in range(round(rate * duration)):
    t = n / rate
    fade = min(1, t / .4) * min(1, max(0, (duration - t) / 1.5))
    low = low * .985 + rng.uniform(-1, 1) * .015
    bed = .018 * low + .012 * math.sin(2 * math.pi * 146.8325 * t) * math.sin(math.pi * t / duration)**2
    channels = [bed, bed]
    for start, freq, pan in notes:
        x = t - start
        if x < 0: continue
        env = (1 - math.exp(-x * 35)) * math.exp(-x / 1.2)
        tone = .085 * env * (math.sin(2 * math.pi * freq * x) + .22 * math.sin(2 * math.pi * freq * 2.003 * x) * math.exp(-x * 2))
        channels[0] += tone * (1 - pan) / 2
        channels[1] += tone * (1 + pan) / 2
    frames.extend(struct.pack('<hh', *(round(max(-1, min(1, c * fade)) * 32767) for c in channels)))
path = Path(__file__).resolve().parents[1] / 'macos/Ade/Resources/Sound/ade-opening.wav'
with wave.open(str(path), 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(rate); w.writeframes(frames)
print(path)
