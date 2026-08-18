-- The one input funnel, after Useful Battle Cam's Sticks.lua: wrap the raw
-- gamepad entry points on src.core.Input, consume exactly what BattlePad
-- claims this instant, and forward every other byte untouched.
--
-- Two disciplines keep a claim from ever wedging the player:
--
--   * VALIDATION PER EVENT.  A claim is a *wish*; each event re-asks the
--     validator ("is the battle on top, in a phase we own?") before a single
--     button is consumed.  The bag opening, the battle popping, a Mimic menu
--     appearing -- the moment the validator says no, the pad flows to the
--     engine again with no hand-off code in between.
--
--   * OWNED-EDGE PAIRING.  A release is consumed if and only if this module
--     consumed its press (the `owned` map).  However the validator flaps
--     between the two events, the engine sees presses and releases in
--     matched pairs and can never be left holding a phantom button.
--
-- Sticks: the engine reads leftx/lefty as a held d-pad direction.  On the
-- first consumed frame the engine is fed a centred stick (so a held
-- direction lifts); settle() releases any engine-side d-pad hold each owned
-- frame; when the claim drops, forwarding real events resumes naturally.

local V = ...

local Capture = {
  claim = nil,          -- nil | "deck" | "queue"
  validator = nil,      -- function() -> bool, set by Core
  phys = {},            -- physical down-state per raw pad button
  owned = {},           -- press edges this module consumed and owes a release
  edges = {},           -- consumed press edges, drained by Deck each frame
  sticks = { leftx = 0, lefty = 0, rightx = 0, righty = 0 },
  joystick = nil,       -- most recent Joystick heard from (for glyph detect)
  installed = false,
}

Capture.DECK, Capture.QUEUE = "deck", "queue"

-- Whether radial stick claiming is live right now.  main.lua installs a
-- resolver that folds the STICKS option (AUTO / ON / OFF) together with
-- whether a Dramatic Shape family mod is active; the default claims the
-- sticks, matching a boot with neither the option nor the voxel mod.
Capture.sticksAllowed = function() return true end

local DECK_BUTTONS = {
  dpup = true, dpdown = true, dpleft = true, dpright = true,
  a = true, b = true, x = true, y = true,
  leftstick = true, rightstick = true,
}
-- While the foe acts, A and B keep their vanilla text fast-forward jobs, so
-- the queue claim leaves them alone.
local QUEUE_BUTTONS = {
  dpup = true, dpdown = true, dpleft = true, dpright = true,
  x = true, y = true, leftstick = true, rightstick = true,
}
local AXES = { leftx = true, lefty = true, rightx = true, righty = true }

local function claimSet(claim)
  if claim == Capture.DECK then return DECK_BUTTONS end
  if claim == Capture.QUEUE then return QUEUE_BUTTONS end
  return nil
end

-- Is the claim live for this exact event?
local function active()
  if not Capture.claim then return false end
  local v = Capture.validator
  if not v then return false end
  local ok, live = pcall(v)
  return ok and live == true
end

-- Wrap the raw entry points so a fault inside BattlePad's own capture logic
-- can never take the game down: on error the event is forwarded to the
-- engine exactly as an unclaimed one, which is the vanilla controller.
local function guard(inner, mine)
  return function(self, joystick, a, b)
    local ok, ret = pcall(mine, self, joystick, a, b)
    if ok then return ret end
    pcall(function()
      require("src.core.Logger").warn(
        "[battle_pad] input capture stood down: %s", tostring(ret))
      V.require("Log").line("input capture stood down: %s", tostring(ret))
    end)
    Capture.claim = nil
    return inner(self, joystick, a, b)
  end
end

