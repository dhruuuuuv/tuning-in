-- tuning in
-- v1.0.0 @muchmetta
-- llllllll.co/u/muchmetta
--
-- E1 volume
-- E2 blend
-- E3 tape
-- K1+E3 tape speed
-- K2 pause / sleep
-- K3 reset tape
-- K1+K3 reset speed

engine.name = "TuningIn"

local scenes = include("tuning-in/lib/scene_data")
local particles = include("tuning-in/lib/particles")

-- encoder sensitivities (gotcha #9: tune on real hardware) -----------------
-- bumped up from the spec estimates: the originals needed several rotations
-- per control. these target roughly: blend ~1.5 turns, tape/speed ~1 turn.
local BLEND_SENS = 0.055
local TAPE_SENS  = 0.045
local SPEED_SENS = 0.03

-- per-event delta clamps (addendum UX #7) ----------------------------------
local BLEND_MAX_STEP = 0.3
local TAPE_MAX_STEP  = 0.15
local SPEED_MAX_STEP  = 0.08

-- blend is circular: six stations on a loop of circumference 6 (night wraps
-- back to birdsong). speed can stretch right down to a slow drone.
local BLEND_WRAP = 6
local SPEED_MIN = 0.05  -- near-frozen drone at the bottom, for kicks

local SLEEP_DURATION = 1800 -- 30 minutes, seconds

-- state --------------------------------------------------------------------
local state = {
  blend = 0.0,
  tape = 0.0,          -- raw knob value 0..1 (curve applied before engine)
  speed = 1.0,
  volume = 0.75,       -- knob position 0..1

  volume_show = 0,     -- frames remaining to show the volume indicator

  -- pause / breath
  paused = false,
  pause_vol = 1.0,     -- target volume multiplier (1 playing, 0 paused)
  pause_vol_cur = 1.0, -- lerped
  breath_speed = 1.0,  -- particle speed multiplier target
  breath_speed_cur = 1.0,
  breath_br = 1.0,     -- particle brightness multiplier target
  breath_br_cur = 1.0,

  -- sleep timer
  sleep_timer = false,
  sleep_start = 0,
  sleep_done = false,
  sleep_dark = false,  -- fully black after final fade

  -- idle deepening
  last_input = 0,
  idle_mult = 0.0,     -- 0 = normal, 1 = fully deep
}

local shift_held = false
local booting = true
local boot_state = "black"
local boot_alpha = 0.0     -- title text brightness scale 0..1
local boot_particle = 0.0  -- particle brightness multiplier during boot
local redraw_metro

-- pre-allocated blended scene (gotcha #4) ----------------------------------
local blended = {}
for k, v in pairs(scenes[1]) do blended[k] = v end

local function lerp_scene_into(dst, a, b, t)
  for k, v in pairs(a) do
    if type(v) == "number" then
      dst[k] = v + (b[k] - v) * t
    end
  end
end

-- smoothstep curve for the tape knob (spec: gentle → sweet → dramatic)
local function apply_tape_curve(raw)
  return raw * raw * (3 - 2 * raw)
end

-- compute and send the final engine volume (knob + all multipliers).
local function push_volume()
  local db = util.linlin(0, 1, -48, 0, state.volume)
  local amp = util.dbamp(db)
  if state.volume <= 0.001 then amp = 0 end
  amp = amp * state.pause_vol_cur
  engine.volume(amp)
end

local function push_tape()
  engine.tape(apply_tape_curve(state.tape))
end

local function mark_input()
  state.last_input = util.time()
  state.idle_mult = 0.0
end

-- params (defaults → read → bang, per gotcha #8) ---------------------------
local function setup_params()
  params:add_separator("tuning in")

  params:add_control("blend", "blend",
    controlspec.new(0, BLEND_WRAP, "lin", 0, 0.0))
  params:set_action("blend", function(v)
    state.blend = v
    engine.blend(v)
  end)

  params:add_control("tape", "tape",
    controlspec.new(0, 1, "lin", 0, 0.0))
  params:set_action("tape", function(v)
    state.tape = v
    push_tape()
  end)

  params:add_control("speed", "speed",
    controlspec.new(SPEED_MIN, 1.5, "lin", 0, 1.0))
  params:set_action("speed", function(v)
    state.speed = v
    engine.speed(v)
  end)

  params:add_control("volume", "volume",
    controlspec.new(0, 1, "lin", 0, 0.75))
  params:set_action("volume", function(v)
    state.volume = v
    push_volume()
  end)

  params:read()  -- restore last session if a pset exists
  params:bang()  -- fire all actions, sending restored values to the engine
end

-- boot sequence ------------------------------------------------------------
local function run_boot()
  clock.run(function()
    boot_state = "black"
    clock.sleep(0.5)

    -- slow volume fade-in, running in parallel with the whole intro (~8s). the
    -- synth is born at the restored blend/tape/speed (the engine remembers), so
    -- there's no scene jump -- just the right soundscape gently swelling in.
    clock.run(function()
      local vsteps = math.floor(8.0 * 15)
      for i = 1, vsteps do
        if not booting then return end -- hand the volume ramp back to tick()
        state.pause_vol_cur = i / vsteps
        push_volume()
        clock.sleep(1 / 15)
      end
    end)

    -- title fades in over ~1s
    boot_state = "title_in"
    for i = 1, 15 do
      boot_alpha = i / 15
      clock.sleep(1 / 15)
    end
    boot_alpha = 1.0

    boot_state = "title_hold"
    clock.sleep(1.5)

    boot_state = "title_out"
    for i = 15, 0, -1 do
      boot_alpha = i / 15
      clock.sleep(1 / 15)
    end
    boot_alpha = 0.0

    -- particles fade in over ~2s (input stays gated until here -- gotcha #3)
    boot_state = "reveal"
    local steps = 30
    for i = 1, steps do
      boot_particle = math.min((i / steps) * 1.5, 1.0)
      clock.sleep(1 / 15)
    end
    boot_particle = 1.0

    booting = false  -- release input; tick() finishes the volume ramp to 1.0
    boot_state = "run"
    mark_input()
  end)
end

function init()
  math.randomseed(util.time() * 1000)
  particles.init()

  booting = true
  boot_particle = 0.0
  state.pause_vol_cur = 0.0 -- so params:bang() sends volume 0 (born silent)

  -- params:bang() fires the actions, which send blend/tape/speed/volume to the
  -- engine; the engine remembers them and creates the synth in that state.
  setup_params()

  -- point the engine at this script's audio folder (gotcha #11)
  engine.folder(norns.state.path .. "audio/")

  redraw_metro = metro.init()
  redraw_metro.time = 1 / 15
  redraw_metro.event = tick
  redraw_metro:start()

  run_boot()
end

-- per-frame tick: update sim state, then request a redraw ------------------
function tick()
  -- while booting, run_boot owns the volume/particle ramps; don't fight it.
  if not booting then
    -- lerp pause / breath multipliers toward their targets
    state.pause_vol_cur = state.pause_vol_cur + (state.pause_vol - state.pause_vol_cur) * 0.06
    state.breath_speed_cur = state.breath_speed_cur + (state.breath_speed - state.breath_speed_cur) * 0.06
    state.breath_br_cur = state.breath_br_cur + (state.breath_br - state.breath_br_cur) * 0.06
    push_volume()

    -- idle deepening: drift toward a deeper world after 60s untouched
    local idle = util.time() - state.last_input
    if idle > 60 then
      state.idle_mult = math.min(state.idle_mult + 0.01, 1.0)
    else
      state.idle_mult = math.max(state.idle_mult - 0.02, 0.0)
    end
  end

  -- sleep timer progress (elapsed time, not accumulation -- gotcha #7)
  if state.sleep_timer and not state.sleep_done then
    local elapsed = util.time() - state.sleep_start
    local progress = math.min(elapsed / SLEEP_DURATION, 1.0)
    state.pause_vol = 1.0 - progress
    state.breath_br = 1.0 - progress * 0.6
    if progress >= 1.0 then
      state.sleep_done = true
      run_sleep_end()
    end
  end

  -- build the interpolated scene for this frame (circular: station 6 wraps to 1)
  local b = state.blend % BLEND_WRAP
  local idx = math.floor(b) + 1
  local frac = b - math.floor(b)
  local nxt = (idx % 6) + 1
  lerp_scene_into(blended, scenes[idx], scenes[nxt], frac)

  -- idle deepening multipliers
  local dm = state.idle_mult
  blended.count = blended.count * (1.0 + 0.12 * dm)

  particles.set_targets(blended)
  particles.update({
    tape = state.tape,
    speed = state.speed * (1.0 - 0.1 * dm),
    speed_mult = state.breath_speed_cur,
    br_mult = state.breath_br_cur,
  })

  redraw()
end

-- final fade at the end of the sleep timer ---------------------------------
function run_sleep_end()
  clock.run(function()
    engine.volume(0)
    -- one faint star holds for 30s, then fades over 30s, then black (UX #3)
    state.breath_br = 0.12
    clock.sleep(30)
    state.breath_br = 0.0
    clock.sleep(30)
    state.sleep_dark = true
  end)
end

-- input handling -----------------------------------------------------------
function enc(n, d)
  if booting then return end
  wake_if_dark()
  mark_input()

  if n == 1 then
    -- volume, -48..0 dB
    state.volume = util.clamp(state.volume + d * 0.02, 0, 1)
    params:set("volume", state.volume)
    state.volume_show = 22 -- ~1.5s at 15fps

  elseif n == 2 then
    -- blend, circular: turns endlessly, night wraps back into birdsong
    local step = util.clamp(d * BLEND_SENS, -BLEND_MAX_STEP, BLEND_MAX_STEP)
    state.blend = (state.blend + step) % BLEND_WRAP
    params:set("blend", state.blend)

  elseif n == 3 then
    if shift_held then
      -- tape speed
      local step = util.clamp(d * SPEED_SENS, -SPEED_MAX_STEP, SPEED_MAX_STEP)
      local sp = util.clamp(state.speed + step, SPEED_MIN, 1.5)
      if math.abs(sp - 1.0) < 0.02 then sp = 1.0 end -- soft detent
      state.speed = sp
      params:set("speed", sp)
    else
      -- tape
      local step = util.clamp(d * TAPE_SENS, -TAPE_MAX_STEP, TAPE_MAX_STEP)
      state.tape = util.clamp(state.tape + step, 0, 1)
      params:set("tape", state.tape)
    end
  end
end

function key(n, z)
  if booting then return end

  if n == 1 then
    shift_held = (z == 1)
    return
  end

  if z == 0 then
    -- K2 release: distinguish tap from hold via the hold clock
    if n == 2 then handle_k2_release() end
    return
  end

  -- z == 1 (press)
  wake_if_dark()
  mark_input()

  if n == 2 then
    handle_k2_press()

  elseif n == 3 then
    if shift_held then
      -- reset speed to 1.0 (0.3s glide)
      glide_param("speed", state.speed, 1.0, 0.3)
    else
      -- reset tape to 0.0 (0.5s glide)
      glide_param("tape", state.tape, 0.0, 0.5)
    end
  end
end

-- K2: tap toggles pause; hold 2s starts the sleep timer --------------------
local k2_hold_clock = nil

function handle_k2_press()
  k2_hold_clock = clock.run(function()
    clock.sleep(2.0)
    k2_hold_clock = nil
    -- held long enough: start (or cancel) the sleep timer
    if state.sleep_timer then
      cancel_sleep_timer()
    else
      start_sleep_timer()
    end
  end)
end

function handle_k2_release()
  if k2_hold_clock then
    -- released before 2s: this was a tap
    clock.cancel(k2_hold_clock)
    k2_hold_clock = nil
    if state.sleep_timer then
      cancel_sleep_timer() -- tap during timer cancels it
    else
      toggle_pause()
    end
  end
end

function toggle_pause()
  state.paused = not state.paused
  if state.paused then
    -- the world holds its breath (addendum UX #2)
    state.pause_vol = 0.0
    state.breath_speed = 0.05
    state.breath_br = 0.4
  else
    state.pause_vol = 1.0
    state.breath_speed = 1.0
    state.breath_br = 1.0
  end
end

function start_sleep_timer()
  state.sleep_timer = true
  state.sleep_done = false
  state.sleep_dark = false
  state.sleep_start = util.time()
end

function cancel_sleep_timer()
  state.sleep_timer = false
  state.sleep_done = false
  state.sleep_dark = false
  -- 3s volume return
  clock.run(function()
    local start = state.pause_vol
    local steps = 45
    for i = 1, steps do
      state.pause_vol = start + (1.0 - start) * (i / steps)
      state.breath_br = 1.0
      clock.sleep(1 / 15)
    end
    state.pause_vol = 1.0
  end)
end

-- turn any encoder while dark → replay boot from saved state
function wake_if_dark()
  if state.sleep_dark then
    state.sleep_dark = false
    state.sleep_timer = false
    state.sleep_done = false
    state.pause_vol = 1.0
    state.breath_br = 1.0
    booting = true
    boot_particle = 0.0
    state.pause_vol_cur = 0.0
    run_boot()
  end
end

-- smoothly glide a param to a target over `dur` seconds
function glide_param(name, from, to, dur)
  clock.run(function()
    local steps = math.max(1, math.floor(dur * 15))
    for i = 1, steps do
      params:set(name, from + (to - from) * (i / steps))
      clock.sleep(1 / 15)
    end
    params:set(name, to)
  end)
end

-- drawing ------------------------------------------------------------------
local function draw_moon(progress)
  -- 5x5 crescent at top-right (122,1). brightness diminishes with progress.
  local br = math.floor(util.linlin(0, 1, 8, 1, progress) + 0.5)
  screen.level(util.clamp(br, 1, 8))
  screen.aa(0)
  -- simple crescent: a small arc of pixels
  screen.pixel(123, 1)
  screen.pixel(124, 1)
  screen.pixel(122, 2)
  screen.pixel(122, 3)
  screen.pixel(123, 4)
  screen.pixel(124, 4)
  screen.fill()
end

local function draw_volume_indicator()
  if state.volume_show > 0 then
    state.volume_show = state.volume_show - 1
    local br = math.floor(state.volume * 12) + 2
    local fade = math.min(state.volume_show, 8)
    screen.level(util.clamp(math.floor(br * fade / 8), 0, 15))
    screen.aa(0)
    screen.pixel(1, 2)
    screen.pixel(1, 3)
    screen.pixel(1, 4)
    screen.fill()
  end
end

function redraw()
  screen.clear()

  if state.sleep_dark then
    screen.update()
    return
  end

  if booting and boot_state ~= "reveal" and boot_state ~= "run" then
    if boot_state == "title_in" or boot_state == "title_hold" or boot_state == "title_out" then
      local lvl = math.floor(boot_alpha * 8 + 0.5)
      if lvl > 0 then
        screen.level(lvl)
        screen.font_face(1)
        screen.font_size(8)
        screen.aa(0)
        local txt = "tuning in"
        local w = screen.text_extents(txt)
        screen.move(64 - w / 2, 36)
        screen.text(txt)
      end
    end
    screen.update()
    return
  end

  -- particle world (dimmed during boot reveal)
  local br_mult = state.breath_br_cur
  if booting then br_mult = br_mult * boot_particle end

  -- circular distance to the nearest station (0 = locked on, 1 = mid-tune)
  local bf = state.blend % 1
  local tuning = math.min(bf, 1 - bf) * 2

  particles.set_targets(blended)
  particles.draw({
    tape = state.tape,
    br_mult = br_mult,
    tuning = tuning,
  })

  -- overlays
  draw_volume_indicator()

  if shift_held then
    screen.level(8)
    screen.aa(0)
    screen.pixel(124, 1)
    screen.fill()
  end

  if state.sleep_timer and not state.sleep_done then
    local elapsed = util.time() - state.sleep_start
    local progress = math.min(elapsed / SLEEP_DURATION, 1.0)
    draw_moon(progress)
  end

  screen.update()
end

function cleanup()
  params:write() -- remember blend / tape / speed / volume
end
