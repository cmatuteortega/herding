# Counting Sheep

A cozy bedtime incremental game in LÖVE 11.x. You count sheep to fall asleep:
tap the fence and a sheep hops over. It starts with one fence at dusk and ends
with sheep in orbit and an AI counting for you. The numbers get bigger while the
sky gets darker, and when the Drowsiness bar fills, you fall asleep. Then you
Dream Again, keeping Dream Points to spend in the Dream shop. It sells
automation that plays the night for you, boosts that make it shorter, and a
way of sleeping (light, for players who tap, or heavy, for those who don't).
From the third night on, restless nights (challenges) open one a night: a
night under a rule, with a reward kept forever.
Each night is quicker than the last, until the bar fills in under a second.
Then the dream turns lucid, the door to the game's next phase.

It's built for a phone held upright (the field on top, the shop under your
thumb) and works on a computer (the field on the left, the shop on the right).

```sh
love .                     # play
love . --speed 10          # dev: the rules run 10x as fast (1 to 1000)
love . --fresh             # dev: ignore the save, start a new game
love . --autoplay 300      # dev: a scripted player taps and buys for 300 game
                           # seconds (add --speed 10), prints how it went, saves a picture
love . --shots             # dev: scripted moments at phone and desktop size, as PNGs
love . --sounds            # dev: every sound and pad layer written as a .wav
luajit tests/run.lua       # dev: the rules' tests, no LÖVE needed
luajit tests/run.lua sim   # dev: the balance sim (a greedy player at 3, 1.5, 0.5 taps/s,
                           # then twelve nights in a row spending Dream Points)
luajit tests/run.lua nights 1.5 15   # dev: N nights in a row at a tap rate, then with no taps,
                                     # then playing each restless night as it opens
luajit tests/run.lua nights 3 20 heavy restless  # dev: one run, sleeping light or heavy
luacheck .                 # dev: the lint
```

