-- tuning-in/lib/particles.lua
-- a single unified particle system whose behaviour morphs with the blended
-- scene. one update function, one draw function, no scene-switching logic.
--
-- the module keeps an internal pool of particles. set_targets(scene) feeds it
-- the interpolated scene table each frame; update(mods) advances the sim;
-- draw(scene, mods) renders it. `mods` carries the cross-cutting modifiers:
--   { tape = 0..1, speed = 0.5..1.5, br_mult = 0..1, speed_mult = 0..1 }

local Particles = {}

local POOL = 60
local SMOOTH = 0.06          -- lerp factor toward per-particle targets
local W, H = 128, 64

local particles = {}
local scene = nil            -- current interpolated scene target
local frame = 0
local shooting = nil         -- active shooting star, or nil
local next_bird_freeze = 300 -- frames until the next bird-perch whimsy
local lightning = 0          -- frames remaining on a rain lightning flash

-- deterministic per-particle random offset in [-1, 1], stable across frames
local function noise(i, salt)
  return math.sin(i * 12.9898 + salt * 78.233) -- cheap hash-ish, in [-1,1]
end

local function rnd(a, b)
  return a + math.random() * (b - a)
end

local function clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi else return v end
end

-- place a particle at a fresh spawn location for the current scene.
local function respawn(p)
  p.x = rnd(scene.spawn_x_min, scene.spawn_x_max)
  p.y = rnd(scene.spawn_y_min, scene.spawn_y_max)
  p.brightness = 0            -- fade in, never pop
  p.flicker_phase = math.random() * math.pi * 2
end

function Particles.init()
  particles = {}
  for i = 1, POOL do
    particles[i] = {
      x = rnd(0, W), y = rnd(0, H),
      dx = 0, dy = 0,
      brightness = 0,
      active = false,
      flicker_phase = math.random() * math.pi * 2,
      off = noise(i, 1.0),      -- movement variance offset
      boff = noise(i, 2.0),     -- brightness variance offset
      freeze = 0,               -- frames left frozen (bird perch)
    }
  end
  frame = 0
  shooting = nil
  next_bird_freeze = 300
  lightning = 0
end

function Particles.set_targets(s)
  scene = s
end

-- advance the simulation one frame.
function Particles.update(mods)
  if scene == nil then return end
  frame = frame + 1

  local rate = (mods.speed or 1.0) * (mods.speed_mult or 1.0)
  local want = clamp(math.floor(scene.count + 0.5), 0, POOL)

  for i = 1, POOL do
    local p = particles[i]
    local should_be = (i <= want)

    if should_be and not p.active then
      p.active = true
      respawn(p)
    end

    -- targets: scene base + per-particle variance
    local tdx = scene.dx + p.off * scene.dx_var
    local tdy = scene.dy + p.boff * scene.dy_var
    local tbr = scene.brightness + p.off * scene.br_var

    -- bird-perch whimsy: freeze one drifting particle occasionally
    if p.freeze > 0 then
      p.freeze = p.freeze - 1
      tdx, tdy = 0, 0
    end

    -- stream shimmer: sinusoidal vertical undulation + slow brightness sway
    if scene.sine_dy and scene.sine_dy > 0.001 then
      tdy = tdy + math.sin(frame * 0.03 + i * 2.0) * scene.sine_dy
      tbr = tbr + math.sin(frame * 0.05 + i * 1.3) * 0.5
    end

    -- night twinkle: very slow, per-star brightness oscillation
    if scene.count <= 8 and scene.dy_var < 0.02 then
      tbr = tbr + math.sin(frame * 0.008 + i * 4.1) * 1.5
    end

    -- lerp toward targets (organic, not instantaneous)
    if p.active then
      p.dx = p.dx + (tdx - p.dx) * SMOOTH
      p.dy = p.dy + (tdy - p.dy) * SMOOTH
      -- if this particle should deactivate, fade brightness to 0
      local goal = should_be and tbr or 0
      p.brightness = p.brightness + (goal - p.brightness) * SMOOTH

      -- fire flicker: advance the phase only. the brightness offset is applied
      -- at DRAW time -- adding it to the persistent brightness here would feed
      -- through the lerp as a leaky integrator and amplify into a hard strobe.
      if scene.flicker and scene.flicker > 0.5 then
        p.flicker_phase = p.flicker_phase + 0.1 + math.random() * 0.05
      end

      -- integrate position
      p.x = p.x + p.dx * rate
      p.y = p.y + p.dy * rate

      -- fire: embers fade as they rise past fade_above, then respawn
      if scene.fade_above and scene.fade_above >= 0 and p.y < scene.fade_above then
        p.brightness = p.brightness * 0.95
        if p.brightness < 1 then respawn(p) end
      end

      -- wrapping / respawn at screen edges
      if p.y > H + 2 then respawn(p); p.y = scene.spawn_y_min end
      if p.y < -6 and scene.dy >= 0 then respawn(p) end
      if p.x > W + 4 then
        if scene.dx < 0 then p.x = W + 4 else p.x = scene.spawn_x_min end
        p.y = rnd(scene.spawn_y_min, scene.spawn_y_max)
      elseif p.x < -6 then
        if scene.dx < 0 then p.x = W + 4 else p.x = scene.spawn_x_min end
        p.y = rnd(scene.spawn_y_min, scene.spawn_y_max)
      end

      -- deactivate fully-faded surplus particles
      if not should_be and p.brightness < 0.5 then
        p.active = false
      end
    end
  end

  -- bird-perch whimsy scheduling (birdsong-ish scenes only)
  if scene.dx > 0.2 and scene.count < 15 then
    next_bird_freeze = next_bird_freeze - 1
    if next_bird_freeze <= 0 then
      next_bird_freeze = math.random(225, 450) -- 15-30s at 15fps
      for i = 1, POOL do
        if particles[i].active then
          particles[i].freeze = math.random(30, 45) -- 2-3s
          break
        end
      end
    end
  end

  -- rain lightning whimsy: rare single-frame bright flash
  if scene.dy > 0.8 and scene.trail > 1.5 then
    if lightning > 0 then lightning = lightning - 1 end
    if math.random() < 0.0015 then lightning = 1 end
  end

  -- shooting star whimsy (night zone) -- see gotcha #6: ~one per minute
  if scene.count <= 8 and scene.dy_var < 0.02 then
    if shooting == nil and math.random() < 0.001 then
      shooting = { x = rnd(0, 40), y = rnd(0, 24), life = 15 }
    end
  end
  if shooting then
    shooting.x = shooting.x + 6
    shooting.y = shooting.y + 6
    shooting.life = shooting.life - 1
    if shooting.life <= 0 then shooting = nil end
  end
