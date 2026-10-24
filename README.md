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
Then the dream turns lucid, and phase 2 begins.

**Phase 2, lucid dreaming:** the night runs itself (auto-wake: a run a minute,
then a second, then a hundred a second, until there's no run to see, only the
flow). Six dream layers, a dream within a dream: each one dreams up the
sleepers of the layer above it, from the Hill down to the Aurora, and the
deeper a layer is the faster its time runs. Dream Points rebuild phase 1's
farm on a grid, a city builder where a building does more beside its own
district and beside a Haystack: the fence, the dog kennel, the meadow, the
pen, the mill, the drones and the barn come back one by one, each rising out
of the dream's hill where it was placed, the dream of the first nights built
again. In front of it all a sheep bounces on
a cloud: hold the field and it climbs, doodle-jump style, for stars, moons and
a best height that lifts every layer. Now and then a flock lines up at the
fence: tap it and count them over, one jump on each beat of a quickening
song, for Dream Points and a tune that raises the run cap for a while. A
golden sheep offers one of three gifts, and now and then a nightmare scatters
a flock for you to herd into the fold with the dog: herding, the prototype
this repository began as. Upgrades kept for good come in sections, one for
each of those games, then the layers and the farm, then seven dream
challenges one after the other. Last of all is the Gate of Horn, and through it, the void: phase 3,
from the field to the dream to nothing at all (its way in is built; the phase
is a placeholder).

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
love . --lucid             # dev: straight into phase 2 with 750 DP to spend (and with
                           # any dev flag on, L jumps there mid-game)
love . --lucid --speed 10 --autoplay 600   # dev: phase 2 played by a simple script
love . --void              # dev: straight into phase 3, through the Gate of Horn
luajit tests/run.lua       # dev: the rules' tests, no LÖVE needed
luajit tests/run.lua sim   # dev: the balance sim (a greedy player at 3, 1.5, 0.5 taps/s,
                           # then twelve nights in a row spending Dream Points)
luajit tests/run.lua nights 1.5 15   # dev: N nights in a row at a tap rate, then with no taps,
                                     # then playing each restless night as it opens
