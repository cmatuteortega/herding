// Counting Sheep. One file, in four parts:
//   1. Logic: the game state and the rules. Pure: no DOM, no canvas, no sound.
//   2. Sprites: the ray-traced ellipsoid bodies from herding / underroot, and
//      the 8+ colour palette they are painted in.
//   3. Scene: the low-res canvas, drawn from the state and from view-only
//      effects (hopping sheep, floating numbers) that never touch the rules.
//   4. UI and boot: the shop, the dialogs, saving, the fixed-timestep loop.
'use strict';

/* ================================================================== 1. Logic */

const Logic = (() => {
  const C = CONFIG;
  const N = Num;

  const ITEMS = [];
  for (const u of C.tapUpgrades) ITEMS.push({ kind: 'tap', growth: C.growth, ...u });
  C.generators.forEach((g, i) => ITEMS.push({ kind: 'gen', growth: C.growth, index: i, ...g }));
  for (const m of C.multipliers) ITEMS.push({ kind: 'mult', growth: C.growth, ...m });
  const BY_ID = Object.fromEntries(ITEMS.map((it) => [it.id, it]));
  const GENS = ITEMS.filter((it) => it.kind === 'gen');

  function freshOwned() {
    return Object.fromEntries(ITEMS.map((it) => [it.id, 0]));
  }

  function freshRun() {
    return {
      sheep: N.zero(),
      runTotal: N.zero(),
      runTime: 0,
      owned: freshOwned(),
      goldenIn: C.golden.firstDelay,
      golden: null, // { t } while one is crossing
      stage: 0,
      asleep: false,
    };
  }

  function fresh() {
    return {
      ...freshRun(),
      version: 1,
      dreamPoints: 0,
      dreams: 0,
      allTime: N.zero(),
      taps: 0,
      buyMode: '1',
      muted: false,
      lastSeen: Date.now(),
    };
  }

  // Events for the view and the sound: logic never calls either.
  const events = [];
  const emit = (type, data) => events.push({ type, ...data });

  function globalMult(s) {
    let m = 1;
    for (const it of ITEMS) if (it.kind === 'mult') m *= 1 + it.add * s.owned[it.id];
    return m * (1 + C.prestige.bonusPerPoint * s.dreamPoints);
  }

  function rawRate(s) {
    let r = 0;
    for (const g of GENS) r += g.rate * s.owned[g.id];
    return r;
  }

  const perSecond = (s) => N.mul(N.from(rawRate(s)), globalMult(s));
  const genRate = (s, id) => N.mul(N.from(BY_ID[id].rate * s.owned[id]), globalMult(s));

  function tapValue(s) {
    let v = C.tapBase;
    for (const it of ITEMS) if (it.kind === 'tap' && it.add) v += it.add * s.owned[it.id];
    for (const it of ITEMS) if (it.kind === 'tap' && it.mult) v *= Math.pow(it.mult, s.owned[it.id]);
    return N.mul(N.from(v), globalMult(s));
  }

  function drowsiness(s) {
    const share = N.toNumber(N.div(s.runTotal, N.from(C.drowsiness.target)));
    return Math.min(1, Math.pow(Math.max(0, share), C.drowsiness.curve));
  }

  function stageOf(s) {
    let k = 0;
    C.stages.forEach((st, i) => { if (N.gte(s.runTotal, N.from(st.at))) k = i; });
    return k;
  }

  function capLeft(s, it) {
    return it.max ? Math.max(0, it.max - s.owned[it.id]) : Infinity;
  }

  // What buying `mode` ('1', '10' or 'max') of an item would mean now:
  // { n, cost, ok }. With max and nothing affordable, the price of one.
  function quote(s, id, mode) {
    const it = BY_ID[id];
    const k = s.owned[id];
    const left = capLeft(s, it);
    if (left === 0) return { n: 0, cost: N.zero(), ok: false, maxed: true };
    let n;
    if (mode === 'max') n = Math.min(left, N.maxAffordable(it.base, it.growth, k, N.toNumber(s.sheep)));
    else n = Math.min(left, Number(mode));
    const ok = n > 0;
    if (!ok) n = 1;
    const cost = N.from(N.sumGeometric(it.base, it.growth, k, n));
    return { n, cost, ok: ok && N.gte(s.sheep, cost), maxed: false };
  }

  // Shown in the shop: generators one at a time (each once the one before is
  // owned), upgrades once the run has counted a share of their price.
  function visible(s, id) {
    const it = BY_ID[id];
    if (s.owned[id] > 0) return true;
    if (it.kind === 'gen') return it.index === 0 || s.owned[GENS[it.index - 1].id] > 0;
    return N.gte(s.runTotal, N.from(it.base * C.revealAt));
  }

  // The one card shown as "???": the next generator after the last visible one.
  function teaser(s) {
    for (const g of GENS) if (!visible(s, g.id)) return g.id;
    return null;
  }

  function count(s, v) {
    s.sheep = N.add(s.sheep, v);
    s.runTotal = N.add(s.runTotal, v);
    s.allTime = N.add(s.allTime, v);
  }

  function buy(s, id, mode) {
    if (s.asleep || !visible(s, id)) return null;
    const q = quote(s, id, mode);
    if (!q.ok) return null;
    const first = s.owned[id] === 0;
    s.sheep = N.sub(s.sheep, q.cost);
    s.owned[id] += q.n;
    emit('bought', { id, n: q.n, first });
    // Whatever this reveals.
    const it = BY_ID[id];
    if (first && it.kind === 'gen' && GENS[it.index + 1]) emit('unlock', { id: GENS[it.index + 1].id });
    return q;
  }

  function tap(s) {
    if (s.asleep) return N.zero();
    const v = tapValue(s);
    count(s, v);
    s.taps++;
    return v;
  }

  function goldenReward(s) {
    return N.max(N.mul(perSecond(s), N.from(C.golden.rewardSeconds)), N.mul(tapValue(s), N.from(C.golden.minTaps)));
  }

  function catchGolden(s) {
    if (!s.golden || s.asleep) return null;
    const v = goldenReward(s);
    count(s, v);
    s.golden = null;
    emit('golden', { value: v });
    return v;
  }

  function settle(s) {
    const st = stageOf(s);
    if (st > s.stage) {
      s.stage = st;
      emit('stage', { stage: st });
    }
    if (!s.asleep && drowsiness(s) >= 1) {
      s.asleep = true;
      s.golden = null;
      emit('asleep', {});
    }
  }

  // One fixed step of `dt` seconds.
  function step(s, dt, rand = Math.random) {
    if (s.asleep) return;
    s.runTime += dt;
    count(s, N.mul(perSecond(s), N.from(dt)));
    if (s.golden) {
      s.golden.t += dt;
      if (s.golden.t >= C.golden.crossTime) s.golden = null;
    } else {
      s.goldenIn -= dt;
      if (s.goldenIn <= 0) {
        s.golden = { t: 0, lane: rand() };
        s.goldenIn = C.golden.minDelay + rand() * (C.golden.maxDelay - C.golden.minDelay);
        emit('goldenAppears', {});
      }
    }
    settle(s);
  }

  // Away for `seconds`: up to the cap of production, counted at once.
  function offline(s, seconds) {
    if (s.asleep || seconds <= 0) return null;
    const cap = C.offline.maxHours * 3600;
    const secs = Math.min(seconds, cap);
    const gain = N.mul(perSecond(s), N.from(secs));
    count(s, gain);
    settle(s);
    return { secs, gain, capped: seconds > cap };
  }

  const dreamPointsFor = (s) => Math.floor(N.toNumber(N.sqrt(N.div(s.runTotal, N.from(C.prestige.divisor)))));

  function dreamAgain(s) {
    const gained = dreamPointsFor(s);
    s.dreamPoints += gained;
    s.dreams++;
    Object.assign(s, freshRun());
    return gained;
  }

  function currentLine(s) {
    const d = drowsiness(s);
    let text = C.lines[0].text;
    for (const l of C.lines) {
      if (l.total !== undefined && !N.gte(s.runTotal, N.from(l.total))) continue;
      if (l.own !== undefined && !(s.owned[l.own] > 0)) continue;
      if (l.drowsy !== undefined && d < l.drowsy) continue;
      text = l.text;
    }
    return text;
  }

  // Saves: plain JSON, Nums serialized, unknown fields ignored, missing ones fresh.
  function serialize(s) {
    return JSON.stringify({
      ...s,
      sheep: N.serialize(s.sheep),
      runTotal: N.serialize(s.runTotal),
      allTime: N.serialize(s.allTime),
      lastSeen: Date.now(),
    });
  }

  function deserialize(json) {
    const s = fresh();
    let o;
    try { o = JSON.parse(json); } catch (e) { return null; }
    if (!o || typeof o !== 'object') return null;
    for (const k of Object.keys(s)) if (k in o && k !== 'owned') s[k] = o[k];
    for (const id of Object.keys(s.owned)) s.owned[id] = Math.max(0, Math.floor(Number(o.owned && o.owned[id]) || 0));
    s.sheep = N.deserialize(o.sheep);
    s.runTotal = N.deserialize(o.runTotal);
    s.allTime = N.deserialize(o.allTime);
    if (!['1', '10', 'max'].includes(s.buyMode)) s.buyMode = '1';
    return s;
  }

  return {
    ITEMS, BY_ID, GENS, events, fresh, step, tap, buy, quote, visible, teaser,
    perSecond, genRate, tapValue, globalMult, drowsiness, stageOf, catchGolden, goldenReward,
    offline, dreamPointsFor, dreamAgain, currentLine, serialize, deserialize,
  };
})();

if (typeof window !== 'undefined') window.Logic = Logic;

/* ================================================================ 2. Sprites */

// The palette: herding's eight colours, and six more for a sky that goes from
// dusk to night (navy, midnight, lavender, lilac) and for the golden sheep.
// Nothing on the canvas is drawn outside it: no alpha, no blending. A soft
// thing (the sky, the night falling over the grass) is dithered instead.
const PAL = (() => {
  const LIST = [
    ['o', '37364e', 'n'], // ink: outlines
    ['t', '355d69', 'o'], // deep teal: grass in shadow
    ['g', '6aae9d', 't'], // grass
    ['m', 'b9d4b4', 'g'], // mint: lit grass
    ['w', 'f4e9d4', 'b'], // cream: wool
    ['b', 'd0baa9', 's'], // beige: wool in shade, the dusk horizon
    ['s', '9e8e91', 'p'], // mauve grey: stone, wood
    ['p', '5b4a68', 'o'], // plum: faces, legs
    ['n', '1c1e38', 'n'], // deep navy: the night sky
    ['v', '2a2c50', 'n'], // midnight
    ['l', 'b7a8dc', 'i'], // lavender
    ['i', '8577b0', 'p'], // lilac
    ['y', 'f0cf7a', 'h'], // gold
    ['h', 'c0904e', 'p'], // gold in shade
  ];
  const css = {}, rgb = {}, darker = {};
  for (const [k, hex, d] of LIST) {
    css[k] = '#' + hex;
    rgb[k] = [parseInt(hex.slice(0, 2), 16), parseInt(hex.slice(2, 4), 16), parseInt(hex.slice(4, 6), 16)];
    darker[k] = d;
  }
  return { css, rgb, darker };
})();

