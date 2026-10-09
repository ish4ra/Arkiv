# Original Arkiv completion sound

`Arkiv-Extraction-Complete.wav` is original mathematical synthesis for Arkiv.
No recording, third-party sample, or other application's audio was used.

- 0.55 seconds, mono, 48 kHz, signed 16-bit PCM WAV.
- A quiet, low-pass seeded-noise/190 Hz seal transient.
- Warm ascending C5–E5 tones, gentle attacks, short decays, a soft second harmonic,
  and a final fade. No voice, reverb, or borrowed melody/sample.
- Normal system output, asynchronous NSSound playback, no volume override.

Reproduce from the repository root:

```sh
python3 scripts/render-completion-sound.py Resources/Arkiv-Extraction-Complete.wav
python3 scripts/render-completion-sound.py --verify Resources/Arkiv-Extraction-Complete.wav
```

The signed app contains it at `Contents/Resources/Arkiv-Extraction-Complete.wav`.
Packaging checks exact synthesized bytes and AppKit decoding/duration for both
architectures, including mounted DMGs. Finder and browser extraction completion
handlers use the same success-only feedback function. Cancellation and failures
are silent apart from existing error behavior. Each successful operation starts
one sound; concurrent successes have separate nonblocking playback instances.
