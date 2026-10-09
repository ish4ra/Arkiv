#!/usr/bin/env python3
"""Original Arkiv seal/chime: only mathematical tones and seeded noise, no samples."""
import io
import math
from pathlib import Path
import struct
import sys
import wave

RATE = 48000
DURATION = 0.55


def render():
    samples = []
    seed = 0x41524B49
    low = 0.0
    for index in range(round(RATE * DURATION)):
        t = index / RATE
        seed = (1664525 * seed + 1013904223) & 0xffffffff
        noise = seed / 0xffffffff * 2 - 1
        low += 0.085 * (noise - low)
        # Soft, low-pass mechanical seal with no harsh broadband click.
        seal = 0.10 * low * math.exp(-t / 0.013) * min(t / 0.003, 1)
        seal += 0.035 * math.sin(2 * math.pi * 190 * t) * math.exp(-t / 0.018) * min(t / 0.003, 1)
        value = seal
        for onset, frequency, gain in [(0.028, 523.251, 0.105), (0.185, 659.255, 0.12)]:
            age = t - onset
            if age >= 0:
                envelope = (1 - math.exp(-age / 0.009)) * math.exp(-age / 0.095)
                tone = math.sin(2 * math.pi * frequency * age) + 0.10 * math.sin(2 * math.pi * 2 * frequency * age)
                value += gain * envelope * tone
        value *= min(1, max(0, (DURATION - t) / 0.055))
        samples.append(round(value * 32767))
    buffer = io.BytesIO()
    with wave.open(buffer, 'wb') as output:
        output.setparams((1, 2, RATE, len(samples), 'NONE', 'not compressed'))
        output.writeframes(struct.pack('<' + 'h' * len(samples), *samples))
    return buffer.getvalue()


if __name__ == '__main__':
    expected = render()
    if len(sys.argv) == 3 and sys.argv[1] == '--verify':
        if Path(sys.argv[2]).read_bytes() != expected:
            raise SystemExit('Completion sound does not match original deterministic synthesis')
        print('Verified original Arkiv sound: mono PCM16, 48000 Hz, 0.55 seconds')
    elif len(sys.argv) == 2:
        Path(sys.argv[1]).write_bytes(expected)
    else:
        raise SystemExit('Usage: render-completion-sound.py [--verify] file.wav')
