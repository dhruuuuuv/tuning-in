// Engine_TuningIn
// six mono buffers, six continuously-running BufRd voices, equal-power
// crossfade driven by `blend`, and a post-mix tape-degradation chain
// driven by `tape`. `speed` sets the base playback rate.
//
// see ambiance-stability-control.md and ambiance-final-addendum.md.

Engine_TuningIn : CroneEngine {
	var <synth;
	var <buffers;
	var <folder;
	var <server;
	var isTone;   // per-index: was this buffer a generated fallback tone?
	var isLoading = false;   // guard against overlapping load routines
	// last-received control values, so a (re)created synth is born in the right
	// state even if lua sent the values before the synth existed.
	var lastBlend = 0, lastTape = 0, lastSpeed = 1, lastVol = 0;

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	alloc {
		server = context.server;
		// default install location; overridden by the `folder` command from lua.
		folder = Platform.userHomeDir ++ "/dust/code/tuning-in/audio/";
		buffers = Array.newClear(6);
		isTone = Array.fill(6, false);

		this.buildDef;

		// --- commands -------------------------------------------------------
		// point the engine at a specific audio folder, then (re)load.
		this.addCommand("folder", "s", { |msg|
			folder = msg[1].asString;
			this.loadBuffers;
		});

		this.addCommand("blend", "f", { |msg|
			lastBlend = msg[1];
			if(synth.notNil) { synth.set(\blend, lastBlend) };
		});
		this.addCommand("tape", "f", { |msg|
			lastTape = msg[1];
			if(synth.notNil) { synth.set(\tape, lastTape) };
		});
		this.addCommand("speed", "f", { |msg|
			lastSpeed = msg[1];
			if(synth.notNil) { synth.set(\speed, lastSpeed) };
		});
		this.addCommand("volume", "f", { |msg|
			lastVol = msg[1];
			if(synth.notNil) { synth.set(\volume, lastVol) };
		});

		// NOTE: do NOT auto-load here. lua sends the `folder` command from init()
		// with the correct install path, which triggers the single load. loading
		// here as well would race that load (double synths, orphaned buffers) and
		// can wedge the engine on `;restart`.
	}

	// build the SynthDef once. buffers are supplied as args at Synth creation,
	// so the def does not depend on any particular buffer being loaded yet.
	buildDef {
		SynthDef(\tuningin, {
			arg out = 0, blend = 0, tape = 0, speed = 1, volume = 1,
			buf0, buf1, buf2, buf3, buf4, buf5;

			var bufs = [buf0, buf1, buf2, buf3, buf4, buf5];
			var tp       = Lag.kr(tape, 0.15);
			var baseRate = Lag.kr(speed, 0.15);
			var vol      = Lag.kr(volume, 0.05);
			// FM tuning position from the RAW blend: 0 on a station, 1 mid-tune.
			// (seam-continuous, so lagging the derived value directly is safe.)
			var tuning   = Lag.kr((blend - blend.round(1.0)).abs * 2, 0.05);
			var sigs, mix, drive, bias, wow, wow2, flut, wowDepth, delayTime, wet, hiss;

			// --- per-voice playback -----------------------------------------
			sigs = Array.fill(6, { |i|
				var buf = bufs[i];
				// a subtle, slow, independent per-voice drift keeps the two
				// crossfading voices from wobbling in lockstep. the audible
				// warble is the post-mix modulation below.
				var drift = LFNoise2.kr(0.03 + (i * 0.007)) * tp * 0.006;
				var rateMod = baseRate * (1 + drift);
				var phase = Phasor.ar(0,
					BufRateScale.kr(buf) * rateMod,
					0, BufFrames.kr(buf));
				// circular crossfade distance: the six stations sit on a loop of
				// circumference 6, so night (5) fades back into birdsong (0).
				var d = (blend - i) % 6;
				var dist = min(d, 6 - d);
				// equal-power cos curve, zero beyond one unit away. lag the AMP
				// (not the blend value) so wrapping across the 6->0 seam never
				// sweeps the lag through the intermediate stations.
				var amp = Lag.kr((dist < 1.0) * cos(dist * (pi / 2)), 0.08);
				BufRd.ar(1, buf, phase, loop: 1) * amp;
			});
			mix = Mix(sigs);

			// --- saturation: tanh (odd harmonics) + a little bias asymmetry for
			// the even-harmonic warmth of tape. subtract bias.tanh to cancel the
			// DC the bias introduces. ---------------------------------------
			drive = tp.linexp(0, 1, 1, 5);
			bias = tp * 0.12;
			mix = ((mix * drive + bias).tanh - bias.tanh) / max(drive, 1);

			// --- head bump (low warmth) + progressive high roll-off ---------
			mix = BLowShelf.ar(mix, 100, 0.7, tp.linlin(0, 1, 0, 5));
			mix = LPF.ar(mix, tp.linexp(0, 1, 20000, 1600).lag(0.5));

			// --- wow & flutter. several LFOs whose rates themselves wander
			// (LFNoise1) sum into a short delay-time modulation, so the pitch
			// warbles organically rather than as a plain vibrato; mixed part-wet
			// for thickness. -------------------------------------------------
			wow   = SinOsc.kr(LFNoise1.kr(0.08).range(0.5, 1.1));       // ~1 Hz wow
			wow2  = SinOsc.kr(LFNoise1.kr(0.05).range(0.15, 0.45), 1.7); // slow wander
			flut  = SinOsc.kr(LFNoise1.kr(0.4).range(6, 10));           // ~8 Hz flutter
			wowDepth = ((wow * 0.0035) + (wow2 * 0.0022) + (flut * 0.00018)) * tp;
			delayTime = (0.010 + wowDepth).clip(0.0003, 0.05);
			wet = DelayC.ar(mix, 0.06, delayTime);
			mix = XFade2.ar(mix, wet, tp.linlin(0, 1, -1, -0.15));

			// --- hiss (subtle, from the playback electronics) ---------------
			hiss = BPF.ar(WhiteNoise.ar(1), 5000, 0.8)
				* tp.linlin(0, 1, 0, 0.05)
				* LFNoise2.kr(0.5).range(0.7, 1.0);
			mix = mix + hiss;

			// --- FM lock-in clarity + inter-station static ------------------
			mix = LPF.ar(mix, tuning.linexp(0, 1, 18000, 4500).lag(0.08));
			mix = mix + (HPF.ar(WhiteNoise.ar(1), 1200) * tuning.squared * 0.08);

			mix = mix * vol;
			Out.ar(out, [mix, mix]);
		}).add;
	}

	// (re)load the six buffers from `folder`, generating a fallback tone for
	// any file that is missing. rebuilds the synth once everything is ready.
	loadBuffers {
		if(isLoading) {
			"tuning in: load already in progress — ignoring".postln;
			^this;
		};
		isLoading = true;
		Routine {
			var anyTone = false;

			if(synth.notNil) { synth.free; synth = nil };
			6.do { |i| if(buffers[i].notNil) { buffers[i].free; buffers[i] = nil } };

			6.do { |i|
				// match 0N_*.flac or 0N_*.wav / .aif
				var matches = (folder ++ "0" ++ (i + 1) ++ "_*").pathMatch;
				if(matches.size > 0) {
					isTone[i] = false;
					buffers[i] = Buffer.read(server, matches[0]);
				} {
					isTone[i] = true;
					anyTone = true;
					buffers[i] = Buffer.alloc(server, 48000 * 10, 1); // 10s mono
				};
			};

			server.sync; // wait for reads / allocs to complete

			// fill the fallback buffers with distinct, gentle harmonic tones.
			6.do { |i|
				if(isTone[i]) {
					buffers[i].sine1(
						Array.fill(i + 2, { |h| (h + 1).reciprocal }),
						true, true, true);
				};
			};

			server.sync;

			// born in the last-known state (blend/tape/speed restored from the
			// pset, volume ~0 during boot) so there's no jump when it appears.
			synth = Synth(\tuningin, [
				\out, context.out_b.index,
				\blend, lastBlend, \tape, lastTape, \speed, lastSpeed, \volume, lastVol,
				\buf0, buffers[0], \buf1, buffers[1], \buf2, buffers[2],
				\buf3, buffers[3], \buf4, buffers[4], \buf5, buffers[5]
			], context.xg);

			if(anyTone) {
				("tuning in: using test tones for missing files — add audio to "
					++ folder).postln;
			} {
				"tuning in: all six loops loaded".postln;
			};

			isLoading = false;
		}.play;
	}

	free {
		if(synth.notNil) { synth.free };
		if(buffers.notNil) {
			buffers.do { |b| if(b.notNil) { b.free } };
		};
	}
}