luajit tests/run.lua nights 3 20 heavy restless  # dev: one run, sleeping light or heavy
luajit tests/run.lua lucid 30        # dev: phase 2's balance sim, a greedy player for 30 minutes
luacheck .                 # dev: the lint
```

Pictures, sounds and saves go to LÖVE's save directory
(`~/.local/share/love/counting-sheep/` on Linux). To build a `.love`, zip the
folder's contents: `zip -9 -r counting-sheep.love . -x '.git/*' 'tests/*'`.

**Controls:** tap or click the field to count a sheep (Space or Enter too). Tap a
card to buy. Drag or use the wheel to scroll the shop. 1 / 2 / 3 picks ×1 / ×10 /
Max, D (or the DREAMS button) opens the Dream shop, M mutes, R reduces motion, F11 or Alt+Enter toggles fullscreen, and Esc quits on a computer.
In phase 2, 1 / 2 / 3 pick LAYERS / FARM / UPGRADES and 4 toggles ×1 / MAX; Space
catches the golden sheep, and 1 / 2 / 3 choose its gift; hold the field and
drag to steer the bouncing sheep up; when a flock waits at the fence, tap it
(or C, or Space) to count it, then tap anywhere on the field (or Space) as
each sheep tops the fence; in a nightmare, hold and drag on the field to move
the dog. On UPGRADES, tap a card to grow it, or start its dream challenge. In the void, tap the dark. The arrow coming round in the top bar
(every phase) resets everything and starts a new game from scratch, after
asking.

## Where it comes from

This repository was *Herding*, a LÖVE prototype (still in the git history).
Counting Sheep keeps herding's assets and method, and lays out its screen the
way underroot does:

- **The palette** is herding's eight colours (`gfx.lua`), plus six for night:
  deep navy, midnight, lavender, lilac and two golds. Nothing is drawn outside
  it, and nothing is drawn with alpha. The dusk sky, night falling over the
  grass and numbers fading out are all ordered dithers.
  Phase 2 adds four for the dream: deep violet, rose, aurora green and cloud.
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
| `config.lua` | **every balance number**: costs, rates, multipliers, the golden sheep, Drowsiness, stages, prestige, offline, the narrator's lines, and phase 2's `dream` section |
| `num.lua` | all amounts of sheep go through it (`add`, `mul`, `format`, geometric costs), so a big-number library can replace plain numbers later |
| `game.lua` | the rules and the state. Pure Lua, no LÖVE, so the tests and the sim run it in luajit |
| `main.lua` | the window, the fit, the fixed-timestep loop, input, saving on the way out, the dev flags |
| `scene.lua` | the field: sky, hills, fence, every sheep, and the view-only effects |
| `ui.lua` | the counter, the Drowsiness bar, the shop, banners, dialogs, input hit tests, the save file |
| `audio.lua`, `synth.lua`, `audiothread.lua` | the sound: playing it, making it, the worker that makes it |
| `gfx.lua`, `tracer.lua`, `models.lua` | the palette and pixel font, the tracer, the bodies |
| `shots.lua` | the `--shots` script |
| `tests/run.lua` | tests and the balance sims (phase 1 and phase 2) |
| `lucid/game.lua` | phase 2's rules: auto-wake in batches, the layers, the town, the upgrades, the golden choice, counting sheep's flock and pay, time away in closed form. Pure Lua |
| `lucid/nightmare.lua` | the nightmare: herding's flock, dog and pressure field, the fold, the cloud. Pure Lua |
| `lucid/bounce.lua` | the bouncing sheep: its cloud, the climb, clouds, stars and moons, and a bot that climbs. Pure Lua |
| `lucid/count.lua` | counting sheep, the rhythm game: the song's beats, taps judged perfect, good or off, and a bot that counts. Pure Lua |
| `lucid/ui.lua` | phase 2's screen: auto-wake, the LAYERS, FARM and UPGRADES tabs, dialogs, the way in and the way out. `ui.lua` hands over to it |
| `lucid/scene.lua` | phase 2's field: the violet sky and aurora, the farm rebuilt on the hill, sheep turning to cloud, the flow, the bouncing sheep, the flock counted over the fence, the nightmare |
| `lucid/upgrades.lua` | the upgrades' pictures, for their cards |
| `void/ui.lua` | phase 3, the void: a placeholder to stand in. `ui.lua` hands over to it |
| `assets/icon/` | the launcher icon, two 40px layers in the palette: the dusk and the hill, and the sheep |
| `android/icon.py` | bakes the Android launcher icon (legacy and adaptive) out of `assets/icon/` (underroot's) |

## Builds

- `.github/workflows/android.yml`: the APK (LÖVE for Android 12.0, the game as
  `game.love`), on every push that changes more than docs, as the workflow
  artifact "Counting Sheep", and attached to a GitHub Release on a `v*` tag.
  Signed with the `ANDROID_KEYSTORE_*` secrets when they are set (and then a
  Play bundle too), or with a throwaway key when they are not, in which case
  each build must be uninstalled before the next goes on. The application id
  is `com.cmatute.countingsheep` unless the `ANDROID_APP_ID` variable says
  otherwise. Taken from underroot's.

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
  phase,                          -- "nights", "lucid" (phase 2) or "void" (phase 3)
  lucid,                          -- phase 2's state (below), from the moment you go lucid
  taps, buyMode, muted, lastSeen,
  version,                        -- the save's shape: 3
}

lucid = {
  sheep, sheepTotal, dp, dpEarned, runs, -- Num: dream sheep, Dream Points, runs ever
  runAcc,                         -- the fraction of a run under way
  legacy,                         -- phase 1's points ever earned, as a multiplier
  dims = { { amount, bought } x6 },-- the six layers: sleepers in each, and bought
  open, grid, level, plots, built,-- the town: land, buildings by cell, their levels
  autoOff,                        -- auto-buyers paused, by layer
  golden, goldenIn, choosing, effects, -- the golden sheep, its gift on offer, gifts running
  nightmare, nightmareIn,         -- herding, while it's on (not saved: it passes)
  challenge, done, herded, counted, climbed, -- the dream challenge under way, the ones met, its progress
  roots,                          -- the upgrades: id = ranks grown
  flock, flockIn, song,           -- a flock waiting at the fence, when the next comes, counting it (not saved)
  tuneMult,                       -- the last song's run cap multiplier, while effects.tune lasts
  gate,                           -- the Gate of Horn is open
  best, bounce,                   -- the best height ever; the climb (not saved: it passes)
  flow, intro, time,
}
```

