-- The Gold (Gen 2) arm.  Gold is a second engine: src/core/Game2.lua
-- boots, src/battle/gen2/Battle.lua is the battle model, and
-- src/ui/gen2/BattleState.lua is the battle screen.  The screen exposes
-- direct semantic calls -- chooseMenu / chooseMove / submit -- so this arm
-- decides with the shared Deck and then simply calls them; the Gen 1
-- synthetic-press puppeteer has no job here.
--
-- What is shared with Gen 1: Capture (same src.core.Input singleton),
-- Deck's compass/radial/queue rules, Skin's band (drawn via render.hud,
-- which Game2 raises with the same signature), Config, PadIcons.
--
-- Phases: "menu" / "moves" are the deck's; "resolving" is the queue
-- window (Gold reads A/B there to advance held messages, so those stay
-- forwarded).  The Bug-Catching Contest (screen.contest) and the DUDE
-- catch tutorial (screen.tutorial) keep Gold's own classic menus.  The
-- first error in any frame stands the arm down for that battle and the
-- vanilla screen carries on with the real controller.

local V = ...
local Config = V.require("Config")
local Capture = V.require("Capture")
local Deck = V.require("Deck")

local Core2 = {
  installed = false,
  game = nil,
  screen = nil,      -- the live Gen2 battle screen while one is up
  origUpdate = nil,
}

local function claimValid()
  local screen, game = Core2.screen, Core2.game
  if not screen or not game or not game.stack then return false end
  if game.stack:top() ~= screen then return false end
  local phase = screen.phase
  if Capture.claim == Capture.DECK then
    return phase == "menu" or phase == "moves"
  end
  return phase == "resolving"
end

local function standDown(screen, err)
  local st = Deck.state(screen)
  st.disabled = true
  Capture.setClaim(nil)
  V.require("Log").line("gen2 stand-down: %s", tostring(err))
  pcall(function()
    require("src.core.Logger").warn(
      "[battle_pad] gen2: standing down for this battle: %s", tostring(err))
  end)
end

-- a silent vanilla frame: Gold's update early-returns through slides,
-- animations and held messages before its phase code reads the cursor,
-- and all of that must keep running under the deck
local function stubInput()
  return setmetatable({}, {
    __index = function() return function() return false end end,
  })
end

local function silent(screen, dt)
  local game = screen.game
  local real = game.input
  game.input = stubInput()
  local ok, err = pcall(Core2.origUpdate, screen, dt)
  game.input = real
  if not ok then error(err, 0) end
end

local function apply(screen, action)
  if action.kind == "move" then
    if screen.phase == "menu" then screen:chooseMenu("fight") end
    if screen.phase == "moves" then screen:chooseMove(action.index) end
  elseif action.kind == "fight" then
    if screen.phase == "menu" then screen:chooseMenu("fight") end
  elseif action.kind == "back" then
    if screen.phase == "moves" then screen.phase = "menu" end
  elseif action.kind == "run" then
    if screen.phase == "moves" then screen.phase = "menu" end
    if screen.phase == "menu" then screen:chooseMenu("run") end
  elseif action.kind == "item" then
    if screen.phase == "moves" then screen.phase = "menu" end
    if screen.phase == "menu" then screen:chooseMenu("item") end
  elseif action.kind == "party" then
    if screen.phase == "moves" then screen.phase = "menu" end
    if screen.phase == "menu" then screen:chooseMenu("party") end
  end
end

-- returns true when this arm ran the frame itself
local function frame(screen, dt)
  Core2.screen = screen
  if not Deck.owns2(screen) then
    Capture.setClaim(nil)
    return false
  end
  local phase = screen.phase

  if phase == "menu" or phase == "moves" then
    silent(screen, dt)
    phase = screen.phase
    if phase ~= "menu" and phase ~= "moves" then
      Capture.setClaim(nil)
      return true
    end
    Capture.setClaim(Capture.DECK)
    Capture.settle()
    local queued = Deck.takeValidQueued2(screen)
    if queued then
      apply(screen, queued)
      return true
    end
    local action = Deck.frame2(screen, dt)
    if action then apply(screen, action) end
    return true
  end

  if phase == "resolving" then
    if Config.get(screen.game, "queueing") == true then
      Capture.setClaim(Capture.QUEUE)
      Capture.settle()
      Deck.queueFrame2(screen, dt)
    else
      Capture.setClaim(nil)
    end
    return false -- vanilla advances the resolution with real input (A/B)
  end

  -- submenus, forced switches, learn/forget flows: vanilla, real input
  Capture.setClaim(nil)
  return false
end

function Core2.install(game)
  if Core2.installed then return end
  Core2.installed = true
  Core2.game = game
  Capture.install()
  Capture.validator = claimValid

  local BattleState = require("src.ui.gen2.BattleState")
  local origUpdate = BattleState.update
  Core2.origUpdate = origUpdate

  BattleState.update = function(self, dt)
    local ok, handled = pcall(frame, self, dt)
    if ok then
      if handled then return end
    else
      standDown(self, handled)
    end
    return origUpdate(self, dt)
  end
end

function Core2.onBattleEnded()
  Core2.screen = nil
  Capture.setClaim(nil)
end

return Core2