Pictures, sounds and saves go to LÖVE's save directory
(`~/.local/share/love/counting-sheep/` on Linux). To build a `.love`, zip the
folder's contents: `zip -9 -r counting-sheep.love . -x '.git/*' 'tests/*'`.

**Controls:** tap or click the field to count a sheep (Space or Enter too). Tap a
card to buy. Drag or use the wheel to scroll the shop. 1 / 2 / 3 picks ×1 / ×10 /
Max, D (or the DREAMS button) opens the Dream shop, M mutes, R reduces motion, F11 or Alt+Enter toggles fullscreen, and Esc quits on a computer.

## Where it comes from

This repository was *Herding*, a LÖVE prototype (still in the git history).
Counting Sheep keeps herding's assets and method, and lays out its screen the
way underroot does:

- **The palette** is herding's eight colours (`gfx.lua`), plus six for night:
  deep navy, midnight, lavender, lilac and two golds. Nothing is drawn outside
  it, and nothing is drawn with alpha. The dusk sky, night falling over the
  grass and numbers fading out are all ordered dithers.
- **The bodies** are herding's: ellipsoids ray-traced a pose at a time by
  `tracer.lua` (Survive School's 3D method, by way of underroot), then creased
  and inked. The camera is lowered to 22° for a side view. The sheep, the
  collie and the fence posts are herding's `models.lua`. The pajamas and
  nightcap, the golden fleece, the drones and the moon are new, built the same
  way.
- **The screen** is underroot's: one low-res canvas blown up by a whole number,
  never under 3, so the 3x5 pixel face stands at least 15 screen pixels tall.
  Flat fills inside a one-pixel ink edge, a dithered veil under dialogs.
- **The sound** is underroot's synth (`synth.lua`), made at load from nothing.
  It renders on a `love.thread` worker (`audiothread.lua`), so it never costs a
  frame.

Libraries, in `lib/`, all MIT, by rxi: **flux** 0.1.5 (tweens: cards popping
and sliding in, banners, dialogs, the counter bump), **lume** 2.3.0 (clamps and
small helpers) and **json.lua** 0.1.2 (the save file).

## Files

| file | what |
| --- | --- |
| `config.lua` | **every balance number**: costs, rates, multipliers, the golden sheep, Drowsiness, stages, prestige, offline, the narrator's lines |
| `num.lua` | all amounts of sheep go through it (`add`, `mul`, `format`, geometric costs), so a big-number library can replace plain numbers later |
| `game.lua` | the rules and the state. Pure Lua, no LÖVE, so the tests and the sim run it in luajit |
| `main.lua` | the window, the fit, the fixed-timestep loop, input, saving on the way out, the dev flags |
| `scene.lua` | the field: sky, hills, fence, every sheep, and the view-only effects |
| `ui.lua` | the counter, the Drowsiness bar, the shop, banners, dialogs, input hit tests, the save file |
| `audio.lua`, `synth.lua`, `audiothread.lua` | the sound: playing it, making it, the worker that makes it |
| `gfx.lua`, `tracer.lua`, `models.lua` | the palette and pixel font, the tracer, the bodies |
| `shots.lua` | the `--shots` script |
| `tests/run.lua` | tests and the balance sim |

### The state

```lua
{
  sheep, runTotal, allTime,       -- Num: spendable, counted this run, counted ever
  runTime,                        -- seconds into this run
  owned = { tapPower, betterFence, dog, meadow, pen, mill, drones, os, barn, lullaby },
  made = { dog, meadow, pen, mill, drones, os }, -- built by the chain this run, in fractions
  challenge,                      -- the restless night you're under, or nil
  stage,                          -- 1 Dusk, 2 The Field, 3 The Factory, 4 Orbit
  golden, goldenIn,               -- a golden sheep crossing { t, lane }, and when the next comes
  asleep,                         -- the night is over; waiting for Dream Again
  dreamPoints, dreamEarned,       -- prestige: to spend, and ever earned (the bonus)
  dreams, dream = { sleepwalk, nightShift, goldenDreams, sleepTalk, tuckedIn, deepSleep, warmBed, dreamCatcher,
                    lightSleeper, heavySleeper },
  done = { insomnia, shortage, wideAwake, coldFeet }, -- restless nights slept through: true
  lastNight, lucidNight,          -- the last night's length; this one was under a second
  phase,                          -- "nights", or "lucid" (the next phase's placeholder)
  taps, buyMode, muted, lastSeen,
}
```

The rules step 30 times a second on a fixed timestep, inside LÖVE's frame. The
screen reads the state every frame and only changes it through `game.lua`'s
functions (`tap`, `buy`, `catchGolden`...). The rules report what happened
(`stage`, `asleep`, `goldenAppears`, `lucid`, and `bought` and `golden` marked
`auto` when the automation did it) as events, which ui.lua turns into banners
and sounds. What only looks (sheep mid-hop, floating numbers, eyelids) lives in
`scene.lua`'s `fx`.

The save is `save.json`. It's written every 10 seconds, when the window loses
focus or is hidden (a phone locked, the app sent away), and on quit. Coming back
grants up to 8 hours of production, with a "While you were dreaming..." dialog;
the same happens if the game sat frozen in the background for a while.

## Tuning `config.lua`

- **Costs:** `cost = base * growth^owned`, with growth 1.15 unless an item sets
  its own. Better Fence (×7), the Barn (×4) and the Lullaby (×6, at most 5) grow
  faster; at 1.15 a few of them would outweigh every generator.
- **Production:** `sum(rate * (owned + made)) * 1.4^heavySleeper * (1 + 0.25*barns) *
  (1 + 0.5*lullabies) * 2^deepSleep * (1 + 0.01*dreamEarned)`. Taps get the same
  multiplier (not Heavy Sleeper's), and a tap of your own adds `0.2*lightSleeper`
  seconds of production.
- **The chain:** a helper with `builds` makes that many of the helper before it
  a second, each (Sheep-OS builds Drones, Drones build Mills, Mills build Pens).
  Built helpers count like bought ones, don't raise the price and don't stay the
  night (Warm Bed keeps bought ones only).
- **Night length** is `drowsiness.target`, the sheep counted that put you to
  sleep. The bar is `(runTotal / target) ^ curve`; a quarter power turns fast
  early growth and slow late growth into a bar that fills at about even speed.
- **Pace of new things:** the generators' `base` costs, and `revealAt` (an
  upgrade shows once the night has counted that share of its price).
- **Stages** start at `stages[i].at` sheep. The **narrator** shows the last line
  in `lines` whose condition holds.
- **Prestige:** Dream Points = `floor(sqrt(total / 3e6) * (1 + 0.5*catchers) *
  pace)`. The pace is `(1500 s / night) ^ 0.35`, from 1 to 20, and it's the loop that
  compounds: a quicker night pays more points, and the points buy a quicker
  night. The **Dream shop** is `dreamShop`, priced `floor(base * growth^owned)`
  in points. `auto.share` is the most of your sheep one auto-buyer trip spends on
  any one thing (without it, Night Shift spends everything on Dogs and the night
  gets slower). `lucid.under` is the night length that opens the next phase.
- **Ways of sleeping** (`group = "path"` in `dreamShop`) are one or the other:
  buying one while you own the other turns you over, and gives back every point
  spent on the other. Light Sleeper is worth it to a player tapping about 1.5 a
  second or more; at 0 taps Heavy Sleeper wins.
- **Restless nights** are `challenges`: each opens once `dreams >= opens`, and
  its rule (`target`, `growth`, `noKind`, `noAuto`) holds while it's
  `s.challenge`. Starting one ends the night you're in with nothing kept;
  falling asleep under it sets `done[id]` and its reward for good. A restless
  night never goes lucid.

### Pacing as shipped

From `luajit tests/run.lua sim` (a greedy player catching every golden sheep),
checked against the real game with `--speed 10 --autoplay 300`:

| taps a second | Wool Mill | Sheep-OS | asleep |
| --- | --- | --- | --- |
| 3 | 3.0 min | 10.7 min | 18 min |
| 1.5 | 3.8 min | 12.7 min | 21 min |
| 0.5 | 5.0 min | 14.3 min | 23 min |

The chain took three to five minutes off the first night (it was 21, 25 and 28).

Night after night (`luajit tests/run.lua nights`: 1.5 taps a second sleeping
light, and each night's Dream Points go on the cheapest thing in the Dream shop):

| night | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 12 | 14 | 16 | 18 | 19 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| seconds | 1249 | 503 | 374 | 306 | 260 | 130 | 92 | 51 | 22 | 23 | 12 | 3.4 | 1.8 | 1.0 | **0.5** |
| Dream Points | 23 | 32 | 36 | 40 | 41 | 78 | 89 | 109 | 146 | 194 | 239 | 474 | 592 | 738 | 740 |

The same, playing each restless night as soon as it opens (nights 3 to 6):

| night | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| restless | | | Insomnia | Shortage | Wide Awake | Cold Feet | | | | | |
| seconds | 1249 | 503 | 538 | 243 | 91 | 207 | 16 | 7.7 | 1.8 | 1.4 | **0.3** |
| Dream Points | 23 | 32 | 64 | 31 | 42 | 47 | 115 | 150 | 252 | 418 | 425 |

Both take about 50 minutes to the first lucid night. Without the restless
nights it's 19 nights, the last ten of them under a minute; with them it's 11,
and the time goes on four nights that each play differently. The way of
sleeping matters: at 3 taps a second, sleeping light reaches lucid on night
16 and heavy on 17, with light's nights 3 to 8 much shorter; at no taps,
heavy reaches it on night 18 and light on 20. The auto-buyers shop every 0.05
seconds, or a night near the end would be over before their second trip.

In the first five minutes something new turns up every 20 to 60 seconds (Tap
Power, the Dog, the Meadow, Better Fence, the Barn, the Pen, the first Lullaby),
and you never wait more than about 25 seconds for something you can afford.

The generators keep the brief's rates, but the costs past the Dog are higher
(Meadow 150, Pen 2.5K, Mill 90K, Drones 2M, Sheep-OS 50M, against 120 / 1.2K /
14K / 180K / 2.5M); with the brief's costs a night lasted 9 minutes. Prestige
used to be `sqrt(total / 1e5)` at +5% a point: 122 points after the first night
made the second last under 4 minutes, with nothing left to do with them. Now
points are scarcer (`3e6`, about 22 a night) and worth 1% each, and the rest of
their value comes from what they buy.

## What's in it

- **The fence:** a sheep runs from the queue and leaps it, squashing as it takes
  off, stretching in the air, flattening as it lands with a puff of wool. A `+N`
  floats up, and quick taps pile into one growing number.
- **The shop:** Tap Power, Better Fence (the fence turns white, then
  gold-capped), and six helpers, each unlocked by owning the one before it (the
  next one teased as a dashed `???` card). The last three build the one before
  them (the chain), and a card shows bought and built: `X24+14`. Then the Barn, the Lullaby, and the
  golden sheep: 60 seconds of production when you catch it (or 40 taps' worth
  early on). Buy ×1, ×10 or Max.
- **The stages:**
  - **Dusk:** one fence and a queue.
  - **The Field:** a fence line on far hills, grazing sheep that multiply with
    Meadows, collies running loops, a pen of bouncing lambs with hearts rising.
  - **The Factory:** the Wool Mill smoking behind the hills, a conveyor belt, and
    everyone in striped pajamas and nightcaps.
  - **Orbit:** sheep circle the moon, some hoppers launch straight up, drones
    patrol with counting beams, and Sheep-OS counts in the grass.
- **The Dream shop** (the DREAMS button, after the first night), kept forever:
  - *While you sleep:* **Sleepwalking** taps 2 a second per level (up to 10),
    **Night Shift** buys helpers for you (two more each level, Dog up to
    Sheep-OS), **Golden Dreams** catches every golden sheep, **Sleep Talking**
    buys Tap Power and Better Fence, and **Tucked In** buys Barns and Lullabies.
    A card the automation buys says AUTO, and a section it buys all of
    folds into one row (SHOW opens it, HIDE folds it back).
  - *Deeper sleep:* **Deep Sleep** doubles everything per level (×4 dearer
    each), **Warm Bed** starts each night with 20% of the helpers you fell
    asleep with per level (all of them at level 5; Barns, Lullabies and tap
    upgrades still reset), and **Dream Catcher** adds +50% Dream Points.
  - *Way of sleeping* (from the third night), one or the other: **Light
    Sleeper** makes each tap of yours count 20% of a second's sheep per level
    and brings golden sheep twice as often; **Heavy Sleeper** makes helpers
    ×1.4 per level, and you sleep through every golden sheep. The other's card
    says TURN OVER, and turning over gives back what the first cost.
  - *Restless nights*, one more each night from the third, the next one dashed
    with the night it opens. START asks first (the night you're in ends,
    nothing kept), then the rule replaces the narrator in gold; GIVE UP goes
    back to a plain night. **Insomnia** (4× the sheep) halves every night's
    sheep after; **Sheep Shortage** (helpers ×1.3 dearer each) makes them ×1.13
    dearer each instead of ×1.15; **Wide Awake** (no Dream shop automation)
    makes Deep Sleep triple; **Cold Feet** (no Barns or Lullabies) doubles them.
  - A gold star on the button means there's something you can buy. After Dream
    Again, the shop opens on it.
- **Lucid:** every night that fills the bar in under a second ends as *A lucid
  dream*, with GO LUCID instead of DREAM AGAIN. That banks the night's Dream
  Points and enters the lucid phase (`phase = "lucid"`, saved, and the screen
  it comes back to). For now it's a placeholder screen, PHASE 2, with a button
  back to counting; nothing counts while you're in it.
- **Night falling:** the sky dithers from dusk down to navy, stars come out and
  twinkle, the moon rises, and the queue dozes (Zzz). Near the end the screen
  blinks and the eyelids droop. At 100% they close, and the ending is a night
  sky with one sheep asleep on top of it all.
- **Juice:** fence bounce, wool and grass puffs, a counter that rolls up and
  jumps, cards that breathe (a lavender ring) when you can afford them, pop when
  bought, slide in when new, and shake when you can't pay. Confetti from the
  price, banners for new helpers and stages, and a gold flash and a shake for a
  golden catch.
- **Sound:** tap notes that climb a pentatonic scale the faster you tap, a soft
  landing, pops and chimes. Under it all is a 32-second lullaby pad, with each
  Lullaby adding a layer: chord tones, a music box through an echo, a shimmer, a
  sub bass, a bell melody. It sinks in pitch and quietens as you get drowsy.
  Nothing plays before the first tap; M mutes.
- **Reduced motion:** LÖVE can't read the system's prefers-reduced-motion
  setting, so there's a button for it beside mute (the wave; R on a keyboard),
  kept in the save. It turns off shake, blinks, squash, Zzz, bobbing and the
  card animations, and numbers fade in place. Every card is 30 game pixels tall
  (90 or more screen pixels), and every letter at least 15.

## Intentionally not included

- Achievements
- A stats screen
- A second prestige layer (lucid dreaming is the gate to one, the content isn't built)
- Restless nights past the four, or doing one again
- Settings beyond mute and motion (volume, notation, a reset button)
- Per-generator upgrades, combos, click frenzies
- Cloud saves, import and export
- Localization
- Android and iOS packaging: the game runs on LÖVE for Android as-is, but
  there's no build here
