# Counting Sheep

A cozy bedtime incremental game. You count sheep to fall asleep: tap the fence and a
sheep hops over. It starts with one fence at dusk and ends with sheep in orbit and an
AI counting for you. The numbers get bigger while the sky gets darker, and when the
Drowsiness bar fills you fall asleep. Then you can Dream Again, keeping Dream Points
that make every sheep count for more.

It's mobile-first (portrait, the shop under your thumb) and works on desktop (the
field on the left, the shop on the right, and Space taps). No dependencies and no
build step.

This repository used to hold *Herding*, a LÖVE prototype; that code is in the git
history. Counting Sheep reuses its palette and its sprite method: the bodies are
ray-traced ellipsoids, painted one pose at a time from an 8+ colour palette with no
alpha, then creased and inked (herding's `tracer.lua`, the method from underroot).
The sheep, the dog and the fence models come from herding's `models.lua`. The UI
follows underroot's: flat fills, solid ink edges, hard drop shadows, the 3x5 pixel
font for numbers in the scene, and dithering anywhere something has to fade.

## Running it

Open `index.html` in a browser. It is plain scripts, so `file://` works. Or serve
the folder:

```sh
python3 -m http.server 8000     # then open http://localhost:8000
```

- `?speed=10` (any value from 1 to 1000) runs the rules that many times faster. It's
  a hidden debug switch for playtesting pacing. Visuals stay at normal speed, and
  offline progress isn't sped up.
- To start over, clear the site's storage, or run
  `localStorage.removeItem('countingSheep.v1')` in the console and reload.

## Files

| file | what |
| --- | --- |
| `index.html` | the page: header, scene, Drowsiness bar, shop, dialog |
| `style.css` | layout (portrait first, two columns from 900px wide), cards, dialogs, reduced motion |
| `config.js` | **every balance number**: costs, rates, multipliers, golden sheep, Drowsiness, stages, prestige, offline, narrator lines |
| `num.js` | all game math (`add`, `mul`, `format`, geometric costs...) behind one object, so plain numbers can be swapped for break_infinity later |
| `game.js` | 1. Logic (state and rules, pure), 2. Sprites (palette, tracer, models, pixel font), 3. Scene (the canvas), 4. UI and boot (shop, dialogs, saves, loop) |
| `audio.js` | WebAudio sound effects and the ambient pad. No audio files |

### The game state

```js
{
  sheep, runTotal, allTime,      // Num: spendable, counted this run, counted ever
  runTime,                       // seconds into this run
  owned: { tapPower, betterFence, dog, meadow, pen, mill, drones, os, barn, lullaby },
  stage,                         // 0 Dusk, 1 The Field, 2 The Factory, 3 Orbit
  golden, goldenIn,              // a golden sheep crossing ({ t, lane }) and when the next one comes
  asleep,                        // the run is over; waiting for Dream Again
  dreamPoints, dreams,           // prestige, kept across runs
  taps, buyMode, muted, lastSeen,
}
```

The rules (`Logic`) step on a fixed timestep (`tickRate`, 30 a second) inside a
`requestAnimationFrame` loop. Drawing reads the state on every frame and never
writes to it. Purely visual things (sheep mid-hop, floating numbers, eyelids) live in
`Scene.fx`. Logic reports what happened (`stage`, `asleep`, `goldenAppears`...) as
events, and the UI and sound pick those up.

Saves are JSON in `localStorage`, written every 10 seconds, when the tab is hidden,
and when the page closes. On return, up to 8 hours of production is granted and
summarised in a "While you were dreaming..." dialog. A tab left in the background
counts as away too.

## Tuning `config.js`

- **Costs**: `cost = base * growth^owned`. `growth` defaults to 1.15. The
  multipliers and Better Fence set their own, much steeper, growth; otherwise a
  handful of them would outweigh every generator.
- **Production**: `sum(rate * owned) * (1 + 0.25*barns) * (1 + 0.5*lullabies) *
  (1 + 0.05*dreamPoints)`. The same multiplier applies to taps.
- **Run length** is mostly `drowsiness.target`, the sheep counted this run that put
  you to sleep. The bar is `(runTotal / target) ^ curve`. Production grows fast early
  and slowly late, and a quarter power turns that into a bar that fills at about
  even speed. Raise `target` for longer nights.
- **Pace of new things**: the generator `base` costs, and `revealAt`, which shows an
  upgrade once the run has counted that share of its price.
- **Stages** start at `stages[i].at` sheep counted. The **narrator** shows the last
  line in `lines` whose condition holds.
- **Prestige**: `prestige.divisor` and `bonusPerPoint`.

### Pacing as shipped

Checked with a headless sim (a greedy buyer, taps at a steady rate, catching every
golden sheep) and with the real page at `?speed=10` and an autoplayer:

| taps a second | Wool Mill | Sheep-OS | asleep |
| --- | --- | --- | --- |
| 3 | 3.0 min | 11.5 min | 21 min |
| 1.5 | 3.8 min | 13.5 min | 25 min |
| 0.5 | 5.0 min | 16 min | 28 min |

In the first five minutes something new appears every 20 to 60 seconds: Tap Power,
the Dog, the Meadow, Better Fence, the Barn, the Pen, the first Lullaby. You never
wait more than about 25 seconds for an affordable purchase.

Changes from the brief's numbers, all made to hit that pacing: the generator rates
are as given, but the costs past the Dog are higher (Meadow 150, Pen 2,500, Mill
90K, Drones 2M, Sheep-OS 50M, against 120 / 1.2K / 14K / 180K / 2.5M). With the
original costs, the whole run took 9 minutes.

Prestige is as given (`floor(sqrt(total / 1e5))`, +5% each). One night gives about
120 Dream Points (+600%), so the second night takes about 5 minutes. If you'd rather
each night be a long one, raise `prestige.divisor` to around `3e6`.

## What's in it

- A fence to tap. A sheep runs from the queue and hops over, and a `+N` floats up.
  Quick taps pile into one growing number.
- Tap Power, Better Fence, six generators unlocked in order (the next one teased as a
  greyed `???` card), Barn, Lullaby (up to 5), and the golden sheep. Tap the golden
  sheep for 60 seconds of production (or 40 taps' worth, early on).
- Buy ×1 / ×10 / Max.
- Four stages, driven by total sheep:
  - **Dusk:** one fence and a queue of sheep.
  - **The Field:** far hills with a fence line, and grazing sheep that multiply with
    Meadows. The dog runs loops once you have one.
  - **The Factory:** the Wool Mill smoking, a conveyor belt, and everyone in
    pajamas and nightcaps.
  - **Orbit:** sheep circle the moon, some auto-hoppers launch straight up, drones
    patrol with counting beams, and Sheep-OS's terminal counts in the grass.
- Night falls as Drowsiness rises: the dusk sky dithers down to navy, stars come
  out and twinkle, the moon rises, and the queue starts dozing (Zzz). Near the end
  the screen blinks and the eyelids droop, and at 100% they close.
- Juice: squash and stretch on hops, a fence bounce, wool puffs on landing, a
  counter that rolls up, floating numbers, and cards that breathe when affordable,
  pop when bought and wobble when you can't afford them. Confetti, banners for new
  helpers and stages, and a gold flash and a little shake for a golden catch.
- Audio: tap notes climbing a pentatonic scale as you tap faster, soft pops,
  chimes, and an ambient chord pad that darkens as you get sleepy. Each Lullaby adds
  a layer: the full chord, then a music box through an echo, a shimmer, a sub, and a
  bell melody. Mute is in the corner, and nothing plays before your first tap.
- `prefers-reduced-motion`: no shake, blinks, squash, Zzz, bobbing or card
  animations, and floating numbers fade in place. Every tap target is 44px or
  larger, and no text is under 14px. The pixel numbers are drawn at 3 CSS pixels a
  game pixel or more.

## Intentionally not included

- Achievements
- A stats screen
- More prestige layers or a prestige shop (Dream Points do one thing)
- Settings beyond mute (volume, number notation, reset button)
- Upgrades for individual generators, combos or click frenzies
- Cloud saves, import/export
- Localization