// 4x4 ordered dither: pixel (x, y) is "on" at density v (0..1).
const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
const dither = (x, y, v) => v * 16 > BAYER[((y & 3) << 2) | (x & 3)] + 0.5;

// The tracer, ported from herding/tracer.lua (Survive School's 3D method by
// way of underroot). A body is a list of ellipsoids; each pixel is traced once
// and its colour *chosen* off a ramp (glint, lit, middle, shadow). Then creases
// where one material's normals disagree, and ink round the silhouette and along
// any step in depth onto another part. Orthographic, so a pose is painted once
// and kept.
const Tracer = (() => {
  const ELEV = (22 * Math.PI) / 180; // lower than herding's: we see sheep side-on
  const CE = Math.cos(ELEV), SE = Math.sin(ELEV);
  const UY = CE, UZ = -SE, NY = SE, NZ = CE;
  const DX = 0, DY = -NY, DZ = -NZ;
  let LX = -0.55, LY = 0.85, LZ = 0.45;
  { const n = Math.hypot(LX, LY, LZ); LX /= n; LY /= n; LZ /= n; }
  let HX = LX, HY = LY + NY, HZ = LZ + NZ;
  { const n = Math.hypot(HX, HY, HZ); HX /= n; HY /= n; HZ /= n; }
  const CREASE = 0.55, BACK = 60;

  const project = (x, y, z) => [x, z * SE - y * CE];

  function shade(r, nx, ny, nz) {
    const d = nx * LX + ny * LY + nz * LZ;
    const h = nx * HX + ny * HY + nz * HZ;
    if (h > 0 && Math.pow(h, 40) > 0.6) return [r[0], 1];
    if (d > 0.72) return [r[1], 2];
    if (d > 0.15) return [r[2], 3];
    if (ny < 0 && d > 0.02) return [r[2], 3]; // bounce light off the ground
    return [r[3], 4];
  }

  // Affine maps: twelve numbers, row-major 3x3 then the shift per row.
  const A = {
    move: (x, y, z) => [1, 0, 0, x, 0, 1, 0, y, 0, 0, 1, z],
    scale: (x, y, z) => [x, 0, 0, 0, 0, y, 0, 0, 0, 0, z, 0],
    rotY(a) { const c = Math.cos(a), s = Math.sin(a); return [c, 0, s, 0, 0, 1, 0, 0, -s, 0, c, 0]; },
    rotZ(a) { const c = Math.cos(a), s = Math.sin(a); return [c, -s, 0, 0, s, c, 0, 0, 0, 0, 1, 0]; },
    mul(a, b, ...rest) {
      const r = new Array(12);
      for (let row = 0; row < 3; row++) {
        const a1 = a[row * 4], a2 = a[row * 4 + 1], a3 = a[row * 4 + 2], a4 = a[row * 4 + 3];
        for (let col = 0; col < 4; col++) r[row * 4 + col] = a1 * b[col] + a2 * b[4 + col] + a3 * b[8 + col];
        r[row * 4 + 3] += a4;
      }
      return rest.length ? A.mul(r, ...rest) : r;
    },
    inv(m) {
      const [a, b, c] = [m[0], m[1], m[2]], [d, e, f] = [m[4], m[5], m[6]], [g, h, i] = [m[8], m[9], m[10]];
      const A1 = e * i - f * h, B1 = -(d * i - f * g), C1 = d * h - e * g;
      const det = a * A1 + b * B1 + c * C1;
      const r = [
        A1 / det, -(b * i - c * h) / det, (b * f - c * e) / det, 0,
        B1 / det, (a * i - c * g) / det, -(a * f - c * d) / det, 0,
        C1 / det, -(a * h - b * g) / det, (a * e - b * d) / det, 0,
      ];
      for (let row = 0; row < 3; row++) {
        r[row * 4 + 3] = -(r[row * 4] * m[3] + r[row * 4 + 1] * m[7] + r[row * 4 + 2] * m[11]);
      }
      return r;
    },
  };

  const ell = (cx, cy, cz, rx, ry, rz, ramp, id = 1) => ({ at: A.mul(A.move(cx, cy, cz), A.scale(rx, ry, rz)), ramp, id });
  function place(parts, m) { for (const p of parts) p.at = A.mul(m, p.at); return parts; }

  // Parts to a picture: a canvas, and the pixel the pivot (room 0,0,0) lands on.
  function paint(parts, edge = 1.5) {
    let i0 = Infinity, j0 = Infinity, i1 = -Infinity, j1 = -Infinity;
    for (const p of parts) {
      const m = p.at;
      p.inv = A.inv(m);
      let r = 0;
      for (let col = 0; col < 3; col++) r = Math.max(r, Math.hypot(m[col], m[4 + col], m[8 + col]));
      const [ci, cj] = project(m[3], m[7], m[11]);
      p.ci = ci; p.cj = cj; p.cr = r + 1;
      i0 = Math.min(i0, ci - p.cr); i1 = Math.max(i1, ci + p.cr);
      j0 = Math.min(j0, cj - p.cr); j1 = Math.max(j1, cj + p.cr);
    }
    i0 = Math.floor(i0) - 1; j0 = Math.floor(j0) - 1; i1 = Math.ceil(i1) + 1; j1 = Math.ceil(j1) + 1;
    const w = i1 - i0 + 1, h = j1 - j0 + 1, n = w * h;
    const key = new Array(n), lev = new Int8Array(n), shd = new Array(n), part = new Int16Array(n), mat = new Int16Array(n);
    const dep = new Float32Array(n), dif = new Float32Array(n), nxs = new Float32Array(n), nys = new Float32Array(n), nzs = new Float32Array(n);
    const best = new Float32Array(n).fill(1e9);

    for (const p of parts) {
      const v = p.inv;
      const bx = v[0] * DX + v[1] * DY + v[2] * DZ;
      const by = v[4] * DX + v[5] * DY + v[6] * DZ;
      const bz = v[8] * DX + v[9] * DY + v[10] * DZ;
      const qa = bx * bx + by * by + bz * bz;
      const rr = p.cr * p.cr;
      const pj0 = Math.max(0, Math.floor(p.cj - p.cr) - j0), pj1 = Math.min(h - 1, Math.ceil(p.cj + p.cr) - j0);
      const pi0 = Math.max(0, Math.floor(p.ci - p.cr) - i0), pi1 = Math.min(w - 1, Math.ceil(p.ci + p.cr) - i0);
      for (let pj = pj0; pj <= pj1; pj++) {
        for (let pi = pi0; pi <= pi1; pi++) {
          const si = i0 + pi + 0.5, sj = j0 + pj + 0.5;
          if ((si - p.ci) ** 2 + (sj - p.cj) ** 2 > rr) continue;
          const ox = si, oy = -sj * UY + BACK * NY, oz = -sj * UZ + BACK * NZ;
          const ax = v[0] * ox + v[1] * oy + v[2] * oz + v[3];
          const ay = v[4] * ox + v[5] * oy + v[6] * oz + v[7];
          const az = v[8] * ox + v[9] * oy + v[10] * oz + v[11];
          const qb = ax * bx + ay * by + az * bz;
          const disc = qb * qb - qa * (ax * ax + ay * ay + az * az - 1);
          if (disc < 0) continue;
          const t = (-qb - Math.sqrt(disc)) / qa;
          const q = pj * w + pi;
          if (t >= best[q]) continue;
          best[q] = t;
          const ux = ax + t * bx, uy = ay + t * by, uz = az + t * bz;
          let nx = v[0] * ux + v[4] * uy + v[8] * uz;
          let ny = v[1] * ux + v[5] * uy + v[9] * uz;
          let nz = v[2] * ux + v[6] * uy + v[10] * uz;
          const l = Math.hypot(nx, ny, nz);
          nx /= l; ny /= l; nz /= l;
          let [k, lv] = shade(p.ramp, nx, ny, nz);
          const printed = p.print && p.print(ux, uy, uz, lv);
          if (printed) { k = printed; lv = 0; }
          key[q] = k; lev[q] = lv; shd[q] = p.ramp[3];
          part[q] = p.id; mat[q] = p.mat || p.id;
          dep[q] = BACK - t; dif[q] = nx * LX + ny * LY + nz * LZ;
          nxs[q] = nx; nys[q] = ny; nzs[q] = nz;
        }
      }
    }

    const out = key.slice();
    const crease = (p, q) => {
      if (!key[q] || mat[p] !== mat[q]) return;
      if (nxs[p] * nxs[q] + nys[p] * nys[q] + nzs[p] * nzs[q] >= CREASE) return;
      const r = dif[p] < dif[q] ? p : q;
      if (lev[r] === 2 || lev[r] === 3) out[r] = shd[r];
    };
    for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) {
      const p = j * w + i;
      if (!key[p]) continue;
      if (i < w - 1) crease(p, p + 1);
      if (j < h - 1) crease(p, p + w);
    }
    const inked = (p, q) => !key[q] || (part[q] !== part[p] && dep[p] - dep[q] > edge);
    for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) {
      const p = j * w + i;
      if (key[p] && (i === 0 || j === 0 || i === w - 1 || j === h - 1 ||
        inked(p, p - 1) || inked(p, p + 1) || inked(p, p - w) || inked(p, p + w))) out[p] = 'o';
    }

    const c = document.createElement('canvas');
    c.width = w; c.height = h;
    const g = c.getContext('2d');
    const img = g.createImageData(w, h);
    for (let q = 0; q < n; q++) {
      const k = out[q];
      if (!k) continue;
      const col = PAL.rgb[k];
      img.data[q * 4] = col[0]; img.data[q * 4 + 1] = col[1]; img.data[q * 4 + 2] = col[2]; img.data[q * 4 + 3] = 255;
    }
    g.putImageData(img, 0, 0);
    return { c, oi: -i0, oj: -j0, w, h };
  }

  return { A, ell, place, paint, CE, SE };
})();