Saves are versioned. `Game.deserialize` reads `version` (none is 1) and runs
`Game.MIGRATE` in order: 1 to 2 leaves a phase-1 save as it was, and gives a
save that went lucid in the old placeholder its phase-2 state, with the points
it held; 2 to 3 changes nothing (the roots, the best height and the gate start
fresh). Phase 1's fields stay where they were; phase 2 lives in `lucid`, and
the void keeps it there too (back through the gate, the dream is as it was).

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

### Phase 2 (`dream` in config.lua)

- **Auto-wake:** runs a second = `min(cap, sheep a second / sheep a run)`, and
  half that while a nightmare is on. The cap starts at 1 and is `(1 + S)^1.7`
  with S the Better Fences' strength; a run needs 60 dream sheep, divided by
  `1 + S` of Dog Kennels. Runs are settled in batches: each step adds runs a
  second × dt to `runAcc` and pays for the whole runs in it, so a thousand
  runs a second cost what one does. Past `flowAt` (30) runs a second the
  screen stops showing runs and shows the flow.
- **Points a run:** `dpPerRun * legacy * (1 + 0.5 * S meadows)`, with
  `legacy = 1 + log10(1 + phase-1 points ever earned) * 0.5` (about ×3 for a
  usual player).
- **Layers:** a sleeper in layer k dreams up `rate_k` sleepers in layer k-1 a
  second; layer 1's count dream sheep. Price `base * growth^bought` in dream
  sheep (÷ `1 + 0.5 * Architect`); every 10 sleepers in a layer its time runs
  ×2 (+0.1 a rank of Time Dilation). All of them × `(1 + S barns)` ×
  `(1 + sqrt(points earned in phase 2) * 0.01 * (1 + 0.5 * Deep Well))` × the
  best height's `(1 + 0.06 * best / 100)`. The growths (1.8 up to 10 a copy)
  beat the ×2 per ten by far, or the chain runs away. In the code a layer is
  still a `dim`.
- **The farm:** a building's strength is its level × (1 + 0.25 per neighbour of
  its district + 0.5 per Haystack beside it). In the code and the save it's
  still the `town`, and the buildings keep the old town's ids (`clock` is the
  Better Fence, `inn` the Dog Kennel, `bakery` the Meadow, `hut` the Breeding
  Pen, `workshop` the Wool Mill, `observatory` the Counting Drones, `mill` the
  Barn, `plaza` the Haystack, `fountain` the Wishing Well, `lighthouse`
  Sheep-OS), so a save's farm is the same one. Prices are `dp` and `sheep`, ×growth
  per copy built or level gained. Every effect is a polynomial in S, never an
  exponential: prices are exponential, so the effect has to lose to them. Land
  is `400 * 1.7^plots` and must touch land you have. Moving a building is
  free.
- **Time away** is closed form: with what's bought held still the chain is a
  polynomial in t, the sheep rate meets the cap at a time found by halving,
  and runs are the rate's integral to there plus the cap after. The points
  those runs earn lift the layers, so the time is cut into 32 pieces, each
  closed form (a test checks it against stepping: within 5%).
