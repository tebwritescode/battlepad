-- BattlePad: the battle, played from the controller in your hands.
--
-- Gen 1's battle flow answers four questions a turn -- which action, which
-- move, which item, which Pokémon -- through nested cursor menus built for
-- two buttons.  A modern pad has ten inputs and two sticks.  BattlePad
-- spends them:
--
--   * the D-PAD is the move compass: north/west/east/south are the four
--     move slots, straight from the command deck
--   * the FACE BUTTONS are the commands: south FIGHT, east RUN (held),
--     north POKEMON, west PACK -- drawn with the glyphs of the pad in your
--     hands (Xbox letters, PlayStation shapes, Nintendo letters)
--   * the LEFT STICK is a radial move selector, the RIGHT STICK a radial
--     command selector: deflect to highlight, release to commit
--   * while the foe is still acting, the same compass QUEUES the next
--     action, spinners orbit the moves, and the pick fires the instant the
--     menu returns -- dissolving quietly if the situation changed
--
-- Every menu surface of the battle -- command deck, bag, party, message
-- box -- wears a modern window-space skin, while the scene above (sprites,
-- HP bars, animations) stays exactly the engine's own.
--
-- Under the hood BattlePad is a puppeteer, not a rewrite: committed choices
-- are fed through the vanilla update loop as synthetic button presses, so
-- ghost battles, trapping locks, Struggle, disabled moves and the forced
-- switch after a faint all run the engine's own code.  Safari, the old-man
-- demo and Mimic's copy menu keep the classic UI on purpose.  The first
-- error in any BattlePad frame stands the mod down for that battle and the
-- vanilla menu carries on with the real controller.
--
-- Keyboard players keep everything: arrows are the compass, A confirms,
-- B backs out (held: run), SELECT opens the party, START opens the pack.

local mod = ...

-- ------- the mod namespace (same shape as Useful Battle Cam's)
--
-- lib/ modules load through V rather than package.path: a mod directory is
-- not on it, and may live inside a mounted .modpkg archive.

local V = { mod = mod, path = mod.path }

local function chunkFor(rel)
  local source = mod:read(rel)
  if not source then
    error(("battle_pad: %s is missing -- reinstall the mod"):format(rel), 0)
  end
  local chunk, err = load(source, "@" .. mod.path .. "/" .. rel)
  if not chunk then
    error(("battle_pad: %s did not compile: %s"):format(rel, tostring(err)), 0)
  end
  return chunk
end

local modules = {}
function V.require(name)
  local hit = modules[name]
  if hit ~= nil then return hit end
  local value = chunkFor("lib/" .. name .. ".lua")(V)
  modules[name] = value
  return value
end

local Config = V.require("Config")
local Capture = V.require("Capture")
local Deck = V.require("Deck")
local Core = V.require("Core")
local Log = V.require("Log")
local Skin = V.require("Skin")

-- ------- options
--
-- One schema, three surfaces: the mod manager sees it via options:define,
-- the in-game OPTIONS menu gets live rows below, and the runtime reads the
-- same persisted bucket both of them write.
mod.options:define(Config.schema)

mod.hooks:wrap("ui.options.rows", function(next_, game, rows)
  local out = next_(game, rows)
  if type(out) ~= "table" then return out end
  for _, row in ipairs(Config.optionRows(game)) do
    out[#out + 1] = row
  end
  return out
end)

-- ------- install
--
-- Engine patches wait for game.ready (the sanctioned way to obtain the Game
-- object); until then the mod is pure registration, which is also what lets
-- the headless test harness load it without a graphics stack.
mod.events:on("game.ready", function(payload)
  if not (payload and payload.game) then return end
  -- one arm per engine: Gen 1's puppeteer, or Gold's direct semantic calls
  local gen = 1
  pcall(function()
    local GameVersion = require("src.core.GameVersion")
    gen = GameVersion.generation(GameVersion.current)
  end)
  if gen == 2 then
    V.require("Core2").install(payload.game)
  else
    Core.install(payload.game)
  end
  Log.session(payload.game, mod.version)
  Log.installCrashCapture()
  -- The Dramatic Shape family's staged battles fly their camera on the
  -- analog sticks.  The STICKS option decides who owns them: AUTO stands
  -- BattlePad down while a voxel mod is active, ON keeps the radial
  -- selection and overrides the camera, OFF leaves the sticks alone.
  local voxelId = nil
  for _, id in ipairs({ "DRAMATIC_SHAPE", "BATTLE_ART_VOXEL_FORK",
                        "DRAMALESS_SHAPE" }) do
    if mod.find(id) then
      voxelId = id
      mod.log:info("%s is active; STICKS AUTO leaves it the battle camera", id)
      break
    end
  end
  V.require("Deck").voxelPresent = voxelId ~= nil
  Capture.sticksAllowed = function()
    local mode = Config.get(Core.game, "sticks")
    if mode == "on" then return true end
    if mode == "off" then return false end
    return voxelId == nil
  end
end)

mod.events:on("battle.started", function(payload)
  Core.onBattleStarted(payload and payload.battle)
  Log.line("battle.started (kind=%s)",
    tostring(payload and payload.kind))
end)
mod.events:on("battle.ended", function()
  Core.onBattleEnded()
  V.require("Core2").onBattleEnded()
  Log.line("battle.ended")
end)
mod.events:on("screen.popped", function()
  -- a battle that leaves the stack by any path releases the pad
  local game = Core.game
  if Core.battle and game and game.stack and game.stack:top() ~= Core.battle then
    Capture.setClaim(nil)
  end
end)

-- All BattlePad pixels ride the window-space HUD hook, after the finished
-- frame; a failure here skips one frame of chrome, never the game's own.
mod.hooks:wrap("render.hud", function(next_, game, viewport)
  next_(game, viewport)
  if Core.installed or V.require("Core2").installed then
    local ok, err = pcall(Skin.hud, game, viewport)
    if not ok then Log.line("Skin.hud error: %s", tostring(err)) end
    if Log.on() and love.timer and love.timer.getTime() < 60 then
      local crash = Log.crashReport()
      if crash then pcall(Skin.crashPanel, crash, viewport) end
    end
  end
end)

-- ------- exports: the headless test suite reaches the modules through here
mod.exports.version = mod.version
mod.exports.lib = V