// The bodies (herding/models.lua's, and a few new ones), each a function from
// a few small numbers to a list of parts, painted the first time those numbers
// are asked for and kept under them.
const Models = (() => {
  const { A, ell, place, paint } = Tracer;
  const ramp = (g, l, m, s) => [g, l, m, s];
  const R = {
    wool: ramp('w', 'w', 'b', 's'),
    gold: ramp('w', 'y', 'y', 'h'),
    pj: ramp('w', 'l', 'l', 'i'),
    face: ramp('b', 's', 'p', 'o'),
    coat: ramp('b', 's', 'p', 'o'),
    white: ramp('w', 'w', 'b', 's'),
    wood: ramp('w', 'b', 's', 'p'),
    picket: ramp('w', 'w', 'b', 's'),
    goldWood: ramp('w', 'y', 'h', 'p'),
    metal: ramp('w', 'b', 's', 'p'),
    moon: ramp('w', 'l', 'i', 'p'),
  };
  const cache = new Map();
  function kept(key, build) {
    let p = cache.get(key);
    if (!p) { p = paint(build()); cache.set(key, p); }
    return p;
  }
  const HEADINGS = 16, TAU = Math.PI * 2;
  const step = (h) => ((Math.round((((h % TAU) + TAU) % TAU) / TAU * HEADINGS)) % HEADINGS);
  const angle = (st) => (st / HEADINGS) * TAU;

  // `squash` -2..3 (negative stretches it in the air, positive flattens it
  // landing), `leg` 0/1 trotting or 2 leaping, `look` 'plain', 'pj' (pajamas
  // and a nightcap) or 'gold', `graze` head down, `size` 1 or smaller.
  function sheep(h, squash = 0, leg = 0, look = 'plain', graze = false, size = 1) {
    const hs = step(h);
    return kept(`sheep${hs}.${squash}.${leg}.${look}.${graze ? 1 : 0}.${size}`, () => {
      const W = look === 'gold' ? R.gold : R.wool;
      // Pajamas: stripes across the body, a shade down the ramp.
      const puff = (x, y, z, rx, ry, rz, id) => {
        const p = ell(x, y, z, rx, ry, rz, W, id);
        p.mat = 1;
        if (look === 'pj') {
          // Lavender stripes across the wool in room height, so they run on
          // from puff to puff.
          p.print = (ux, uy, uz, lv) => {
            if (Math.floor((y + uy * ry) / 1.7) % 2) return null;
            return lv >= 4 ? 'i' : lv === 1 ? null : 'l';
          };
        }
        return p;
      };
      const parts = [
        puff(-0.4, 5.0, 0, 6.0, 4.2, 4.8, 1),
        puff(-3.0, 7.0, 1.8, 3.4, 3.0, 3.0, 11),
        puff(-2.8, 7.0, -2.0, 3.3, 3.0, 3.0, 12),
        puff(1.0, 7.6, 1.6, 3.3, 3.0, 3.0, 13),
        puff(1.0, 7.5, -1.8, 3.3, 3.0, 3.0, 14),
        puff(-5.4, 5.6, 0, 2.6, 2.6, 2.8, 15),
      ];
      let hx = 6.4, hy = 6.6;
      if (graze) { hx = 7.2; hy = 2.8; }
      parts.push(ell(hx, hy, 0, 3.0, 2.7, 2.5, R.face, 2));
      parts.push(ell(hx + 2.0, hy - 0.8, 0, 1.5, 1.6, 1.6, R.face, 2));
      parts.push(ell(hx - 0.6, hy + 1.0, 2.8, 0.8, 1.0, 1.4, R.face, 3));
      parts.push(ell(hx - 0.6, hy + 1.0, -2.8, 0.8, 1.0, 1.4, R.face, 3));
      if (look === 'pj') {
        // A nightcap, tipped back, with a cream bobble.
        const cap = ell(hx - 1.4, hy + 3.0, 0, 2.2, 1.6, 2.2, R.pj, 16);
        cap.print = (ux, uy) => (uy < -0.4 ? 'w' : null);
        parts.push(cap);
        parts.push(ell(hx - 3.6, hy + 4.2, 0, 1.4, 1.2, 1.4, R.pj, 17));
        parts.push(ell(hx - 5.0, hy + 4.0, 0, 1.0, 1.0, 1.0, R.white, 18));
      } else {
        parts.push(puff(hx - 1.6, hy + 2.2, 0, 2.0, 1.4, 1.8, 16)); // the topknot
      }
      const legs = leg === 2
        ? [[3.4, 2.4, 1.8, 0.6], [3.4, -2.4, 1.8, 0.6], [-3.4, 2.4, -1.8, 0.6], [-3.4, -2.4, -1.8, 0.6]]
        : [[3.4, 2.4, leg ? 0.9 : -0.9, 0], [3.4, -2.4, leg ? -0.9 : 0.9, 0], [-3.4, 2.4, leg ? -0.9 : 0.9, 0], [-3.4, -2.4, leg ? 0.9 : -0.9, 0]];
      for (const l of legs) parts.push(ell(l[0] + l[2], 1.2 + l[3], l[1], 1.0, 1.7, 1.0, R.face, 4));
      const q = squash * 0.07;
      return place(parts, A.mul(A.scale(size, size, size), A.rotY(-angle(hs)), A.scale(1 + q, 1 - q * 1.6, 1 + q)));
    });
  }

  // herding's collie. `gait` 0..3 is where the legs are in the stride.
  function dog(h, gait) {
    const hs = step(h);
    return kept(`dog${hs}.${gait}`, () => {
      const C = R.coat, Wt = R.white;
      const hy = 9.4;
      const parts = [
        ell(0, 6.4, 0, 6.2, 3.6, 3.4, C, 1),
        ell(4.2, 6.4, 0, 2.8, 3.2, 3.0, Wt, 2),
        ell(7.2, hy, 0, 3.1, 2.9, 2.8, C, 3),
        ell(9.8, hy - 1.0, 0, 2.0, 1.4, 1.5, Wt, 4),
        ell(10.9, hy - 0.6, 0, 0.7, 0.6, 0.7, C, 9),
        ell(6.4, hy + 2.6, 1.6, 0.8, 1.6, 0.9, C, 5),
        ell(6.4, hy + 2.6, -1.6, 0.8, 1.6, 0.9, C, 5),
        ell(-7.0, 7.2, 0, 3.0, 1.7, 1.6, C, 6),
        ell(-9.6, 7.8, 0, 1.6, 1.4, 1.3, Wt, 7),
      ];
      const swing = Math.sin((gait / 4) * TAU) * 1.8;
      for (const l of [[3.8, 2.0, 1], [3.8, -2.0, -1], [-3.8, 2.0, -1], [-3.8, -2.0, 1]]) {
        parts.push(ell(l[0] + swing * l[2], 1.6, l[1], 1.1, 2.0, 1.1, l[0] > 0 ? Wt : C, 8));
      }
      return place(parts, A.mul(A.scale(0.8, 0.8, 0.8), A.rotY(-angle(hs))));
    });
  }

  // The fence: two posts and two rails. Wood, then a white picket with the
  // first Better Fence, then gold-capped with the third.
  function fence(level, squash) {
    const look = level >= 3 ? 2 : level >= 1 ? 1 : 0;
    return kept(`fence${look}.${squash}`, () => {
      const W = look === 2 ? R.picket : look === 1 ? R.picket : R.wood;
      const cap = look === 2 ? R.goldWood : W;
      const parts = [];
      for (const x of [-7.5, 7.5]) {
        parts.push(ell(x, 6, 0, 1.6, 6.4, 1.6, W, 1));
        parts.push(ell(x, 12.6, 0, 1.8, 1.1, 1.8, cap, 2));
      }
      parts.push(ell(0, 9.2, 0.6, 9.4, 1.1, 1.0, W, 3));
      parts.push(ell(0, 4.8, 0.6, 9.4, 1.1, 1.0, W, 4));
      const q = squash * 0.06;
      return place(parts, A.scale(1.25 + q * 0.5, 1.25 - q, 1.25));
    });
  }

  function drone(tilt) {
    return kept(`drone${tilt}`, () => place([
      ell(0, 0, 0, 3.2, 1.6, 3.2, R.metal, 1),
      ell(0, -1.2, 0, 1.4, 1.0, 1.4, R.moon, 5),
      ell(-4, 1.2, -3, 2.0, 0.4, 2.0, R.white, 2),
      ell(4, 1.2, -3, 2.0, 0.4, 2.0, R.white, 3),
      ell(-4, 1.2, 3, 2.0, 0.4, 2.0, R.white, 4),
      ell(4, 1.2, 3, 2.0, 0.4, 2.0, R.white, 6),
    ], A.rotZ(tilt * 0.12)));
  }

  function moon(r) {
    return kept(`moon${r}`, () => {
      const p = ell(0, 0, 0, r, r, r, R.moon, 1);
      // A few craters, printed a shade down.
      p.print = (ux, uy, uz, lv) => {
        const c = [[0.3, 0.4, 0.86], [-0.5, -0.1, 0.86], [0.1, -0.55, 0.83]];
        for (const [a, b, cz] of c) if ((ux - a) ** 2 + (uy - b) ** 2 + (uz - cz) ** 2 < 0.05) return lv >= 3 ? 'p' : 'i';
        return null;
      };
      return [p];
    });
  }

  return { sheep, dog, fence, drone, moon, step };
})();

// The 3x5 pixel face from Survive School / underroot / herding.
const Font = (() => {
  const G = {
    A: ['.#.', '#.#', '###', '#.#', '#.#'], B: ['##.', '#.#', '##.', '#.#', '##.'], C: ['.##', '#..', '#..', '#..', '.##'],
    D: ['##.', '#.#', '#.#', '#.#', '##.'], E: ['###', '#..', '##.', '#..', '###'], F: ['###', '#..', '##.', '#..', '#..'],
    G: ['.##', '#..', '#.#', '#.#', '.##'], H: ['#.#', '#.#', '###', '#.#', '#.#'], I: ['###', '.#.', '.#.', '.#.', '###'],
    J: ['..#', '..#', '..#', '#.#', '.#.'], K: ['#.#', '##.', '#..', '##.', '#.#'], L: ['#..', '#..', '#..', '#..', '###'],
    M: ['#.#', '###', '###', '#.#', '#.#'], N: ['#.#', '##.', '###', '.##', '#.#'], O: ['.#.', '#.#', '#.#', '#.#', '.#.'],
    P: ['##.', '#.#', '##.', '#..', '#..'], Q: ['.#.', '#.#', '#.#', '##.', '.##'], R: ['##.', '#.#', '##.', '#.#', '#.#'],
    S: ['.##', '#..', '.#.', '..#', '##.'], T: ['###', '.#.', '.#.', '.#.', '.#.'], U: ['#.#', '#.#', '#.#', '#.#', '###'],
    V: ['#.#', '#.#', '#.#', '#.#', '.#.'], W: ['#.#', '#.#', '###', '###', '#.#'], X: ['#.#', '#.#', '.#.', '#.#', '#.#'],
    Y: ['#.#', '#.#', '.#.', '.#.', '.#.'], Z: ['###', '..#', '.#.', '#..', '###'],
    0: ['###', '#.#', '#.#', '#.#', '###'], 1: ['.#.', '##.', '.#.', '.#.', '###'], 2: ['##.', '..#', '.#.', '#..', '###'],
    3: ['##.', '..#', '.#.', '..#', '##.'], 4: ['#.#', '#.#', '###', '..#', '..#'], 5: ['###', '#..', '##.', '..#', '##.'],
    6: ['.##', '#..', '###', '#.#', '###'], 7: ['###', '..#', '.#.', '.#.', '.#.'], 8: ['###', '#.#', '###', '#.#', '###'],
    9: ['###', '#.#', '###', '..#', '##.'], '.': ['...', '...', '...', '...', '.#.'], '+': ['...', '.#.', '###', '.#.', '...'],
    '-': ['...', '...', '###', '...', '...'], ':': ['...', '.#.', '...', '.#.', '...'], '!': ['.#.', '.#.', '.#.', '...', '.#.'],
    '/': ['..#', '..#', '.#.', '#..', '#..'], '?': ['##.', '..#', '.#.', '...', '.#.'], '>': ['#..', '.#.', '..#', '.#.', '#..'],
    '_': ['...', '...', '...', '...', '###'], ' ': ['...', '...', '...', '...', '...'],
  };
  const width = (s, z = 1) => (s.length * 4 - 1) * z;
  // Plot `s` at (x, y), each font pixel z by z game pixels.
  // `dens` below 1 dithers it away (how a number fades with no alpha).
  function draw(g, s, x, y, k, z = 1, dens = 1) {
    g.fillStyle = PAL.css[k];
    s = String(s).toUpperCase();
    for (let n = 0; n < s.length; n++) {
      const gl = G[s[n]];
      if (!gl) continue;
      for (let r = 0; r < 5; r++) for (let c = 0; c < 3; c++) {
        if (gl[r][c] !== '#') continue;
        const px = x + (n * 4 + c) * z, py = y + r * z;
        if (dens < 1 && !dither(px, py, dens)) continue;
        g.fillRect(px, py, z, z);
      }
    }
  }
  // With an ink edge, to read over anything.
  function label(g, s, x, y, k, z = 1, dens = 1, edge = 'o') {
    const ring = z > 1 ? [[-1, 0], [1, 0], [0, -1], [0, 1], [1, 1], [-1, 1], [1, -1], [-1, -1]] : [[-1, 0], [1, 0], [0, -1], [0, 1], [1, 1]];
    for (const [dx, dy] of ring) draw(g, s, x + dx, y + dy, edge, z, dens);
    draw(g, s, x, y, k, z, dens);
  }
  return { draw, label, width };
})();

