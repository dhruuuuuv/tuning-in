# ambiance

a sound object for norns. six nature soundscapes — birdsong, forest, rain,
stream, fire, night — blended continuously through a single control. a second
control ages the sound like a dying tape machine. no menus, no screens to
navigate. just two knobs and a landscape.

![ambiance](doc/cover.png)


## controls

    E1  volume
    E2  blend — sweep through six soundscapes
    E3  stability — tape degradation (pristine → warm → vintage → worn → memory)

    K1 held + E3  tape speed (0.5× to 1.5×)

    K2  tap: pause / resume (2s fade)
        hold 2s: start 30-minute sleep timer
    K3  tap: reset stability to pristine
    K1 + K3: reset tape speed to 1.0×


## sound

the blend control crossfades continuously between six loops. at any
position, at most two adjacent sounds are audible, mixed with an
equal-power curve. the stability control introduces wow, flutter,
saturation, filtering, hiss, and occasional dropouts — like a tape
reel aging in real time. at low settings it adds warmth. past halfway
the sound begins to wander. fully clockwise, the recordings are
barely recognisable — a memory of a landscape.


## screen

a unified particle system whose behaviour morphs with the blend.
birdsong: sparse bright dots drifting across a dawn horizon. rain:
dense diagonal streaks falling. fire: embers rising from a warm glow.
night: almost black, a few dim stars, occasional shooting star.
stability adds visual instability — jitter, glitches, a wobbling
horizon. the screen ages with the sound.


## install

from maiden:
`;install https://github.com/dhruvc/ambiance`

or clone to `~/dust/code/`:
`git clone https://github.com/dhruvc/ambiance.git`


## audio

ambiance ships with six short loops. drop your own recordings into
`~/dust/code/ambiance/audio/` to replace them:

    01_birdsong.flac
    02_forest.flac
    03_rain.flac
    04_stream.flac
    05_fire.flac
    06_night.flac

mono, 48kHz, seamlessly loopable, 30–45 seconds each. FLAC is preferred
(lossless, ~half the size of WAV); WAV and AIFF also load. the filename
must begin with the two-digit index and an underscore (`01_`, `02_`, …) —
anything after that is free. if no files are found, gentle test tones are
generated on first run so the script still works.

the six loops sound best when they feel like one world: normalise them to
matching loudness, keep them all mono, and give each a seamless 2-second
crossfade at the loop join (Audacity: *Effect › Crossfade Clip*).

### sourcing from freesound

the bundled loops (and any you source) are from [freesound.org](https://freesound.org)
under permissive Creative Commons licences. keep them **simple and minimal** —
a single steady texture per file, not a busy montage. that is what lets the
crossfade sound like walking between places rather than switching stations.

**every sound must be credited.** see [`audio/AUDIO_CREDITS.md`](audio/AUDIO_CREDITS.md).
CC-BY sounds require attribution; CC0 sounds do not, but we credit them anyway.
prefer CC0 or CC-BY. avoid CC-BY-NC unless you are not redistributing.


## requirements

norns (220802 or later)


## credits

concept + design: dhruv chadha (dhruvc.com)

audio: see [`audio/AUDIO_CREDITS.md`](audio/AUDIO_CREDITS.md)

inspired by the FM3 buddha machine, chase bliss blooper, and the
idea that the best technology disappears.
