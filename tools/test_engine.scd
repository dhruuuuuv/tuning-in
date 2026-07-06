// test_engine.scd — audition the tuning-in engine on a desktop, no norns needed.
//
// this mirrors engine/Engine_TuningIn.sc as a plain SynthDef + a slider GUI so
// you can hear the crossfade and tape degradation before deploying to hardware.
//
// how to run:
//   1. install SuperCollider:  brew install --cask supercollider
//   2. open this file in the SuperCollider IDE (SCIDE)
//   3. put the cursor inside the block below and press Cmd+Return to evaluate
//   4. a window of sliders appears — sweep blend / tape / speed / volume
//   5. to stop: press Cmd+. (period)  — silences everything
//
// blend positions: 0 birdsong · 1 forest · 2 rain · 3 stream · 4 fire · 5 night

(
var audioDir, names;

// resolve the audio folder relative to this script (../audio/)
audioDir = PathName(thisProcess.nowExecutingPath).parentPath ++ "../audio/";
names = ["birdsong", "forest", "rain", "stream", "fire", "night"];

s.waitForBoot({
	var buffers, syn, win, mk;

	// --- load the six loops ------------------------------------------------
	buffers = Array.fill(6, { |i|
		var matches = (audioDir ++ "0" ++ (i + 1) ++ "_*").pathMatch;
		if(matches.size > 0) {
			("loading: " ++ PathName(matches[0]).fileName).postln;
			Buffer.read(s, matches[0]);
		} {
			("MISSING 0" ++ (i + 1) ++ "_* in " ++ audioDir
				++ " -- using a tone").postln;
			Buffer.alloc(s, 48000 * 5, 1).sine1(
				Array.fill(i + 2, { |h| (h + 1).reciprocal }), true, true, true);
		};
	});

	s.sync;

	// --- the engine DSP (kept in sync with Engine_TuningIn.sc) -------------
	SynthDef(\tuningin_test, {
		arg out = 0, blend = 0, tape = 0, speed = 1, volume = 0.5,
		buf0, buf1, buf2, buf3, buf4, buf5;

		var bufs = [buf0, buf1, buf2, buf3, buf4, buf5];
		var stab     = Lag.kr(tape, 0.15);
		var baseRate = Lag.kr(speed, 0.15);
		var vol      = Lag.kr(volume, 0.05);
		var tuning   = Lag.kr((blend - blend.round(1.0)).abs * 2, 0.05);
		var sigs, mix, drive, bias, wow, wow2, flut, wowDepth, delayTime, wet, hiss;

		sigs = Array.fill(6, { |i|
			var buf = bufs[i];
			var drift = LFNoise2.kr(0.03 + (i * 0.007)) * stab * 0.006;
			var rateMod = baseRate * (1 + drift);
			var phase = Phasor.ar(0,
				BufRateScale.kr(buf) * rateMod, 0, BufFrames.kr(buf));
			var d = (blend - i) % 6;
			var dist = min(d, 6 - d);
			var amp = Lag.kr((dist < 1.0) * cos(dist * (pi / 2)), 0.08);
			BufRd.ar(1, buf, phase, loop: 1) * amp;
		});

		mix = Mix(sigs);
		drive = stab.linexp(0, 1, 1, 5);
		bias = stab * 0.12;
		mix = ((mix * drive + bias).tanh - bias.tanh) / max(drive, 1);
		mix = BLowShelf.ar(mix, 100, 0.7, stab.linlin(0, 1, 0, 5));
		mix = LPF.ar(mix, stab.linexp(0, 1, 20000, 1600).lag(0.5));
		wow = SinOsc.kr(LFNoise1.kr(0.08).range(0.5, 1.1));
		wow2 = SinOsc.kr(LFNoise1.kr(0.05).range(0.15, 0.45), 1.7);
		flut = SinOsc.kr(LFNoise1.kr(0.4).range(6, 10));
		wowDepth = ((wow * 0.0035) + (wow2 * 0.0022) + (flut * 0.00018)) * stab;
		delayTime = (0.010 + wowDepth).clip(0.0003, 0.05);
		wet = DelayC.ar(mix, 0.06, delayTime);
		mix = XFade2.ar(mix, wet, stab.linlin(0, 1, -1, -0.15));
		hiss = BPF.ar(WhiteNoise.ar(1), 5000, 0.8)
			* stab.linlin(0, 1, 0, 0.05) * LFNoise2.kr(0.5).range(0.7, 1.0);
		mix = mix + hiss;
		mix = LPF.ar(mix, tuning.linexp(0, 1, 18000, 4500).lag(0.08));
		mix = mix + (HPF.ar(WhiteNoise.ar(1), 1200) * tuning.squared * 0.08);
		mix = mix * vol;
		Out.ar(out, [mix, mix]);
	}).add;

	s.sync;

	syn = Synth(\tuningin_test, [
		\buf0, buffers[0], \buf1, buffers[1], \buf2, buffers[2],
		\buf3, buffers[3], \buf4, buffers[4], \buf5, buffers[5],
		\volume, 0.5
	]);

	// --- GUI ---------------------------------------------------------------
	AppClock.sched(0, {
		win = Window("tuning in — engine test", Rect(200, 200, 460, 260)).front;
		win.view.decorator = FlowLayout(win.view.bounds);
		win.onClose = { syn.free; buffers.do(_.free) };

		mk = { |label, lo, hi, init, sym|
			EZSlider(win, 420 @ 40, label,
				ControlSpec(lo, hi), { |ez| syn.set(sym, ez.value) },
				init, labelWidth: 90, numberWidth: 70).setColors;
		};

		mk.("blend",     0, 6,   0,   \blend);
		mk.("tape",      0, 1,   0,   \tape);
		mk.("speed",     0.05, 1.5, 1, \speed);
		mk.("volume",    0, 1,   0.5, \volume);

		StaticText(win, 420 @ 40).string_(
			"0 birdsong  1 forest  2 rain  3 stream  4 fire  5 night");
	});

	"\ntuning in engine test running. Cmd+. to stop.".postln;
});
)