function Capture.install()
  if Capture.installed then return end
  Capture.installed = true
  local Input = require("src.core.Input")
  Capture.Input = Input
  local innerPressed = Input.gamepadpressed
  local innerReleased = Input.gamepadreleased
  local innerAxis = Input.gamepadaxis
  Capture.innerPressed, Capture.innerReleased, Capture.innerAxis =
    innerPressed, innerReleased, innerAxis

  Input.gamepadpressed = guard(innerPressed, function(self, joystick, button)
    if joystick then Capture.joystick = joystick end
    Capture.phys[button] = true
    local set = claimSet(Capture.claim)
    if set and set[button] and active() then
      Capture.owned[button] = true
      Capture.edges[#Capture.edges + 1] = button
      return
    end
    return innerPressed(self, joystick, button)
  end)

  Input.gamepadreleased = guard(innerReleased, function(self, joystick, button)
    Capture.phys[button] = nil
    if Capture.owned[button] then
      Capture.owned[button] = nil
      return
    end
    return innerReleased(self, joystick, button)
  end)

  Input.gamepadaxis = guard(innerAxis, function(self, joystick, axis, value)
    if joystick then Capture.joystick = joystick end
    if AXES[axis] then
      Capture.sticks[axis] = value
      -- A stick this mod has stood down from is forwarded untouched and
      -- never centred: the camera mod that owns it must see every event.
      if Capture.sticksAllowed() and active() then
        if not Capture.stickHeld then
          -- first consumed frame: lift any direction the engine still holds
          Capture.stickHeld = true
          innerAxis(self, joystick, "leftx", 0)
          innerAxis(self, joystick, "lefty", 0)
        end
        return
      end
      Capture.stickHeld = nil
    end
    return innerAxis(self, joystick, axis, value)
  end)
end

-- Set (or clear) the claim for this frame.  Clearing hands the engine the
-- stick where it really is; owned presses stay owed regardless.
function Capture.setClaim(claim)
  if claim == Capture.claim then return end
  Capture.claim = claim
  Capture.edges = {}
  local Input = Capture.Input
  if not Input then return end
  if not claim and Capture.stickHeld then
    Capture.stickHeld = nil
    Capture.innerAxis(Input, Capture.joystick, "leftx", Capture.sticks.leftx)
    Capture.innerAxis(Input, Capture.joystick, "lefty", Capture.sticks.lefty)
  end
end

-- Once per owned frame: shed any engine-side hold on a button or direction
-- we now claim.  A press that predates the claim keeps its engine down-state
-- otherwise (its release gets consumed only when `owned` says so, which it
-- would not be) -- releasing engine-side here is idempotent and closes that
-- window.  The edge itself is forfeited; the player taps again.
--
-- The stick centring is ONCE per claim episode and only while this mod is
-- allowed the sticks at all.  Re-centring every frame meant that with a
-- mod that flies its camera on the sticks (the Dramatic Shape family), the
-- instant a battle opened BattlePad began writing "centred" into the
-- engine 60 times a second underneath that camera.  A stick this mod has
-- stood down from must be left completely alone.
function Capture.settle()
  local Input = Capture.Input
  if not Input or not Capture.claim then return end
  local set = claimSet(Capture.claim)
  for button in pairs(set) do
    if Capture.phys[button] and not Capture.owned[button] then
      Capture.innerReleased(Input, Capture.joystick, button)
      -- own it from here: its physical release must not reach the engine
      -- as an unmatched edge
      Capture.owned[button] = true
    end
  end
  if Capture.sticksAllowed() and not Capture.stickHeld then
    Capture.stickHeld = true
    Capture.innerAxis(Input, Capture.joystick, "leftx", 0)
    Capture.innerAxis(Input, Capture.joystick, "lefty", 0)
  end
end

-- Consumed press edges since the last call.
function Capture.takeEdges()
  local edges = Capture.edges
  Capture.edges = {}
  return edges
end

function Capture.isDown(button)
  return Capture.phys[button] == true
end

-- side: "left" | "right" -> x, y (centred when stick claiming stands down)
function Capture.stick(side)
  if not Capture.sticksAllowed() then return 0, 0 end
  if side == "left" then return Capture.sticks.leftx, Capture.sticks.lefty end
  return Capture.sticks.rightx, Capture.sticks.righty
end

return Capture
