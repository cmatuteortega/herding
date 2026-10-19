// Every sound, synthesized with WebAudio: no files. Nothing plays until the
// first tap (browsers require a gesture, and a bedtime game should not shout).
//
// Under it all runs a pad: a slow chord progression on soft detuned voices
// through a lowpass that closes as you get drowsy. Each Lullaby adds a layer:
//   1 the third and the seventh of each chord
//   2 a music box, an arpeggio through an echo
//   3 a high shimmer
//   4 a breathing sub bass
//   5 a slow bell melody over the top

const Sound = (() => {
  let ctx = null;
  let master, sfx, pad, padFilter, echo, echoSend;
  let muted = false;
  let lullabies = 0;
  let drowsy = 0;
  let asleep = false;
  let chordIndex = 0;
  let voices = []; // [{ osc: [..], gain, tone, layer }]
  let boxTimer = null, nextBox = 0, boxStep = 0, nextBell = 0, bellStep = 0, chordTimer = null;
  let noise = null;
  let combo = 0, lastTap = 0, lastLand = 0;

  const midi = (n) => 440 * Math.pow(2, (n - 69) / 12);
  // Cmaj9, Am9, Fmaj7, G6/sus: a lullaby turn, each eight seconds.
  const CHORDS = [
    [48, 55, 64, 71, 74],
    [45, 52, 60, 67, 71],
    [41, 48, 57, 64, 67],
    [43, 50, 59, 62, 69],
  ];
  const PENTA = [0, 2, 4, 7, 9];

  function now() { return ctx.currentTime; }

  function init() {
    if (ctx) { if (ctx.state === 'suspended') ctx.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    ctx = new AC();
    master = ctx.createGain();
    master.gain.value = muted ? 0 : 0.8;
    const comp = ctx.createDynamicsCompressor();
    comp.threshold.value = -18; comp.ratio.value = 3;
    master.connect(comp).connect(ctx.destination);

    sfx = ctx.createGain(); sfx.gain.value = 0.55; sfx.connect(master);

    padFilter = ctx.createBiquadFilter();
    padFilter.type = 'lowpass'; padFilter.frequency.value = 1800; padFilter.Q.value = 0.4;
    pad = ctx.createGain(); pad.gain.value = 0;
    padFilter.connect(pad).connect(master);
    pad.gain.setTargetAtTime(0.32, now(), 3); // fade in, slowly

    // A soft echo for the music box and bells.
    echo = ctx.createDelay(2); echo.delayTime.value = 0.42;
    const fb = ctx.createGain(); fb.gain.value = 0.38;
    const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 2200;
    echo.connect(lp).connect(fb).connect(echo);
    const wet = ctx.createGain(); wet.gain.value = 0.5;
    lp.connect(wet).connect(master);
    echoSend = ctx.createGain(); echoSend.gain.value = 1; echoSend.connect(echo);

    const len = ctx.sampleRate;
    noise = ctx.createBuffer(1, len, ctx.sampleRate);
    const ch = noise.getChannelData(0);
    for (let i = 0; i < len; i++) ch[i] = Math.random() * 2 - 1;

    buildPad();
    chordTimer = setInterval(nextChord, 8000);
    nextBox = now() + 1; nextBell = now() + 4;
    boxTimer = setInterval(schedule, 100);
    document.addEventListener('visibilitychange', () => {
      if (!ctx) return;
      if (document.hidden) ctx.suspend(); else ctx.resume();
    });
  }

  // One pad voice: two detuned oscillators on a chord tone.
  function addVoice(tone, layer, type, vol, octave = 0, detune = 6) {
    const gain = ctx.createGain();
    gain.gain.value = 0;
    // A slow swell on each, out of step with the others, so the pad breathes.
    const trem = ctx.createGain(); trem.gain.value = 0.7;
    gain.connect(trem).connect(padFilter);
    const f = midi(CHORDS[chordIndex][tone] + octave * 12);
    const osc = [-detune, detune].map((dt) => {
      const o = ctx.createOscillator();
      o.type = type; o.frequency.value = f; o.detune.value = dt;
      o.connect(gain); o.start();
      return o;
    });
    const lfo = ctx.createOscillator(); lfo.frequency.value = 0.05 + Math.random() * 0.08;
    const depth = ctx.createGain(); depth.gain.value = 0.3;
    lfo.connect(depth).connect(trem.gain); lfo.start();
    voices.push({ osc, gain, tone, layer, vol, octave, lfo });
  }

  function buildPad() {
    addVoice(0, 0, 'triangle', 0.16, 0);
    addVoice(1, 0, 'sine', 0.14, 0);
    addVoice(2, 1, 'triangle', 0.09, 0);
    addVoice(3, 1, 'sine', 0.07, 0);
    addVoice(4, 3, 'sine', 0.035, 1, 9); // shimmer
    addVoice(0, 4, 'sine', 0.2, -1, 2); // sub
    applyLayers();
  }

  function applyLayers() {
    if (!ctx) return;
    for (const v of voices) {
      const on = !asleep && v.layer <= lullabies;
      v.gain.gain.setTargetAtTime(on ? v.vol : 0, now(), asleep ? 3 : 1.5);
    }
  }

  function nextChord() {
    if (!ctx) return;
    chordIndex = (chordIndex + 1) % CHORDS.length;
    for (const v of voices) {
      const f = midi(CHORDS[chordIndex][v.tone] + v.octave * 12);
      for (const o of v.osc) o.frequency.setTargetAtTime(f, now(), 0.8);
    }
  }

  // Music box and bells, scheduled a little ahead of time.
  function schedule() {
    if (!ctx || asleep) return;
    const t0 = now();
    const stepLen = 0.42 + drowsy * 0.3; // slows down as you get sleepy
    while (nextBox < t0 + 0.3) {
      if (lullabies >= 2) {
        const ch = CHORDS[chordIndex];
        const pattern = [0, 2, 4, 2, 1, 3, 4, 3];
        const n = ch[pattern[boxStep % 8]] + 24;
        if (boxStep % 8 !== 7 || Math.random() < 0.5) pluck(midi(n), nextBox, 0.05, 1.4, true);
        boxStep++;
      }
      nextBox += stepLen;
    }
    while (nextBell < t0 + 0.3) {
      if (lullabies >= 5) {
        const melody = [76, 74, 72, 74, 76, 79, 76, 72];
        pluck(midi(melody[bellStep % melody.length]), nextBell, 0.06, 3, true, 'triangle');
        bellStep++;
      }
      nextBell += stepLen * 4;
    }
  }

  // A plucked note: fast attack, long exponential tail.
  function pluck(freq, at, vol, decay, wet = false, type = 'sine', dest = null) {
    if (!ctx) return;
    const o = ctx.createOscillator(); o.type = type; o.frequency.value = freq;
    const gn = ctx.createGain();
    gn.gain.setValueAtTime(0, at);
    gn.gain.linearRampToValueAtTime(vol, at + 0.008);
    gn.gain.exponentialRampToValueAtTime(0.0001, at + decay);
    o.connect(gn).connect(dest || sfx);
    if (wet) gn.connect(echoSend);
    o.start(at); o.stop(at + decay + 0.05);
  }

  function sweep(f0, f1, at, dur, vol, type = 'sine') {
    const o = ctx.createOscillator(); o.type = type;
    o.frequency.setValueAtTime(f0, at);
    o.frequency.exponentialRampToValueAtTime(f1, at + dur);
    const gn = ctx.createGain();
    gn.gain.setValueAtTime(0, at);
    gn.gain.linearRampToValueAtTime(vol, at + 0.006);
    gn.gain.exponentialRampToValueAtTime(0.0001, at + dur);
    o.connect(gn).connect(sfx);
    o.start(at); o.stop(at + dur + 0.05);
  }

  function puff(at, vol, freq, dur) {
    const src = ctx.createBufferSource(); src.buffer = noise;
    const f = ctx.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = freq;
    const gn = ctx.createGain();
    gn.gain.setValueAtTime(vol, at);
    gn.gain.exponentialRampToValueAtTime(0.0001, at + dur);
    src.connect(f).connect(gn).connect(sfx);
    src.start(at, Math.random() * 0.5); src.stop(at + dur + 0.02);
  }

  // A note of the current chord's pentatonic scale, climbing with fast taps.
  function scaleNote(i, base = 72) {
    const root = CHORDS[chordIndex][0] % 12;
    return base + root + PENTA[i % 5] + 12 * Math.floor(i / 5);
  }

  const cues = {
    tap() {
      const t = now();
      combo = t - lastTap < 0.45 ? Math.min(combo + 1, 9) : 0;
      lastTap = t;
      const f = midi(scaleNote(combo, 67));
      pluck(f, t, 0.16, 0.25);
      pluck(f * 2, t, 0.03, 0.12, false, 'triangle');
    },
    land() {
      const t = now();
      if (t - lastLand < 0.12) return;
      lastLand = t;
      puff(t, 0.05, 500, 0.07);
    },
    buy({ tier = 0, first = false } = {}) {
      const t = now();
      sweep(320 + tier * 40, 900 + tier * 80, t, 0.11, 0.22);
      pluck(midi(scaleNote(2 + tier, 72)), t + 0.05, 0.1, 0.5, true);
      if (first) pluck(midi(scaleNote(4 + tier, 72)), t + 0.16, 0.1, 0.8, true);
    },
    nope() {
      sweep(260, 200, now(), 0.12, 0.08, 'triangle');
    },
    goldenAppears() {
      const t = now();
      for (let i = 0; i < 3; i++) pluck(midi(scaleNote(10 + i * 2, 72)), t + i * 0.09, 0.05, 0.6, true);
    },
    golden() {
      const t = now();
      for (let i = 0; i < 7; i++) pluck(midi(scaleNote(i * 2, 72)), t + i * 0.06, 0.12, 0.9, true);
    },
    stage() {
      const t = now();
      CHORDS[chordIndex].forEach((n, i) => pluck(midi(n + 12), t + i * 0.12, 0.08, 2.4, true, 'triangle'));
    },
    asleep() {
      const t = now();
      [79, 76, 72, 67, 64, 60].forEach((n, i) => pluck(midi(n), t + i * 0.55, 0.09, 2.5, true));
    },
  };

  function cue(name, data) {
    if (!ctx || muted) return;
    if (cues[name]) cues[name](data);
  }

  function setMuted(m) {
    muted = m;
    if (ctx) master.gain.setTargetAtTime(m ? 0 : 0.8, now(), 0.15);
  }

  function setLullabies(n) {
    if (n === lullabies) return;
    lullabies = n;
    applyLayers();
  }

  // The sleepier, the darker and quieter the pad.
  function setDrowsy(d) {
    drowsy = d;
    if (ctx) padFilter.frequency.setTargetAtTime(2000 - d * 1300, now(), 1);
  }

  function setAsleep(a) {
    if (a === asleep) return;
    asleep = a;
    if (ctx) pad.gain.setTargetAtTime(a ? 0.0 : 0.32, now(), a ? 2.5 : 2);
    applyLayers();
  }

  return { init, cue, setMuted, setLullabies, setDrowsy, setAsleep, get started() { return !!ctx; } };
})();
