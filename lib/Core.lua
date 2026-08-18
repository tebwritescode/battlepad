-- Where BattlePad meets the engine: one wrap on BattleState.update, one on
-- BattleState.buildScreen, one on Screens.push.  Everything else in the mod
-- hangs off what these three observe.
--
-- The update wrap is the whole safety story: every BattlePad frame runs
-- under pcall, and the first error stands the mod down FOR THAT BATTLE and
-- falls through to the vanilla update with the real input object -- the
-- player keeps a working menu no matter what this mod does.

local V = ...
local Config = V.require("Config")
local Capture = V.require("Capture")
local Deck = V.require("Deck")
local Puppet = V.require("Puppet")
local Skin = V.require("Skin")

local Core = {
  installed = false,
  game = nil,
  battle = nil,       -- the live BattleState, set by update wrap + events
  origUpdate = nil,
}

-- Claim validity, re-asked for every single input event (see Capture): the
-- battle must be the top screen, in a phase BattlePad owns.
local function claimValid()
  local battle, game = Core.battle, Core.game
  if not battle or not game or not game.stack then return false end
  if game.stack:top() ~= battle then return false end
  local phase = battle.phase
  if Capture.claim == Capture.DECK then
    return phase == "menu" or phase == "moveSelect"
  end
  return phase == "messages"
end

local function standDown(battle, err)
  local st = Deck.state(battle)
  st.disabled = true
  Capture.setClaim(nil)
  V.require("Log").line("gen1 stand-down: %s", tostring(err))
  pcall(function()
    require("src.core.Logger").warn(
      "[battle_pad] standing down for this battle: %s", tostring(err))
  end)
end

-- The BattlePad frame.  Returns true when it ran the vanilla update itself
-- (via Puppet); false hands the frame to vanilla with real input.
local function frame(battle, dt)
  Core.battle = battle
  if not Deck.owns(battle) then
    Capture.setClaim(nil)
    return false
  end
  local phase = battle.phase

  if phase == "menu" or phase == "moveSelect" then
    -- vanilla guards first, on a silent frame: forced replacement after a
    -- faint, locked actions, the ghost re-route -- all vanilla, all intact
    Puppet.silent(battle, dt)
    phase = battle.phase
    if phase ~= "menu" and phase ~= "moveSelect" then
      -- a guard consumed the frame (or the turn); nothing left to own
      Capture.setClaim(nil)
      return true
    end
    Capture.setClaim(Capture.DECK)
    Capture.settle()
    local queued = Deck.takeValidQueued(battle)
    if queued then
      Puppet.act(battle, dt, queued)
      return true
    end
    local action = Deck.frame(battle, dt,
      phase == "moveSelect" and "moves" or "menu",
      battle.player.curMoves or {}, battle.moveIndex)
    if action then Puppet.act(battle, dt, action) end
    return true
  end

  if phase == "messages" then
    if Config.get(battle.game, "queueing") == true
        and battle.afterQueue == "menu"
        and battle.player and battle.player.mon
        and battle.player.mon.hp > 0 then
      Capture.setClaim(Capture.QUEUE)
      Capture.settle()
      Deck.queueFrame(battle, dt)
    else
      Capture.setClaim(nil)
    end
    return false -- vanilla runs the message queue with real input (A/B skip)
  end

  -- mimicSelect and anything new: vanilla, real input
  Capture.setClaim(nil)
  return false
end

function Core.install(game)
  if Core.installed then return end
  Core.installed = true
  Core.game = game
  Capture.install()
  Capture.validator = claimValid

  local BattleState = require("src.battle.BattleState")
  local origUpdate = BattleState.update
  Core.origUpdate = origUpdate
  Puppet.init(origUpdate)

  BattleState.update = function(self, dt)
    local ok, handled = pcall(frame, self, dt)
    if ok then
      if handled then return end
    else
      standDown(self, handled)
    end
    return origUpdate(self, dt)
  end

  -- The deck now LIVES on the vanilla move-select phase, whose classic
  -- TYPE/PP panel draws ABOVE the band; skip the whole text-area draw
  -- while the deck owns those phases (the band occludes the rest anyway).
  local origDrawTextArea = BattleState.drawTextArea
  BattleState.drawTextArea = function(self)
    local ok, owned = pcall(function()
      return Deck.owns(self)
             and (self.phase == "menu" or self.phase == "moveSelect")
    end)
    if ok and owned then return end
    return origDrawTextArea(self)
  end

  -- battle-pushed screens (bag, party, forced switch) come through here;
  -- variadic pass-through matches the engine's own buildScreen(id, ...)
  local origBuild = BattleState.buildScreen
  BattleState.buildScreen = function(self, id, ...)
    local screen = origBuild(self, id, ...)
    if Deck.owns(self) then pcall(Skin.tag, screen, id, self) end
    return screen
  end

  -- the bag's party-target picker (heals, X items) comes through here
  local Screens = require("src.ui.Screens")
  local origPush = Screens.push
  Screens.push = function(game2, id, ...)
    local result = origPush(game2, id, ...)
    if Core.battle and (id == "PartyMenu" or id == "BagMenu")
        and Deck.owns(Core.battle)
        and game2 and game2.stack then
      pcall(Skin.tag, game2.stack:top(), id, Core.battle)
    end
    return result
  end
end

-- events wired in main.lua
function Core.onBattleStarted(battle)
  if battle then Core.battle = battle end
end

function Core.onBattleEnded()
  Core.battle = nil
  Capture.setClaim(nil)
end

return Core
