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
			if(synth.notNil) { synth.set(\blend, msg[1]) };
		});
		this.addCommand("tape", "f", { |msg|
			if(synth.notNil) { synth.set(\tape, msg[1]) };
		});
		this.addCommand("speed", "f", { |msg|
			if(synth.notNil) { synth.set(\speed, msg[1]) };
		});
		this.addCommand("volume", "f", { |msg|
			if(synth.notNil) { synth.set(\volume, msg[1]) };
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
			var blendLag = Lag.kr(blend, 0.08);
			var tp       = Lag.kr(tape, 0.15);
			var baseRate = Lag.kr(speed, 0.15);
			var vol      = Lag.kr(volume, 0.05);
			var sigs, mix, drive, bump, lpf, dropRate, dropTrig, dropEnv, hiss;

			// --- per-voice: playback + independent pitch modulation ---------
			sigs = Array.fill(6, { |i|
				var buf = bufs[i];
				// wow: slow pitch wander; its rate itself wanders (LFNoise1).
				var wowRate = LFNoise1.kr(0.1 + (i * 0.013)).range(0.3, 0.9);
				var wow = SinOsc.kr(wowRate, i * 0.7) * tp * 0.024;
				// flutter: fast shimmer, small depth.
				var flutRate = LFNoise1.kr(0.3 + (i * 0.04)).range(5, 11);
				var flut = SinOsc.kr(flutRate, i * 1.3) * tp * 0.004;
				// drift: brownian speed wander.
				var drift = LFNoise2.kr(0.03 + (i * 0.007)) * tp * 0.008;
				var rateMod = baseRate * (1 + wow + flut + drift);
				var phase = Phasor.ar(0,
					BufRateScale.kr(buf) * rateMod,
					0, BufFrames.kr(buf));
				var dist = (blendLag - i).abs;
				// equal-power crossfade: cos curve, zero beyond one unit away.
				var amp = (dist < 1.0) * cos(dist * (pi / 2));
				BufRd.ar(1, buf, phase, loop: 1) * amp;
			});

			mix = Mix(sigs);

			// --- post-mix tape chain ---------------------------------------
			// saturation (before the head roll-off, as with real tape).
			drive = tp.linexp(0, 1, 1, 6);
			mix = (mix * drive).tanh / max(drive, 1);

			// head bump: gentle low-shelf that keeps the sound full as it darkens.
			bump = tp.linlin(0, 1, 0, 6);
			mix = BLowShelf.ar(mix, 100, 0.7, bump);

			// high-frequency roll-off.
			lpf = tp.linexp(0, 1, 20000, 1400);
			mix = LPF.ar(mix, Lag.kr(lpf, 0.5));

			// dropouts: none below 0.65, then increasingly frequent.
			dropRate = tp.linlin(0.65, 1, 0, 0.15).max(0);
			dropTrig = Dust.kr(dropRate);
			dropEnv = EnvGen.kr(
				Env.new([1, 0.15, 1], [0.03, 0.08], \sin),
				dropTrig);
			mix = mix * dropEnv;

			// hiss: band-shaped, added after the filter (playback electronics).
			hiss = BPF.ar(WhiteNoise.ar(1), 5000, 0.8)
				* tp.linlin(0, 1, 0, 0.06)
				* LFNoise2.kr(0.5).range(0.7, 1.0);
			mix = mix + hiss;

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

			synth = Synth(\tuningin, [
				\out, context.out_b.index,
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
