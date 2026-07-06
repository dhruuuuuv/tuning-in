# tuning in

a sound object for norns. six nature soundscapes: birdsong, forest, rain,
stream, fire, night. blended continuously through a single control. a second
control ages and worbles the sound.

![tuning in](doc/cover.png)


## controls

| control | action |
| --- | --- |
| **E1** | volume |
| **E2** | blend: an endless loop through the six soundscapes |
| **E3** | tape: degradation (pristine → warm → worn → memory) |
| **K1 + E3** | tape speed (0.05× to 1.5×) |
| **K2** tap | pause / resume (2s fade) |
| **K2** hold 2s | start a 30-minute sleep timer |
| **K3** tap | reset tape to pristine |
| **K1 + K3** | reset tape speed to 1.0× |


## sound

the blend control crossfades continuously around a loop of six soundscapes:
turn past night and it wraps back into birdsong.


## install

from maiden:

```
;install https://github.com/dhruuuuuv/tuning-in
```

or clone into `~/dust/code/`:

```
git clone https://github.com/dhruuuuuv/tuning-in.git
```


## audio

tuning in ships with six short loops. drop your own recordings into
`~/dust/code/tuning-in/audio/` to replace them:

```
01_birdsong.flac
02_forest.flac
03_rain.flac
04_stream.flac
05_fire.flac
06_night.flac
```

each should be mono, 48kHz, seamlessly loopable, 30–45 seconds. FLAC is
preferred (lossless, ~half the size of WAV); WAV and AIFF also load. the
filename must start with the two-digit index and an underscore (`01_`, `02_`,
…), anything after that is free. if no files are found, gentle test tones are
generated on first run so the script still works.

the six loops sound best when they feel like one world: matched loudness, all
mono, with a seamless ~2-second crossfade at the loop join.

### sourcing from freesound

the bundled loops are from [freesound.org](https://freesound.org) under
permissive Creative Commons licences. keep them **simple and minimal**. a
single steady texture per file, not a busy montage. that is what lets the
crossfade sound like walking between places rather than switching stations.

every sound is credited in
[`audio/AUDIO_CREDITS.md`](audio/AUDIO_CREDITS.md). prefer **CC0** or
**CC-BY** (CC-BY requires attribution); avoid CC-BY-NC unless you are not
redistributing.

### preparing loops

two helper scripts (need `ffmpeg`; the search script also needs `curl` +
`jq`):

```
# audition CC0 / CC-BY candidates (needs a free freesound API key)
export FREESOUND_TOKEN=...
./tools/freesound_search.sh "steady rain loop"

# turn a downloaded recording into a finished loop for a given slot
#   slots: 1 birdsong  2 forest  3 rain  4 stream  5 fire  6 night
./tools/prepare_audio.sh 3 ~/Downloads/rain.wav
```

`prepare_audio.sh` folds to mono, resamples to 48kHz, loudness-matches all six
to the same target, and builds a seamless crossfade loop: writing e.g.
`audio/03_rain.flac`. tune the section with env vars:

```
START=12 LEN=40 XF=2 ./tools/prepare_audio.sh 3 rain.wav
```


## deploying to a networked norns

```
NORNS_HOST=norns.local ./tools/deploy.sh
```

then in maiden's REPL run `;restart` (so norns loads the engine) and select
`tuning-in` on the device.


## requirements

norns (220802 or later)


## credits

concept + design: muchmetta ([llllllll.co/u/muchmetta](https://llllllll.co/u/muchmetta))

audio: see [`audio/AUDIO_CREDITS.md`](audio/AUDIO_CREDITS.md)