/* ================================================================== 3. Scene */

// The view: everything is drawn into a small canvas, a game pixel a whole
// number of device pixels (herding's main.lua fit), so nothing is ever
// smoothed. It reads the state; what only looks (a sheep mid-hop, a number
// floating up) lives in Scene and never feeds back into the rules.
const Scene = (() => {
  const TAU = Math.PI * 2;
  const C = CONFIG;
  let canvas, g, cw = 160, ch = 120, scale = 3, cssPx = 3;
  let L = {}; // the layout, in game pixels
  let bg = null, bgKey = '';
  let reduced = false;
  let stars = [];
  let t = 0;

  const fx = {
    hoppers: [], particles: [], floats: [], zzz: [], hearts: [], smoke: [], launched: [],
    fenceBounce: 0, shake: 0, autoAcc: 0, zAcc: 0, smokeAcc: 0, heartAcc: 0,
    lids: { blink: 0, next: 6, close: 0 },
    queueBob: 0, flash: 0,
  };

  // Seeded dice for anything placed (stars, grazing spots): the same picture
  // every time for the same screen.
  function seeded(seed) {
    let x = seed | 0 || 1;
    return () => ((x = (x * 16807) % 2147483647) / 2147483647);
  }

  function init(el, opts) {
    canvas = el;
    g = canvas.getContext('2d');
    reduced = !!opts.reduced;
    resize();
  }

  function setReduced(v) { reduced = v; }

  // Fit to the scene box: the biggest whole zoom that keeps at least ~110
  // game pixels down the short way, and never smaller than 3 CSS pixels a
  // game pixel (so the pixel numbers stay over 14px tall).
  function resize() {
    const box = canvas.parentElement.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    const wDev = Math.max(1, Math.round(box.width * dpr)), hDev = Math.max(1, Math.round(box.height * dpr));
    scale = Math.max(Math.ceil(3 * dpr), Math.floor(Math.min(hDev / 120, wDev / 150)));
    cw = Math.ceil(wDev / scale);
    ch = Math.ceil(hDev / scale);
    canvas.width = cw;
    canvas.height = ch;
    cssPx = scale / dpr;
    canvas.style.width = cw * cssPx + 'px';
    canvas.style.height = ch * cssPx + 'px';
    g.imageSmoothingEnabled = false;
    layout();
    bgKey = '';
  }

  function layout() {
    const horizon = Math.round(ch * 0.55);
    const lane = Math.round(horizon + (ch - horizon) * 0.55);
    L = {
      horizon, lane,
      fenceX: Math.round(cw * 0.5),
      fieldTop: horizon + 3,
      fieldBot: lane - 9,
      belt: ch - lane >= 20 ? lane + 9 : null,
      queueX: Math.round(cw * 0.5) - 24,
    };
    const rnd = seeded(cw * 131 + ch);
    stars = [];
    const n = Math.round((cw * horizon) / 90);
    for (let i = 0; i < n; i++) {
      stars.push({ x: Math.floor(rnd() * cw), y: Math.floor(rnd() * (horizon - 12)), at: rnd(), ph: rnd() * TAU, big: rnd() < 0.12 });
    }
    stars.sort((a, b) => a.at - b.at);
  }

  // Scene pixels from a pointer event.
  function toGame(clientX, clientY) {
    const r = canvas.getBoundingClientRect();
    return [((clientX - r.left) / r.width) * cw, ((clientY - r.top) / r.height) * ch];
  }

  /* --- the backdrop: sky, hills, grass. Rebuilt only when the night deepens a step. */

  const SKY = ['b', 'l', 'i', 'p', 'v', 'n'];
  function hillY(x, stage) {
    let y = L.horizon - 5 - 3 * Math.sin(x * 0.045 + 1.3) - 2 * Math.sin(x * 0.11 + 0.4);
    if (stage >= 1) y -= 2 + 2 * Math.sin(x * 0.02 + 2);
    return Math.round(y);
  }
  function nearHillY(x) {
    return Math.round(L.horizon - 1 - 2.5 * Math.sin(x * 0.07 + 4) - 1.5 * Math.sin(x * 0.19));
  }

  function buildBackdrop(d, stage) {
    const c = document.createElement('canvas');
    c.width = cw; c.height = ch;
    const bgc = c.getContext('2d');
    const img = bgc.createImageData(cw, ch);
    const put = (x, y, k) => {
      const q = (y * cw + x) * 4, col = PAL.rgb[k];
      img.data[q] = col[0]; img.data[q + 1] = col[1]; img.data[q + 2] = col[2]; img.data[q + 3] = 255;
    };
    // Night over the ground: a step darker, dithered in as you get sleepy.
    const night = Math.min(1, d * 1.1);
    const dim = (x, y, k) => (dither(x, y, night) ? PAL.darker[k] : k);
    for (let x = 0; x < cw; x++) {
      const hy = hillY(x, stage), ny = nearHillY(x);
      for (let y = 0; y < ch; y++) {
        let k;
        if (y < hy) {
          // Sky: an index down the ramp, from the dusk glow at the horizon up;
          // the night pushes the whole ramp darker. Between two steps, dithered.
          const v = Math.max(0, Math.min(SKY.length - 1, (1 - y / L.horizon) * 2.1 + d * 3.3));
          const lo = Math.floor(v);
          k = SKY[Math.min(SKY.length - 1, dither(x, y, v - lo) ? lo + 1 : lo)];
        } else if (y < ny && y < L.horizon) {
          k = dim(x, y, y === hy ? 'g' : 't'); // far hills
          if (stage >= 1 && y === hy + 1 && x % 9 === 0) k = 's'; // a fence line along the far field
        } else {
          // Grass: lighter tufts in a loose pattern, a worn path along the lane.
          const h = (((x + 17) * 73856093) ^ ((y + 31) * 19349663)) >>> 0;
          k = 'g';
          if (y === ny || (h % 41 === 0 && y < L.lane - 4)) k = 'm';
          else if (h % 67 === 0) k = 't';
          if (Math.abs(y - (L.lane + 1)) <= 1 && dither(x, y, 0.55)) k = 'm';
          if (y > L.lane + 4 && h % 19 === 0) k = 't';
          k = dim(x, y, k);
        }
        put(x, y, k);
      }
    }
    bgc.putImageData(img, 0, 0);
    return c;
  }

  /* --- pieces */

  // Draw a painted sprite with its pivot at (x, y).
  function blit(sp, x, y) {
    g.drawImage(sp.c, Math.round(x) - sp.oi, Math.round(y) - sp.oj);
  }

  function px(k, x, y, w = 1, h = 1) {
    g.fillStyle = PAL.css[k];
    g.fillRect(Math.round(x), Math.round(y), w, h);
  }

  // A filled disc as rows of whole pixels, optionally dithered.
  function disc(k, cx, cy, r, dens = 1) {
    g.fillStyle = PAL.css[k];
    cx = Math.round(cx); cy = Math.round(cy);
    for (let dy = -r; dy <= r; dy++) {
      const hw = Math.round(Math.sqrt(Math.max(0, r * r - dy * dy)));
      for (let dx = -hw; dx <= hw; dx++) {
        if (dens < 1 && !dither(cx + dx, cy + dy, dens)) continue;
        g.fillRect(cx + dx, cy + dy, 1, 1);
      }
    }
  }

  function shadow(x, y, w) {
    w = Math.max(3, Math.round(w));
    for (let i = -w; i <= w; i++) if (dither(Math.round(x) + i, y, 0.6)) px('t', x + i, y);
  }

  const look = (stage) => (stage >= 2 ? 'pj' : 'plain');

  /* --- what the logic asks for */

  // A tap: a sheep from the queue runs and hops the fence, and the number pops.
  function tapped(value, s, at) {
    fx.fenceBounce = 1;
    fx.queueBob = 1;
    hop(L.queueX, value, s.stage, false);
    // Quick taps pile into one number that keeps growing, rather than a
    // stack of them on top of each other.
    const last = fx.floats[fx.floats.length - 1];
    if (last && last.tap && last.t < 0.35) {
      last.value = Num.add(last.value, value);
      last.text = '+' + Num.format(last.value);
      last.t = 0;
      last.pop = 1;
      last.x = Math.round(Math.max(2, Math.min(cw - Font.width(last.text, 2) - 2, last.cx - Font.width(last.text, 2) / 2)));
      return;
    }
    const text = '+' + Num.format(value);
    const cx = (at ? at[0] : L.fenceX) + (Math.random() * 16 - 8);
    floatText(text, Math.max(2, Math.min(cw - Font.width(text, 2) - 2, cx - Font.width(text, 2) / 2)), L.lane - 40, 'w');
    Object.assign(fx.floats[fx.floats.length - 1], { tap: true, value, cx, pop: 1 });
  }

  function hop(x0, value, stage, auto) {
    if (fx.hoppers.length >= C.visual.maxHoppers) return;
    const toOrbit = auto && stage >= 3 && Math.random() < 0.3;
    fx.hoppers.push({
      x: x0, t: 0, phase: 'run', ph: 0, z: Math.floor(Math.random() * 3) - 1,
      h: toOrbit ? 200 : 17 + Math.random() * 6, look: look(stage), orbit: toOrbit, speed: auto ? 62 : 90,
    });
  }

  function floatText(text, x, y, k, big) {
    fx.floats.push({ text, x: Math.round(x), y, t: 0, k, z: big ? 3 : 2, life: big ? 1.8 : 0.95 });
  }

  function burst(x, y, n, keys, power = 1) {
    if (reduced) n = Math.ceil(n / 3);
    for (let i = 0; i < n; i++) {
      const a = Math.random() * TAU;
      const v = (20 + Math.random() * 40) * power;
      fx.particles.push({ x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v * 0.7 - 25 * power, t: 0, life: 0.5 + Math.random() * 0.5, k: keys[i % keys.length] });
    }
  }

  // Where the golden sheep is, at progress p (0..1) across: logic keeps only
  // the time, so the tap test and the drawing both ask here.
  function goldenPos(gs) {
    const p = gs.t / C.golden.crossTime;
    const x = -14 + (cw + 28) * p;
    const base = L.horizon - 8 - gs.lane * L.horizon * 0.2; // below the counter, above the hills
    const y = base - Math.abs(Math.sin(p * Math.PI * 7)) * 7;
    return [x, y];
  }

  function hitGolden(s, gx, gy) {
    if (!s.golden) return false;
    const [x, y] = goldenPos(s.golden);
    return Math.hypot(gx - x, (gy - (y - 6)) * 1.2) < 16;
  }

  function goldenCaught(value, s) {
    const [x, y] = s.golden ? goldenPos(s.golden) : [cw / 2, L.horizon / 2];
    burst(x, y - 6, 28, ['y', 'w', 'h', 'y'], 1.4);
    const text = '+' + Num.format(value);
    floatText(text, Math.max(2, Math.min(cw - Font.width(text, 3) - 2, x - Font.width(text, 3) / 2)), y - 26, 'y', true);
    fx.flash = 1;
    if (!reduced) fx.shake = 0.35;
  }

  function bought(id) {
    // A puff of wool where the new thing appears.
    const where = {
      dog: [L.fenceX, L.fieldBot], meadow: [cw * 0.3, L.fieldTop + 4], pen: [cw * 0.8, L.fieldBot - 2],
      mill: [20, L.horizon - 10], drones: [cw * 0.5, L.horizon * 0.5], os: [cw - 16, L.fieldBot],
      betterFence: [L.fenceX, L.lane - 8], tapPower: [L.queueX, L.lane - 6], barn: [cw * 0.85, L.horizon - 4], lullaby: [cw / 2, L.horizon * 0.4],
    }[id] || [cw / 2, L.lane];
    burst(where[0], where[1], 12, ['w', 'l', 'm']);
    if (id === 'betterFence') { fx.fenceBounce = 1.5; if (!reduced) fx.shake = 0.15; }
  }

  /* --- per frame */

  function update(dt, s) {
    t += dt;
    const d = Logic.drowsiness(s);
    fx.fenceBounce = Math.max(0, fx.fenceBounce - dt * 6);
    fx.queueBob = Math.max(0, fx.queueBob - dt * 5);
    fx.shake = Math.max(0, fx.shake - dt);
    fx.flash = Math.max(0, fx.flash - dt * 3);

    // The generators send sheep over too, at a calm pace that grows with them.
    const rate = Num.toNumber(Logic.perSecond(s));
    if (rate > 0 && !s.asleep) {
      const per = Math.min(C.visual.autoHopsPerSecond, 0.35 + Math.log10(1 + rate) * 0.3);
      fx.autoAcc += dt * per;
      if (fx.autoAcc >= 1) { fx.autoAcc -= 1; hop(-12, 0, s.stage, true); }
    }

    for (const h of fx.hoppers) {
      h.t += dt;
      const jumpFrom = L.fenceX - 12, jumpTo = L.fenceX + 12;
      if (h.phase === 'run') {
        h.x += h.speed * dt;
        if (h.x >= jumpFrom) { h.phase = 'jump'; h.ph = 0; h.x = jumpFrom; }
      } else if (h.phase === 'jump') {
        h.ph += dt / (h.orbit ? 1.4 : 0.42);
        h.x = jumpFrom + (jumpTo - jumpFrom) * Math.min(1, h.ph) * (h.orbit ? 0.6 : 1);
        if (h.orbit && h.ph >= 0.5) { h.done = true; fx.launched.push({ x: h.x, y: L.lane - h.h * 0.5, t: 0 }); }
        else if (h.ph >= 1) {
          h.phase = 'land'; h.ph = 0; h.x = jumpTo;
          burst(h.x, L.lane, 4, ['m', 'w']);
          Game.cue('land');
        }
      } else if (h.phase === 'land') {
        h.ph += dt / 0.14;
        if (h.ph >= 1) h.phase = 'out';
      } else {
        h.x += h.speed * 0.9 * dt;
        if (h.x > cw + 16) h.done = true;
      }
    }
    fx.hoppers = fx.hoppers.filter((h) => !h.done);

    for (const l of fx.launched) { l.t += dt; l.y -= dt * 120; l.x += dt * 20; }
    fx.launched = fx.launched.filter((l) => l.y > -20);

    for (const p of fx.particles) {
      p.t += dt; p.x += p.vx * dt; p.y += p.vy * dt; p.vy += 140 * dt; p.vx *= 1 - dt * 2;
    }
    fx.particles = fx.particles.filter((p) => p.t < p.life);

    for (const f of fx.floats) f.t += dt;
    fx.floats = fx.floats.filter((f) => f.t < f.life);

    // Zzz from the queue, more of them the sleepier you are.
    if (d > 0.3 && !reduced) {
      fx.zAcc += dt * (d - 0.25) * 1.4;
      if (fx.zAcc >= 1) {
        fx.zAcc = 0;
        fx.zzz.push({ x: L.queueX - 10 + Math.random() * 16, y: L.lane - 14, t: 0, z: d > 0.75 && Math.random() < 0.4 ? 2 : 1, ph: Math.random() * TAU });
      }
    }
    for (const z of fx.zzz) z.t += dt;
    fx.zzz = fx.zzz.filter((z) => z.t < 2.6);

    // Chimney smoke and pen hearts.
    if (s.owned.mill > 0 || s.stage >= 2) {
      fx.smokeAcc += dt * 1.6;
      if (fx.smokeAcc >= 1) { fx.smokeAcc = 0; fx.smoke.push({ x: 30, y: L.horizon - 30, t: 0, r: 1 }); }
    }
    for (const sm of fx.smoke) { sm.t += dt; sm.y -= dt * 6; sm.x += dt * 4 + Math.sin(sm.t * 2) * dt * 2; }
    fx.smoke = fx.smoke.filter((sm) => sm.t < 4);
    if (s.owned.pen > 0) {
      fx.heartAcc += dt * 0.7;
      if (fx.heartAcc >= 1) { fx.heartAcc = 0; fx.hearts.push({ x: cw * 0.8 + Math.random() * 14 - 7, y: L.fieldBot - 10, t: 0 }); }
    }
    for (const h of fx.hearts) { h.t += dt; h.y -= dt * 7; }
    fx.hearts = fx.hearts.filter((h) => h.t < 1.8);

    // Eyelids: a resting droop near the end, blinks more and more often, and
    // shut for good when you fall asleep.
    const lids = fx.lids;
    if (s.asleep) lids.close = Math.min(1, lids.close + dt / 2.4);
    else lids.close = Math.max(0, lids.close - dt / 1.2);
    if (d > 0.55 && !s.asleep && !reduced) {
      lids.next -= dt;
      if (lids.next <= 0) {
        lids.blink = 1;
        lids.next = 2.5 + Math.random() * (10 - 9 * (d - 0.55) / 0.45);
      }
    }
    lids.blink = Math.max(0, lids.blink - dt / 0.38);
  }

  function render(s) {
    const d = Logic.drowsiness(s);
    const stage = s.stage;
    const key = `${cw}x${ch}.${Math.round(d * 48)}.${Math.min(stage, 1)}`;
    if (key !== bgKey) { bg = buildBackdrop(Math.round(d * 48) / 48, stage); bgKey = key; }

    g.save();
    if (fx.shake > 0 && !reduced) g.translate(Math.round((Math.random() - 0.5) * 4 * fx.shake), Math.round((Math.random() - 0.5) * 4 * fx.shake));
    g.drawImage(bg, 0, 0);

    drawSky(s, d);
    drawField(s, d);
    drawLane(s);
    drawBelt(s);
    drawOver(s, d);
    g.restore();
    drawLids(d);
  }

  function drawSky(s, d) {
    // Stars come out past a quarter of the way to sleep, and twinkle.
    const shown = (d - 0.2) / 0.6;
    for (const st of stars) {
      if (st.at > shown) break;
      if (st.y >= hillY(st.x, s.stage) - 1) continue;
      const tw = Math.sin(t * 1.3 + st.ph);
      if (tw < -0.85) continue;
      const k = tw > 0.6 ? 'w' : 'l';
      px(k, st.x, st.y);
      if (st.big && tw > 0.3) { px('l', st.x - 1, st.y); px('l', st.x + 1, st.y); px('l', st.x, st.y - 1); px('l', st.x, st.y + 1); }
    }

    // The moon rises with drowsiness; in Orbit, sheep circle it.
    if (d > 0.3 || s.stage >= 3) {
      const rise = Math.min(1, (d - 0.3) / 0.5);
      const mx = cw - Math.max(16, cw * 0.16), my = Math.round(L.horizon - 6 - rise * (L.horizon * 0.6));
      const orbiting = s.stage >= 3 ? 3 + Math.min(6, s.owned.os + Math.floor(s.owned.drones / 10)) : 0;
      const orbit = [];
      for (let i = 0; i < orbiting; i++) {
        const a = t * 0.45 + (i * TAU) / orbiting;
        orbit.push({ a, x: mx + Math.cos(a) * 18, y: my + Math.sin(a) * 5 - 2 });
      }
      const sheepAt = (o) => blit(Models.sheep(o.a + Math.PI / 2, 0, 2, 'pj', false, 0.5), o.x, o.y + 3);
      for (const o of orbit) if (Math.sin(o.a) < 0) sheepAt(o);
      blit(Models.moon(9), mx, my);
      for (const o of orbit) if (Math.sin(o.a) >= 0) sheepAt(o);
    }

    // The sheep the Orbit stage sends straight up.
    for (const l of fx.launched) {
      blit(Models.sheep(-Math.PI / 2 + 0.6, -2, 2, 'pj'), l.x, l.y);
      if (Math.floor(t * 20) % 2) px('y', l.x - 1, l.y + 2, 2, 2);
    }

    // Drones on patrol, a light blinking on each.
    const drones = s.owned.drones > 0 ? Math.min(5, 1 + Math.floor(s.owned.drones / 8)) : 0;
    for (let i = 0; i < drones; i++) {
      const ph = i * 2.1;
      const x = cw / 2 + Math.sin(t * 0.35 + ph) * cw * 0.38;
      const y = L.horizon * 0.62 + Math.sin(t * 0.8 + ph * 1.7) * 6 - i * 3;
      const vx = Math.cos(t * 0.35 + ph);
      blit(Models.drone(vx > 0.3 ? 1 : vx < -0.3 ? -1 : 0), x, y);
      if ((Math.floor(t * 2 + i) & 1) === 0) px('y', x, y - 2);
      // ...and a dithered beam straight down when it is counting.
      if (Math.sin(t * 0.9 + ph) > 0.85) for (let yy = y + 3; yy < L.horizon; yy++) if (dither(Math.round(x), yy, 0.25)) px('y', x, yy);
    }

    // The Wool Mill, behind the hills.
    if (s.owned.mill > 0 || s.stage >= 2) {
      const fx0 = 6, fy = L.horizon - 18;
      px('o', fx0 - 1, fy - 1, 30, 20);
      px('p', fx0, fy, 28, 18);
      for (let i = 0; i < 4; i++) { // a sawtooth roof
        for (let r = 0; r < 4; r++) { px('o', fx0 + i * 7 + r, fy - 1 - r, 1, 1); px('i', fx0 + i * 7 + r, fy - r, 1, r); }
        px('o', fx0 + i * 7 + 4, fy - 5, 1, 5);
      }
      px('o', fx0 + 21, fy - 14, 6, 14); px('s', fx0 + 22, fy - 13, 4, 13); // chimney
      for (let i = 0; i < 3; i++) {
        const lit = Math.sin(t * 1.5 + i * 2) > -0.6;
        px(lit ? 'y' : 'h', fx0 + 3 + i * 8, fy + 5, 4, 4);
      }
      for (const sm of fx.smoke) disc(sm.t < 2 ? 'w' : 'b', sm.x, sm.y, 1 + Math.floor(sm.t * 0.8), Math.max(0.15, 0.8 - sm.t * 0.2));
    }
  }

  function drawField(s, d) {
    const stage = s.stage;
    const things = [];
    // Grazing sheep, a few more with each Meadow.
    const grazers = s.owned.meadow > 0 ? Math.min(9, 1 + Math.ceil(s.owned.meadow / 3)) : 0;
    const rnd = seeded(77);
    for (let i = 0; i < grazers; i++) {
      const bx = rnd() * cw, by = L.fieldTop + 2 + rnd() * (L.fieldBot - L.fieldTop - 2);
      const dir = rnd() < 0.5 ? 1 : -1;
      const x = ((bx + dir * t * 1.2 + cw + 20) % (cw + 20)) - 10;
      const graze = Math.sin(t * 0.7 + i * 1.9) > -0.2;
      things.push({ y: by, draw: () => blit(Models.sheep(dir > 0 ? 0.3 : Math.PI - 0.3, 0, 0, look(stage), graze, 0.75), x, by) });
    }
    // Dogs, running loops round the field.
    const dogs = s.owned.dog > 0 ? Math.min(3, 1 + Math.floor(s.owned.dog / 15)) : 0;
    for (let i = 0; i < dogs; i++) {
      const a = t * (0.55 + i * 0.12) + i * 2.2;
      const rx = cw * 0.38, ry = (L.fieldBot - L.fieldTop) / 2;
      const x = L.fenceX + Math.cos(a) * rx, y = (L.fieldTop + L.fieldBot) / 2 + Math.sin(a) * ry;
      const vx = -Math.sin(a) * rx, vy = Math.cos(a) * ry;
      const h = Math.atan2(vy / Tracer.SE, vx);
      const gait = Math.floor(t * 12 + i) % 4;
      things.push({ y, draw: () => blit(Models.dog(h, gait), x, y) });
    }
    // The Breeding Pen: a little fold of bouncing lambs.
    if (s.owned.pen > 0) {
      const x0 = Math.round(cw * 0.8) - 11, y0 = L.fieldBot - 3;
      const lambs = Math.min(4, 1 + Math.floor(s.owned.pen / 8));
      things.push({
        y: y0, draw: () => {
          px('o', x0 - 1, y0 - 7, 24, 1); px('b', x0, y0 - 6, 22, 1);
          for (let i = 0; i < lambs; i++) {
            const b = Math.abs(Math.sin(t * 3 + i * 1.3)) * 3;
            blit(Models.sheep(i % 2 ? 0.4 : Math.PI - 0.4, 0, b > 1.5 ? 2 : 0, look(stage), false, 0.55), x0 + 4 + i * 5, y0 - 1 - b);
          }
          px('o', x0 - 1, y0 - 2, 24, 1); px('b', x0, y0 - 1, 22, 1);
          for (const xx of [x0 - 1, x0 + 10, x0 + 21]) { px('o', xx, y0 - 8, 2, 9); px('s', xx, y0 - 7, 1, 7); }
        },
      });
      for (const h of fx.hearts) things.push({ y: 999, draw: () => drawHeart(h.x, h.y, h.t) });
    }
    // Sheep-OS: a terminal in the grass, counting.
    if (s.owned.os > 0) {
      const x0 = cw - 26, y0 = L.fieldBot - 14;
      things.push({
        y: y0 + 14, draw: () => {
          px('o', x0 - 1, y0 - 1, 22, 16); px('s', x0, y0, 20, 14); px('n', x0 + 2, y0 + 2, 16, 9);
          for (let r = 0; r < 3; r++) {
            const n = Math.floor(t * 6 + r * 3) % 13;
            for (let i = 0; i < n; i++) if ((i * 7 + r + Math.floor(t * 4)) % 5) px(r === 2 ? 'y' : 'm', x0 + 3 + i, y0 + 3 + r * 3);
          }
          px('o', x0 + 8, y0 + 14, 4, 2); px('o', x0 + 5, y0 + 15, 10, 1);
        },
      });
    }
    things.sort((a, b) => a.y - b.y);
    for (const th of things) th.draw();
  }

  function drawHeart(x, y, tt) {
    const dens = tt > 1.2 ? 1 - (tt - 1.2) / 0.6 : 1;
    const rows = ['.l.l.', 'lllll', '.lll.', '..l..'];
    rows.forEach((row, r) => { for (let c = 0; c < 5; c++) if (row[c] === 'l' && (dens >= 1 || dither(Math.round(x) + c, Math.round(y) + r, dens))) px('l', x + c - 2, y + r); });
  }

  function drawLane(s) {
    const stage = s.stage;
    const lane = L.lane;
    // The queue: three sheep waiting their turn, dozing as the night goes on.
    const bob = fx.queueBob;
    for (let i = 2; i >= 0; i--) {
      const x = L.queueX - i * 14 - 2;
      if (x < -10) continue;
      const breathe = Math.sin(t * 1.4 + i) > 0.6 ? 1 : 0;
      shadow(x, lane + 1, 6);
      blit(Models.sheep(0.35, i === 0 && bob > 0.5 ? 1 : breathe, 0, look(stage)), x, lane - (i === 0 ? Math.round(bob * 2) : 0));
    }
    // The hoppers, then the fence over them, so they sail over its rails.
    for (const h of fx.hoppers) {
      let y = lane + h.z, squash = 0, leg = Math.floor(h.x / 4) % 2;
      if (h.phase === 'jump') {
        const p = Math.min(1, h.ph);
        y -= Math.sin(p * Math.PI) * h.h * (h.orbit ? Math.max(1, p * 2) : 1);
        leg = 2;
        squash = p < 0.12 ? 1 : p < 0.4 ? -2 : p < 0.7 ? -1 : 0;
        shadow(h.x, lane + 1, 6 - Math.sin(p * Math.PI) * 3);
      } else {
        shadow(h.x, lane + 1, 6);
        if (h.phase === 'land') { squash = h.ph < 0.5 ? 3 : 1; leg = 0; }
      }
      if (reduced) squash = 0;
      blit(Models.sheep(0.35, squash, leg, h.look), h.x, y);
    }
    const fb = fx.fenceBounce;
    const sq = reduced ? 0 : fb > 0.6 ? 2 : fb > 0.2 ? 1 : 0;
    blit(Models.fence(s.owned.betterFence, sq), L.fenceX, lane + 3);
  }

  function drawBelt(s) {
    if (L.belt === null || s.stage < 2) return;
    const y = L.belt;
    px('o', 0, y - 1, cw, 7);
    px('s', 0, y, cw, 2);
    px('p', 0, y + 2, cw, 3);
    const off = Math.floor(t * 18) % 8;
    for (let x = -8 + off; x < cw; x += 8) { px('b', x, y, 3, 1); px('o', x + 3, y + 2, 1, 3); }
    // Pajama sheep riding it to wherever sheep go.
    const riders = Math.min(7, 2 + Math.floor(s.owned.mill / 4));
    for (let i = 0; i < riders; i++) {
      const x = ((i * (cw + 24)) / riders + t * 18) % (cw + 24) - 12;
      blit(Models.sheep(0.1, 0, 0, 'pj', false, 0.8), x, y + 1);
    }
  }

  function drawOver(s, d) {
    for (const p of fx.particles) px(p.k, p.x, p.y);
    for (const z of fx.zzz) {
      const dens = z.t > 1.8 ? 1 - (z.t - 1.8) / 0.8 : 1;
      Font.label(g, 'z', Math.round(z.x + Math.sin(z.t * 2 + z.ph) * 3), Math.round(z.y - z.t * 9), 'l', z.z, dens);
    }
    if (s.golden) drawGolden(s.golden);
    for (const f of fx.floats) {
      const p = f.t / f.life;
      const rise = reduced ? 0 : (1 - Math.pow(1 - Math.min(1, p * 1.4), 3)) * (f.z > 1 ? 18 : 14);
      const dens = p > 0.65 ? 1 - (p - 0.65) / 0.35 : 1;
      // A pop at the start: the big ones land a pixel high, then settle.
      const popUp = f.pop && f.t < 0.08 && !reduced ? 1 : 0;
      Font.label(g, f.text, f.x, Math.round(f.y - rise) - popUp, f.k, f.z, dens);
    }
    if (fx.flash > 0) {
      for (let y = 0; y < ch; y += 1) for (let x = 0; x < cw; x += 1) if (dither(x, y, fx.flash * 0.25)) px('y', x, y);
    }
  }

  function drawGolden(gs) {
    const [x, y] = goldenPos(gs);
    const p = gs.t / C.golden.crossTime;
    // A sparkle trail, then the sheep itself, glowing.
    for (let i = 1; i < 6; i++) {
      const [tx, ty] = goldenPos({ t: Math.max(0, gs.t - i * 0.08), lane: gs.lane });
      if ((Math.floor(t * 14) + i) % 2) px(i < 3 ? 'y' : 'w', tx - 6 + Math.sin(i * 3 + t * 9) * 2, ty - 4 + Math.cos(i * 2) * 2);
    }
    const air = Math.abs(Math.sin(p * Math.PI * 7));
    blit(Models.sheep(0.25, air < 0.15 ? 1 : -1, air > 0.15 ? 2 : 0, 'gold'), x, y);
    if (Math.floor(t * 6) % 2) { px('w', x + 6, y - 15); px('w', x - 8, y - 10); }
  }

  function drawLids(d) {
    const l = fx.lids;
    const rest = d > 0.85 ? (d - 0.85) / 0.15 * 0.18 : 0;
    const blink = l.blink > 0 ? Math.sin(l.blink * Math.PI) : 0;
    const amt = Math.min(1, Math.max(rest, blink * 0.9, l.close));
    if (amt <= 0) return;
    const half = ch / 2 + 2;
    const top = Math.round(half * amt);
    px('n', 0, 0, cw, top - 2);
    for (let y = Math.max(0, top - 2); y < top + 2; y++) for (let x = 0; x < cw; x++) if (dither(x, y, 1 - (y - (top - 2)) / 4)) px('n', x, y);
    const bot = ch - Math.round(half * amt);
    px('n', 0, bot + 2, cw, ch - bot);
    for (let y = bot - 2; y < bot + 2; y++) for (let x = 0; x < cw; x++) if (dither(x, y, (y - (bot - 2)) / 4)) px('n', x, y);
    // Lashes, when nearly shut.
    if (amt > 0.6 && amt < 1) for (let x = 6; x < cw; x += 7) { px('o', x, top + 1); px('o', x + 1, top + 2); }
  }

  // A sprite painted into a small canvas, for a shop card.
  function icon(id) {
    const c = document.createElement('canvas');
    c.width = 28; c.height = 22;
    const ig = c.getContext('2d');
    ig.imageSmoothingEnabled = false;
    const put = (sp, x, y) => ig.drawImage(sp.c, Math.round(x) - sp.oi, Math.round(y) - sp.oj);
    const art = (rows, x0, y0) => rows.forEach((row, r) => { for (let i = 0; i < row.length; i++) if (row[i] !== '.') { ig.fillStyle = PAL.css[row[i]]; ig.fillRect(x0 + i, y0 + r, 1, 1); } });
    switch (id) {
      case 'tapPower': art(ICONS.hand, 7, 2); break;
      case 'betterFence': put(Models.fence(1, 0), 14, 19); break;
      case 'dog': put(Models.dog(0.4, 1), 14, 18); break;
      case 'meadow': put(Models.sheep(0.35, 0, 0, 'plain', true), 13, 19); art(['m.m...m..m', '.g..m..gm.'], 7, 19); break;
      case 'pen': put(Models.sheep(0.4, 0, 0, 'plain', false, 0.6), 8, 18); put(Models.sheep(Math.PI - 0.4, 0, 0, 'plain', false, 0.6), 20, 18); art(['.l.l.', 'lllll', '.lll.', '..l..'], 12, 1); break;
      case 'mill': put(Models.sheep(0.35, 0, 0, 'pj'), 13, 19); break;
      case 'drones': put(Models.drone(0), 14, 11); art(['y'], 14, 7); break;
      case 'os': art(ICONS.os, 5, 2); break;
      case 'barn': art(ICONS.barn, 6, 2); break;
      case 'lullaby': art(ICONS.lullaby, 6, 2); break;
      default: break;
    }
    return c;
  }

  const ICONS = {
    hand: [
      '.y...oo.....',
      '..y.owwo....',
      '....owwo....',
      'yy..owwoooo.',
      '....owwowwooo',
      '....owwowwowwo',
      '.ooooww.wwowwo',
      'owwowwwwwwwwwo',
      'owwwwwwwwwwwwo',
      '.owwwwwwwwwwbo',
      '..owwwwwwwwbo.',
      '...owwwwwwbo..',
      '....obbbbbo...',
      '.....ooooo....',
    ],
    os: [
      'oooooooooooooooooo',
      'osssssssssssssssso',
      'osnnnnnnnnnnnnnnso',
      'osnmmnmnmmmnnnnnso',
      'osnnnnnnnnnnnnnnso',
      'osnmmmnmnmmnnnnnso',
      'osnnnnnnnnnnnnnnso',
      'osnyynyyynynnnnnso',
      'osnnnnnnnnnnnnnnso',
      'osnmyyyyyyyyyyy_so'.replace('_', 'n'),
      'osnnnnnnnnnnnnnnso',
      'osssssssssssssssso',
      'oooooooooooooooooo',
      '.......oooo.......',
      '.....oooooooo.....',
    ],
    barn: [
      '........o........',
      '......ooiooo.....',
      '....ooiiiiioo....',
      '..ooiiiiiiiiioo..',
      '.oiiiiiwwwiiiiio.',
      'ooooooowwwooooooo',
      '.opppppppppppppo.',
      '.opwwwwwwwwwwwpo.',
      '.opwpwpwowpwpwpo.',
      '.opwwpwwowwpwwpo.',
      '.opwpwpwowpwpwpo.',
      '.opwwwwwowwwwwpo.',
      '.opppppppppppppo.',
      'ooooooooooooooooo',
    ],
    lullaby: [
      '...oooo..........',
      '..owwwo......oo..',
      '.owwwo.......olo.',
      '.owwo........olo.',
      'owwwo........ol..',
      'owwwo........ol..',
      'owwwwo.....oool..',
      '.owwwwo...olllo..',
      '.owwwwwooooolo...',
      '..owwwwwwwo.oo...',
      '...ooowwoo.......',
      '......oo.........',
      '..y.......y......',
      '......y..........',
    ],
  };

  return {
    init, resize, setReduced, update, render, tapped, goldenCaught, bought, hitGolden, toGame, icon, fx,
    get size() { return [cw, ch, cssPx]; },
  };
})();

