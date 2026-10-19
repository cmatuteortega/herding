# Herding

A cozy herding puzzle in LÖVE 11.x. You play a small dog and guide a flock into its pen. There's no timer and no way to fail.

```sh
love .            # --level N to start on a level, --window for a 1280x720 window
```

**Controls:** WASD or the arrow keys walk, and Shift runs. You can also hold the mouse button or a finger down, and the dog goes to that point: a short drag creeps, a long one runs. A gamepad's left stick is analogue. R restarts the level, N skips it, and F11 or Alt+Enter toggles fullscreen.

| file | what |
| --- | --- |
| `flock.lua` | boids, wandering, grazing, panic. **`CONFIG` at the top holds every tuning number.** |
| `dog.lua` | dog movement and the dithered pressure field |
| `level.lua` | the three fields, fences and pen, collision and repulsion |
| `main.lua` | canvas fit, camera, level flow, HUD |
| `input.lua` | keyboard, mouse, touch and gamepad |
| `tracer.lua`, `models.lua` | the 3D method: ellipsoid bodies ray-traced per pose and cached (from underroot / Survive School) |
| `gfx.lua` | the 8-colour palette, pixel drawing and the 3x5 font |