- **Numbers:** every amount goes through `num.lua`, which grew `pow`, `eq`,
  `gt`, `lte`, `min`, `floor`, `log10` and geometric prices in Num, so a
  big-number library can take its place. A greedy player's dream sheep are at
  1E58 after three hours, so plain numbers hold for now.

- **The farm on the hill:** each plot of the 5×5 grid has a place on the
  dream's hill (the back row on the skyline, the front row at the bottom of
  the field, the columns wider apart as they come forward). Buildings on the
  hill are drawn from shapes (`SHAPES` in `lucid/scene.lua`), not the small
  pictures the FARM grid uses: in perspective, a pixel a unit on the skyline
  up to 2.8 at the front, inked round as one, with a shadow thrown left and
  grass at the foot, and the back two rows dithered into the horizon's lilac.
  An empty plot is turned earth; a building rises out of the ground when it's
  put down, a level up rings out, and its levels show as gold pips. Moving
  one moves it on the hill too.
- **The upgrades** (`sections` and `roots`: in the code and the save they're
  still the roots): a rank at a time, for `dp * growth^rank` Dream Points, up
  to `max`, kept for good, as cards in sections like the farm's. In a section
  each opens once the one before it (`at`) has a rank. The games first: the
  bouncing sheep (Springy Wool, Star Bag, Cloud Steps, Moon Pull), counting
  sheep (Sheep Bell, Slow Song, Lullaby, Encore), the nightmares (Quick Dog,
  Good Dog, Night Light) and the golden sheep (Spinning Top, Slow Gold); then
  the layers (the Architect, Deep Well, Time Dilation) and the farm
  (Surveyor, Night Market, Bellows). Last, the dream challenges: the Mirror
  Lake (grown once the farm has one), the seven challenges one after the
  other, each opening once the one before it is mastered, and the Gate of
  Horn. Every effect is a polynomial in its rank, like the town's.
- **Counting sheep** (`count`, `lucid/count.lua`): every 150 to 260 seconds
  (÷ `1 + 0.25` a Sheep Bell; the first at 75) a flock lines up at the fence
  and waits 20 seconds. Tapped, 16 sheep jump it, a beat apart from 0.75
  seconds down to 0.45, after a count-in of two ticks; a tick sounds on every
  top. A tap within 0.08 s of a top is perfect (1), within 0.17 good (0.5),
  both ×(1 + 0.15 a Slow Song); a sheep let past, or a tap with none near,
  breaks the count. Over, it pays 45 seconds of Dream Points (at least 30, +50%
  a Lullaby) by the share counted, and leaves a tune: the run cap ×(1 + 0.5 ×
  share) for 40 seconds (+50% an Encore). While a song is on the bouncing
  sheep rests, no golden sheep comes, and no nightmare: the field is the
  fence's.
- **The bouncing sheep** (`bounce`, `lucid/bounce.lua`): in field units 100
  across. Left alone it hops on its cloud. Held, it's launched and drifts
  after the finger (`follow`, at most `maxVx`); a cloud it falls onto throws
  it up at `jump` (×1.6 off a gold spring cloud; a dark cloud holds once and
  breaks; past 160 high some drift). Clouds come `gapMin` to `gapMax` apart,
  never more than 80% of a jump. Let go and the clouds stop holding it: it
  falls, and off the bottom of the view the climb is over. A star pays 4
  seconds of Dream Points (at least 3), a moon every 400 high is a golden
  gift, and the best height ever lifts every layer. While it climbs the field
  slides down behind it, the hill and the town go under, and higher still the
  dark thins towards the void.
- **The way out:** the Gate of Horn costs 300M DP and needs the last
  challenge mastered. Opened, the dream drains to ink from the edges, the
  gate opens in the middle, a sheep drifts up into it, and the phase is
  "void" (`Game.goVoid`). The void is a placeholder for phase 3; BACK TO THE
  DREAM goes back through the gate, which stays open (GO THROUGH on its card).
