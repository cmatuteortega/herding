# Herding

A cozy herding puzzle in LÖVE 11.x. You play a small dog and guide a flock into its pen. There's no timer and no way to fail.

```sh
love .            # --level N to skip the title and start on a level, --window for a 1280x720 window
```

**Controls:** WASD or the arrow keys walk, and Shift runs. You can also hold the mouse button or a finger down, and the dog goes to that point: a short drag creeps, a long one runs. A gamepad's left stick is analogue. **Space**, the right mouse button, a gamepad's A or X, or a second finger **barks**. Esc, P, the pause button or Start pauses. R restarts the level, N skips it, and F11 or Alt+Enter toggles fullscreen.

**What's in it:**

- Six fields, chosen from the title screen. Each one opens when you finish or skip the one before it, and progress is saved.
- The bark pushes every sheep near the dog away at once. It startles them a little, and then the dog needs a moment before it can bark again.
- Lambs are small and nervous, and they stay close to their mothers. A black sheep is stubborn: she reacts less to the dog and would rather graze. You have to get close or bark to move her.
- Ponds work like rocks for the flock, but they are painted flat into the ground.
- Calm rating: a level finished without scaring a single sheep earns three hearts. Your best for each field is shown on the title screen.
- A dot at the edge of the screen points to each sheep that is out of view.

| file | what |
| --- | --- |
| `flock.lua` | boids, wandering, grazing, panic, the bark, sheep kinds. **`CONFIG` and `KINDS` at the top hold every tuning number.** |
| `dog.lua` | dog movement, the dithered pressure field, the bark ring |
| `level.lua` | the six fields, fences, ponds and pen, collision and repulsion |
| `main.lua` | canvas fit, camera, level flow, title, pause, HUD |
| `save.lua` | which fields are open and the best hearts for each, in `progress.txt` |
| `input.lua` | keyboard, mouse, touch and gamepad |
| `tracer.lua`, `models.lua` | the 3D method: ellipsoid bodies ray-traced per pose and cached (from underroot / Survive School) |
| `gfx.lua` | the 8-colour palette, pixel drawing and the 3x5 font |