end

-- draw the whole scene: background glow, horizon, particles, whimsy.
function Particles.draw(mods)
  if scene == nil then return end

  local tape = mods.tape or 0
  local br_mult = mods.br_mult or 1.0
  -- the display ages with the sound (addendum UX #6)
  local tape_dim = 1.0 - (tape * 0.15)
  -- position jitter grows with tape (kept subtle)
  local jitter = 0
  if tape > 0.4 then jitter = (tape - 0.4) * 0.6 end

  -- (no background glow bands and no horizon line -- full-width horizontal
  --  strips read as "lines" and, worse, the -1 no-glow sentinel interpolated
  --  during transitions, sweeping ghost bands across the screen. particles only.)

  -- particles
  local trail = scene.trail or 0
  for i = 1, POOL do
    local p = particles[i]
    if p.active and p.brightness > 0.5 then
      -- fire flicker as a transient ±3 draw offset (not accumulated -- see update)
      local flick = 0
      if scene.flicker and scene.flicker > 0.5 then
        flick = math.sin(p.flicker_phase) * 3
      end
      local br = (p.brightness + flick) * br_mult * tape_dim
      local lvl = clamp(math.floor(br + 0.5), 1, 15)

      -- draw-position jitter, grows subtly with tape (not real position)
      local jx, jy = 0, 0
      if jitter > 0 then
        jx = (math.random() * 2 - 1) * jitter
        jy = (math.random() * 2 - 1) * jitter
      end

      local dx_draw = p.x + jx
      local dy_draw = p.y + jy

      screen.level(lvl)
      if trail > 0.5 then
        screen.aa(1)
        screen.line_width(1)
        screen.move(dx_draw, dy_draw)
        screen.line(dx_draw + p.dx * trail, dy_draw + p.dy * trail)
        screen.stroke()
      else
        screen.aa(0)
        screen.pixel(math.floor(dx_draw), math.floor(dy_draw))
        screen.fill()
      end
    end
  end

  -- rain lightning flash
  if lightning > 0 then
    screen.level(14)
    screen.aa(0)
    screen.pixel(math.random(0, W - 1), math.random(0, 20))
    screen.fill()
  end

  -- shooting star
  if shooting then
    screen.level(15)
    screen.aa(1)
    screen.line_width(1)
    screen.move(shooting.x, shooting.y)
    screen.line(shooting.x - 4, shooting.y - 4)
    screen.stroke()
  end

  -- inter-station static speckle (FM tuning): faint dust between stations that
  -- clears as you lock onto a soundscape. squared to match the audio static.
  local tuning = mods.tuning or 0
  if tuning > 0.02 then
    local n = math.floor(tuning * tuning * 36)
    screen.aa(0)
    for _ = 1, n do
      screen.level(math.random(1, 3))
      screen.pixel(math.random(0, W - 1), math.random(0, H - 1))
      screen.fill()
    end
  end

  screen.aa(0)
end

return Particles