- **Dream challenges** (`challenges`): at the end of the upgrades, once the
  town's Mirror Lake stands (400K DP and 1E30 sheep), one after the other.
  Starting one sets the layers and dream sheep back to the start and, while it
  lasts, the points earned don't lift the layers (only the town does), or the
  old multiplier would carry any rule. The town, the upgrades and the points
  stay. Goals are `runs` (runs a second under the rule), `sheep` (dream sheep
  counted under it), `herd` (flocks brought home) or `height` (a climb that
  high). Giving up just lifts the rule.

| challenge | rule | goal | reward |
| --- | --- | --- | --- |
| Nightmare Season | a nightmare every 8 s after the last | 3 flocks home | a wider fold, nightmares pay double |
| Broken Fences | Better Fences at half strength | 40 runs/s | the cap's power 1.7 → 1.85 |
| Thin Air | clouds half as wide | a climb 300 high | stars and the best height count double |
| Only One | one sleeper a layer | 1E18 dream sheep | time ×2.5 every ten, not ×2 |
| Shallow Sleep | only the first three layers dream | 1E20 dream sheep | the first three layers ×3 |
| Falling | no auto-buyers | 300 runs/s | every layer ×2 |
| Empty Squares | no building helps its neighbours | 120 runs/s | districts count double |

  The sim gives a challenge up after six minutes and tries it again ten later.

From `luajit tests/run.lua lucid 120` (a greedy player bringing 750 DP and
7,000 earned, catching every golden sheep, herding every nightmare in,
counting every flock with every sheep perfect, growing the cheapest upgrade
under a tenth of its points, and climbing for thirty seconds every two
minutes with the bot, which climbs far better than a person: its best is 560
on the first climb and about 950 later):

| minute | 1 | 2 | 3 | 6 | 8 | 10 | 20 | 30 | 45 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| runs a second | 1 | 6.9 | 16.8 | 40 | 71 | 37 | 99 | 536 | 622 |

(Minute 10 is under Broken Fences and minute 20 under Empty Squares: a
challenge starts the layers over.) The Mirror Lake comes at 8.4 minutes, a
first rank of every upgrade by 8.6, the challenges from 9 to 21 minutes, and
the Gate of Horn at 47. Counting matters: with `NOCOUNT=1` (never counting) the
gate comes at 60 minutes; a person who misses some sheep lands between. In
the first ten minutes there's something new 58 times, at most 63 seconds
apart, and never more than 61 seconds without something to buy in town. The
flow comes at 5.6 minutes.

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
    with the night it opens. The night one opens, a banner says so and the
    Dream shop opens on it; while one waits to be tried the section sits at
    the top of the Dream shop, and until you look a rose mark blinks on
    DREAMS. START asks first (the night you're in ends,
    nothing kept), then the rule replaces the narrator in gold; GIVE UP goes
    back to a plain night. **Insomnia** (4× the sheep) halves every night's
    sheep after; **Sheep Shortage** (helpers ×1.3 dearer each) makes them ×1.13
    dearer each instead of ×1.15; **Wide Awake** (no Dream shop automation)
    makes Deep Sleep triple; **Cold Feet** (no Barns or Lullabies) doubles them.
  - A gold star on the button means there's something you can buy. After Dream
    Again, the shop opens on it.
- **Lucid:** every night that fills the bar in under a second ends as *A lucid
  dream*, with GO LUCID instead of DREAM AGAIN. That banks the night's Dream
  Points and goes into phase 2, for good: the night closes, the dream opens
  violet from the middle, "YOU STOP COUNTING SHEEP. YOU START DREAMING THEM.",
  a new cadence, and a word on what's changed. The points come along to spend.