/* ========================================================== 4. UI and boot */

const Game = (() => {
  const C = CONFIG;
  const $ = (id) => document.getElementById(id);
  const params = new URLSearchParams(location.search);
  // Hidden debug: ?speed=10 runs the rules ten times as fast.
  const speed = Math.max(1, Math.min(1000, Number(params.get('speed')) || 1));
  const motionQuery = window.matchMedia ? matchMedia('(prefers-reduced-motion: reduce)') : { matches: false };
  let reduced = motionQuery.matches;

  let S = Logic.fresh();
  let shownCount = 0;
  let lastLine = '';
  let shopSig = '';
  const cards = {};
  let endingTimer = null;

  const cue = (name, data) => Sound.cue(name, data);

  /* --- saving */

  function save() {
    try { localStorage.setItem(C.save.key, Logic.serialize(S)); } catch (e) { /* private mode: play on unsaved */ }
  }

  function load() {
    let raw = null;
    try { raw = localStorage.getItem(C.save.key); } catch (e) { raw = null; }
    if (!raw) return false;
    const s = Logic.deserialize(raw);
    if (!s) return false;
    S = s;
    return true;
  }

  /* --- away: offline progress */

  function away(seconds) {
    const r = Logic.offline(S, seconds);
    if (!r || seconds < C.offline.minSeconds || !Num.gte(r.gain, Num.from(1))) return;
    showModal({
      title: 'While you were dreaming...',
      body: `<p>Your helpers kept counting for <b>${duration(r.secs)}</b>${r.capped ? ` (dreams last ${C.offline.maxHours} hours at most)` : ''}.</p>
             <p class="big">+${Num.format(r.gain)} sheep</p>`,
      button: S.asleep ? 'Oh...' : 'Wake up gently',
    });
  }

  function duration(secs) {
    secs = Math.floor(secs);
    const h = Math.floor(secs / 3600), m = Math.floor((secs % 3600) / 60), s = secs % 60;
    if (h) return `${h}h ${m}m`;
    if (m) return `${m}m ${s}s`;
    return `${s}s`;
  }

  /* --- dialogs */

  function showModal({ title, body, button, onClose, night }) {
    const m = $('modal');
    m.classList.toggle('night', !!night);
    $('modalTitle').textContent = title;
    $('modalBody').innerHTML = body;
    const b = $('modalButton');
    b.textContent = button;
    b.onclick = () => {
      Sound.init();
      m.classList.remove('open');
      m.setAttribute('aria-hidden', 'true');
      setTimeout(() => { if (!m.classList.contains('open')) m.hidden = true; }, 400);
      if (onClose) onClose();
      if (endingWaits) { endingWaits = false; setTimeout(showEnding, 500); }
    };
    m.hidden = false;
    m.setAttribute('aria-hidden', 'false');
    requestAnimationFrame(() => m.classList.add('open'));
    setTimeout(() => b.focus(), 50);
  }

  const modalOpen = () => $('modal').getAttribute('aria-hidden') === 'false';
  let endingWaits = false;

  function showEnding() {
    if (!S.asleep) return;
    if (modalOpen()) { endingWaits = true; return; }
    const gain = Logic.dreamPointsFor(S);
    const after = S.dreamPoints + gain;
    showModal({
      night: true,
      title: 'You fell asleep.',
      body: `<p>You counted <b>${Num.format(S.runTotal)}</b> sheep${S.runTime > 1 ? ` in ${duration(S.runTime)}` : ''}.</p>
             <p class="big">+${gain} Dream Point${gain === 1 ? '' : 's'}</p>
             <p>Each one makes every sheep count ${Math.round(C.prestige.bonusPerPoint * 100)}% more, forever.<br>
             With ${after}: <b>+${Math.round(after * C.prestige.bonusPerPoint * 100)}%</b> production.</p>`,
      button: 'Dream Again',
      onClose: () => {
        Logic.dreamAgain(S);
        Sound.setAsleep(false);
        shownCount = 0;
        shopSig = '';
        save();
        banner('A new night', 'The sheep are waiting');
      },
    });
  }

  function banner(title, sub) {
    const b = $('banner');
    b.innerHTML = `<b>${title}</b>${sub ? `<span>${sub}</span>` : ''}`;
    b.classList.remove('show');
    void b.offsetWidth;
    b.classList.add('show');
    clearTimeout(banner.timer);
    banner.timer = setTimeout(() => b.classList.remove('show'), 3000);
  }

  /* --- the shop */

  function describe(it) {
    const o = S.owned[it.id];
    const gm = Logic.globalMult(S);
    switch (it.kind) {
      case 'gen': {
        const each = Num.mul(Num.from(it.rate), gm);
        return o ? `+${Num.format(each, true)}/s each · ${Num.format(Logic.genRate(S, it.id), true)}/s` : `${it.desc} · +${Num.format(each, true)}/s`;
      }
      case 'tap':
        return `${it.desc} · now ${Num.format(Logic.tapValue(S))} a tap`;
      default:
        if (it.max) return `${it.desc} · ${o}/${it.max}`;
        return `${it.desc} · now ×${(1 + it.add * o).toFixed(2).replace(/\.?0+$/, '')}`;
    }
  }

  function card(it) {
    const el = document.createElement('button');
    el.className = 'card ' + it.kind;
    el.type = 'button';
    el.dataset.id = it.id;
    const ic = document.createElement('div');
    ic.className = 'icon';
    ic.appendChild(Scene.icon(it.id));
    el.appendChild(ic);
    el.insertAdjacentHTML('beforeend', `
      <div class="info">
        <div class="name"><span class="label"></span><span class="owned"></span></div>
        <div class="desc"></div>
      </div>
      <div class="price"><span class="cost"></span><span class="qty"></span></div>`);
    el.addEventListener('click', () => buyClicked(it.id, el));
    const ref = { el, label: el.querySelector('.label'), owned: el.querySelector('.owned'), desc: el.querySelector('.desc'), cost: el.querySelector('.cost'), qty: el.querySelector('.qty'), last: {} };
    ref.label.textContent = it.name;
    return ref;
  }

  function teaserCard(id) {
    const it = Logic.BY_ID[id];
    const prev = Logic.GENS[it.index - 1];
    const el = document.createElement('div');
    el.className = 'card locked';
    el.innerHTML = `<div class="icon"><span>?</span></div><div class="info"><div class="name">???</div><div class="desc">Own a ${prev.name} to find out</div></div>`;
    return el;
  }

  function buildShop() {
    const sections = { tap: $('listTap'), gen: $('listGen'), mult: $('listMult') };
    const vis = Logic.ITEMS.filter((it) => Logic.visible(S, it.id)).map((it) => it.id);
    const tease = Logic.teaser(S);
    const sig = vis.join(',') + '|' + tease;
    if (sig === shopSig) return;
    const fresh = shopSig !== '';
    const before = new Set(shopSig.split('|')[0].split(','));
    shopSig = sig;
    for (const k of Object.keys(sections)) sections[k].innerHTML = '';
    for (const it of Logic.ITEMS) {
      if (!vis.includes(it.id)) continue;
      if (!cards[it.id]) cards[it.id] = card(it);
      const ref = cards[it.id];
      ref.last = {};
      sections[it.kind].appendChild(ref.el);
      if (fresh && !before.has(it.id) && !reduced) {
        ref.el.classList.add('reveal');
        setTimeout(() => ref.el.classList.remove('reveal'), 700);
      }
    }
    if (tease) sections.gen.appendChild(teaserCard(tease));
    $('secTap').hidden = !sections.tap.children.length;
    $('secMult').hidden = !sections.mult.children.length;
  }

  function set(ref, key, value, apply) {
    if (ref.last[key] === value) return;
    ref.last[key] = value;
    apply(value);
  }

  function updateShop() {
    buildShop();
    for (const it of Logic.ITEMS) {
      const ref = cards[it.id];
      if (!ref || !ref.el.isConnected) continue;
      const q = Logic.quote(S, it.id, S.buyMode);
      set(ref, 'afford', q.ok && !S.asleep, (v) => ref.el.classList.toggle('afford', v));
      set(ref, 'maxed', q.maxed, (v) => ref.el.classList.toggle('maxed', v));
      set(ref, 'cost', q.maxed ? 'Done' : Num.format(q.cost), (v) => { ref.cost.textContent = v; });
      set(ref, 'qty', q.maxed ? '' : '×' + q.n, (v) => { ref.qty.textContent = v; });
      set(ref, 'owned', S.owned[it.id] ? String(S.owned[it.id]) : '', (v) => { ref.owned.textContent = v; });
      set(ref, 'desc', describe(it), (v) => { ref.desc.textContent = v; });
      set(ref, 'aria', `${it.name}, ${S.owned[it.id]} owned, ${q.maxed ? 'maxed' : `costs ${Num.format(q.cost)} sheep for ${q.n}`}`, (v) => ref.el.setAttribute('aria-label', v));
    }
  }

  function buyClicked(id, el) {
    Sound.init();
    const it = Logic.BY_ID[id];
    const first = S.owned[id] === 0;
    const q = Logic.buy(S, id, S.buyMode);
    if (!q) {
      cue('nope');
      if (!reduced) { el.classList.remove('nope'); void el.offsetWidth; el.classList.add('nope'); }
      return;
    }
    cue('buy', { tier: it.kind === 'gen' ? it.index : it.kind === 'mult' ? 3 : 1, first });
    if (navigator.vibrate) try { navigator.vibrate(8); } catch (e) { /* ignore */ }
    Scene.bought(id);
    if (!reduced) {
      el.classList.remove('pop'); void el.offsetWidth; el.classList.add('pop');
      confetti(el);
    }
    if (first && it.kind === 'gen') banner(`New helper: ${it.name}`, it.desc);
    if (it.id === 'lullaby') Sound.setLullabies(S.owned.lullaby);
    updateShop();
  }

  // Little squares of wool and lavender out of the price.
  function confetti(el) {
    const r = el.querySelector('.price').getBoundingClientRect();
    const keys = ['w', 'l', 'y', 'b'];
    for (let i = 0; i < 10; i++) {
      const p = document.createElement('i');
      p.className = 'bit';
      p.style.left = r.left + r.width / 2 + 'px';
      p.style.top = r.top + r.height / 2 + 'px';
      p.style.background = PAL.css[keys[i % keys.length]];
      document.body.appendChild(p);
      const a = Math.random() * Math.PI * 2, v = 30 + Math.random() * 50;
      p.animate([
        { transform: 'translate(-50%,-50%) scale(1)', opacity: 1 },
        { transform: `translate(calc(-50% + ${Math.cos(a) * v}px), calc(-50% + ${Math.sin(a) * v - 20}px)) scale(0.4)`, opacity: 0 },
      ], { duration: 520 + Math.random() * 200, easing: 'cubic-bezier(.2,.7,.3,1)' }).onfinish = () => p.remove();
    }
  }

  function setBuyMode(m) {
    S.buyMode = m;
    for (const b of document.querySelectorAll('.buymode button')) b.setAttribute('aria-pressed', String(b.dataset.mode === m));
    updateShop();
  }

  /* --- the HUD */

  function updateHud(dt) {
    const real = Num.toNumber(S.sheep);
    // The counter rolls up to the real number instead of jumping.
    shownCount = real < shownCount ? real : shownCount + (real - shownCount) * Math.min(1, dt * 12);
    if (Math.abs(real - shownCount) < 0.5) shownCount = real;
    $('count').textContent = Num.format(shownCount);
    const rate = Logic.perSecond(S);
    $('rate').textContent = `${Num.format(rate, true)} per second · ${Num.format(Logic.tapValue(S))} a tap`;
    const d = Logic.drowsiness(S);
    const pct = Math.floor(d * 100);
    $('drowsyFill').style.width = d * 100 + '%';
    $('drowsyPct').textContent = pct + '%';
    $('drowsy').setAttribute('aria-valuenow', String(pct));
    $('drowsy').classList.toggle('heavy', d > 0.85);
    document.documentElement.style.setProperty('--night', d.toFixed(3));
    const line = Logic.currentLine(S);
    if (line !== lastLine) {
      lastLine = line;
      const el = $('line');
      el.classList.remove('in'); void el.offsetWidth;
      el.textContent = line;
      el.classList.add('in');
    }
    $('hint').classList.toggle('gone', S.taps >= 3 || S.dreams > 0 || S.asleep);
    const dp = $('dp');
    dp.hidden = S.dreamPoints <= 0;
    $('dpVal').textContent = `${S.dreamPoints} · +${Math.round(S.dreamPoints * C.prestige.bonusPerPoint * 100)}%`;
    Sound.setDrowsy(d);
  }

  function bump() {
    if (reduced) return;
    $('count').animate([{ transform: 'scale(1.1)' }, { transform: 'scale(1)' }], { duration: 160, easing: 'ease-out' });
  }

  /* --- events from the rules */

  function drain() {
    while (Logic.events.length) {
      const e = Logic.events.shift();
      if (e.type === 'stage') {
        const st = C.stages[e.stage];
        banner(st.name, st.title);
        cue('stage');
      } else if (e.type === 'goldenAppears') {
        cue('goldenAppears');
      } else if (e.type === 'asleep') {
        cue('asleep');
        Sound.setAsleep(true);
        save();
        clearTimeout(endingTimer);
        endingTimer = setTimeout(showEnding, reduced ? 600 : 2800);
      }
    }
  }

  /* --- input */

  function tapAt(clientX, clientY) {
    Sound.init();
    if (S.asleep) return;
    const [gx, gy] = clientX === null ? [null, null] : Scene.toGame(clientX, clientY);
    if (gx !== null && Scene.hitGolden(S, gx, gy)) {
      const v = Logic.catchGolden(S);
      Scene.goldenCaught(v, S);
      cue('golden');
      if (navigator.vibrate) try { navigator.vibrate([10, 40, 10]); } catch (e) { /* ignore */ }
      bump();
      return;
    }
    const v = Logic.tap(S);
    Scene.tapped(v, S, gx === null ? null : [gx, gy]);
    cue('tap');
    bump();
  }

  function bindInput() {
    const scene = $('scene');
    scene.addEventListener('pointerdown', (e) => {
      if (e.button !== undefined && e.button > 0) return;
      e.preventDefault();
      tapAt(e.clientX, e.clientY);
    });
    scene.addEventListener('keydown', (e) => {
      if (e.repeat) return;
      if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); tapAt(null, null); }
    });
    // Space anywhere outside a button counts too, on a computer.
    document.addEventListener('keydown', (e) => {
      if (e.repeat || e.target.closest('button, input') || e.target === scene) return;
      if (e.key === ' ') { e.preventDefault(); tapAt(null, null); }
    });
    for (const b of document.querySelectorAll('.buymode button')) b.addEventListener('click', () => { Sound.init(); setBuyMode(b.dataset.mode); });
    $('mute').addEventListener('click', () => {
      Sound.init();
      S.muted = !S.muted;
      Sound.setMuted(S.muted);
      $('mute').setAttribute('aria-pressed', String(S.muted));
      $('mute').classList.toggle('off', S.muted);
      save();
    });
    // The first touch anywhere is the gesture that lets sound start.
    document.addEventListener('pointerdown', () => Sound.init(), { once: true });
    if (motionQuery.addEventListener) motionQuery.addEventListener('change', (e) => { reduced = e.matches; Scene.setReduced(reduced); });
    new ResizeObserver(() => Scene.resize()).observe(scene);
    document.addEventListener('visibilitychange', () => { if (document.hidden) save(); });
    window.addEventListener('pagehide', save);
    window.addEventListener('beforeunload', save);
  }

  /* --- the loop: rules on a fixed step, drawing on every frame */

  const STEP = 1 / C.tickRate;
  let acc = 0, last = 0, lastWall = 0, saveIn = C.save.intervalSeconds;

  function frame(now) {
    const wall = Date.now();
    const gap = (wall - lastWall) / 1000;
    lastWall = wall;
    let dt = Math.min(0.25, Math.max(0, (now - last) / 1000));
    last = now;
    // Gone a while (a background tab stops the frames): that counts as away.
    if (gap > 5) { away(gap); dt = 0; }
    acc += dt * speed;
    let n = 0;
    while (acc >= STEP && n < 2000) { Logic.step(S, STEP); acc -= STEP; n++; }
    if (n >= 2000) acc = 0;
    drain();
    Scene.update(dt, S);
    Scene.render(S);
    updateHud(dt);
    updateShop();
    saveIn -= dt;
    if (saveIn <= 0) { saveIn = C.save.intervalSeconds; save(); }
    requestAnimationFrame(frame);
  }

  function boot() {
    const had = load();
    Scene.init($('view'), { reduced });
    Sound.setMuted(S.muted);
    Sound.setLullabies(S.owned.lullaby);
    $('mute').setAttribute('aria-pressed', String(S.muted));
    $('mute').classList.toggle('off', S.muted);
    setBuyMode(S.buyMode);
    bindInput();
    shownCount = Num.toNumber(S.sheep);
    if (had) {
      if (S.asleep) { Scene.fx.lids.close = 1; Sound.setAsleep(true); showEnding(); }
      else away((Date.now() - S.lastSeen) / 1000);
    }
    last = performance.now();
    lastWall = Date.now();
    if (speed > 1) console.info(`Counting Sheep: speed x${speed}`);
    requestAnimationFrame(frame);
  }

  return { boot, cue, get state() { return S; } };
})();

if (typeof document !== 'undefined' && document.getElementById('view')) Game.boot();