- **Phase 2, lucid dreaming:**
  - *Auto-wake*, under the field: a bar that fills once a run (1 RUN / 60S),
    then shimmers, then reads NO NIGHT. ONLY DREAM. Each run you can still see
    hops the fence with its points over it; after that it's a stream of wool.
  - *LAYERS*: the six dream layers (the Hill, the Clouds, the Sky Meadow, the
    Moon, the Stars, the Aurora), each card its sleepers, what they dream up
    and how fast time runs there; the next one a dashed `???`. ×1 or MAX. An
    AUTO pill on each one a farm building auto-buys; tap it to pause.
  - *FARM*: a 5×5 grid, the middle 3×3 open. Pick a building and tap a plot;
    tap a building to LEVEL UP or MOVE it (free); tap a dashed `+` to BUY LAND.
    Every building is a piece of phase 1's field and barn, dreamt back.
    Speed (gold): Better Fence, Dog Kennel, Meadow. Automation (lilac):
    Breeding Pen, Wool Mill, Counting Drones (two layers each), the Barn.
    Pasture (green): Haystack, Wishing Well, Sheepfold. Lucidity: the Mirror
    Lake, and Sheep-OS to see, not to build yet. Everything built stands on
    the dream's hill, rising out of the ground as it goes up.
  - *UPGRADES*: cards in sections like the farm's, each headed with its
    game and how to play it: the bouncing sheep, counting sheep, the
    nightmares, the golden sheep, then the layers and the farm. A card shows
    what it does, its rank and its price; one waiting on the one before it
    is dimmed and says so. Tap it to grow it.
  - *Dream challenges*, the last section of UPGRADES once the Mirror Lake
    stands, one opening after the other. Once the Mirror Lake can be bought,
    a rose mark blinks on FARM and Lucidity moves to the top of the list (TO
    THE FARM on the lake's card picks it up to place). Built, a banner points
    to UPGRADES; a challenge waiting puts the mark on UPGRADES, and opening it
    scrolls to the challenge. START asks first; then the rule and how far
    you've got show in gold over the field, the card says GIVE UP, and a
    challenge met is MASTERED, its reward kept.
  - *The bouncing sheep*, in front of the field: it hops on its cloud; hold
    the field and it climbs after your finger, cloud to cloud, while the field
    slides away under it. Stars pay Dream Points, a moon is a golden gift, and
    a new best height says how much it lifts every layer.
  - *Counting sheep*: now and then a flock lines up on the near side of the
    fence with a gold ring round it, and a line under the field says to tap
    it and how long it waits. Tapped, the climb stops and the field is the
    fence's: the flock comes up to it and each sheep jumps it on the beat, a
    light over the fence brightest at the top. Tap anywhere on the field as
    each one tops it: PERFECT turns it gold, GOOD counts it, a miss turns it
    to cloud and bleats. The counted, the combo and the music box climbing
    with it show over the field; at the end, Dream Points and a CAP chip
    while the tune lasts.
  - *The Gate of Horn*, at the end of UPGRADES: the way out, into the void.
  - *The lucid golden sheep* crosses the sky: tap it and choose ×7 for 30
    seconds, Dream Points now (4 minutes' worth), or time ×2 for a minute.
  - *Nightmares*, every four to seven minutes: the field turns to night grass,
    the flock scatters, a dark cloud with rose eyes drifts after it, and runs
    go at half speed. Drag the dog: the sheep flee its pressure field (dithered
    green round it), and inside the fold they stay. A sheep the cloud sits on
    too long is lost. All in: up to three minutes of points. Left alone, it
    passes in a minute.
  - The sky goes violet with an aurora, Dream Sheep graze the hill and the
    deeper layers drift as cloud-sheep. The pad keeps only its chords,
    music box and shimmer, quieter and a little lower.
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
- Phase 3, the void: only its way in and a placeholder to stand in
- Pending for phase 2: the second prestige layer (Sheep-OS on the farm, shown,
  not built), nightmares that grow, a soft cap on Insomnia, surplus sheep
  paying points
- `ui.lua` hands over to `lucid/ui.lua` but they don't share widgets yet
  (cards, dialogs and banners are drawn in each)
- Restless nights past the four, or doing one again
- Settings beyond mute, motion and reset (volume, notation)
- Per-generator upgrades, combos, click frenzies
- Cloud saves, import and export
- Localization
- Android and iOS packaging: the game runs on LÖVE for Android as-is, but
  there's no build here
