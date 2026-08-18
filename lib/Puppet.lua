-- The puppeteer: BattlePad never re-implements a byte of battle logic.  To
-- commit a choice it hands the vanilla update loop a stub input object that
-- answers "A is pressed" (or nothing at all) and lets BattleState's own
-- menu code run -- so ghost battles, trapping locks, Struggle-when-dry,
-- disabled moves, empty PP and the forced switch after a faint all keep
-- their exact vanilla behavior, driven by the same guards that vanilla
-- players exercise.
--
-- A stub answers wasPressed/isDown from a fixed table and every unknown
-- method with a harmless false, so no real controller state leaks into a
-- synthesized frame.

local V = ...

local Puppet = {}

-- set by Core.install with the captured vanilla BattleState.update
Puppet.origUpdate = nil

local function stubFor(presses)
  local stub = { presses = presses or {} }
  return setmetatable(stub, {
    __index = function(_, key)
      if key == "wasPressed" then
        return function(self, button) return self.presses[button] == true end
      end
      return function() return false end
    end,
  })
end

function Puppet.init(origUpdate)
  Puppet.origUpdate = origUpdate
end

-- Run one vanilla update with the given synthetic presses (nil = silence).
-- Errors bubble to Core's pcall, which stands BattlePad down for the battle.
local function exec(battle, dt, presses)
  local game = battle.game
  local real = game.input
  game.input = stubFor(presses)
  local ok, err = pcall(Puppet.origUpdate, battle, dt)
  game.input = real
  if not ok then error(err, 0) end
end

-- One silent vanilla frame: runs the phase guards (faint -> replacement
-- menu, locked action -> auto-resolve, ghost re-route) without moving the
-- vanilla cursor, because the stub reports no buttons at all.
function Puppet.silent(battle, dt)
  exec(battle, dt, nil)
end

-- One synthetic B: backs a stray moveSelect out to the command menu, so
-- the classic move list and TYPE/PP panel (which draw above the deck's
-- band) can never share a frame with the deck.
function Puppet.back(battle, dt)
  exec(battle, dt, { b = true })
end

-- Steps run back-to-back within the frame; each first checks the phase it
-- expects, so a vanilla guard that consumed the turn mid-sequence (say, a
-- no-PP Struggle) simply ends the sequence early.
local function runSteps(battle, dt, steps)
  for _, step in ipairs(steps) do
    if battle.phase ~= step.phase then return end
    if step.set then step.set(battle) end
    exec(battle, dt, { [step.press] = true })
  end
end

-- Commit a deck action through the vanilla menu.
-- action: { kind = "move", index = n } | { kind = "fight" | "back" }
--       | { kind = "run" | "item" | "party" }
function Puppet.act(battle, dt, action)
  local steps
  if action.kind == "move" then
    if battle.phase == "moveSelect" then
      -- the deck lives on the vanilla move list now; one press commits
      steps = { { phase = "moveSelect", press = "a",
                  set = function(b)
                    b.moveIndex = action.index
                    b.moveSwapIndex = nil
                  end } }
    else
      -- a queued move re-enters from the command menu: FIGHT, then the slot
      steps = {
        { phase = "menu", press = "a",
          set = function(b) b.menuIndex = 1 end },
        { phase = "moveSelect", press = "a",
          set = function(b)
            b.moveIndex = action.index
            b.moveSwapIndex = nil
          end },
      }
    end
  elseif action.kind == "fight" then
    steps = { { phase = "menu", press = "a",
                set = function(b) b.menuIndex = 1 end } }
  elseif action.kind == "back" then
    steps = { { phase = "moveSelect", press = "b" } }
  elseif action.kind == "run" then
    steps = { { phase = "menu", press = "a",
                set = function(b) b.menuIndex = 4 end } }
  elseif action.kind == "item" then
    steps = { { phase = "menu", press = "a",
                set = function(b) b.menuIndex = 3 end } }
  elseif action.kind == "party" then
    steps = { { phase = "menu", press = "a",
                set = function(b) b.menuIndex = 2 end } }
  else
    return
  end
  -- entered mid-moveSelect (mod toggled on, or a stale phase): back out to
  -- the command menu first so the sequence starts where it expects
  if battle.phase == "moveSelect" and steps[1].phase == "menu" then
    table.insert(steps, 1, { phase = "moveSelect", press = "b" })
  end
  runSteps(battle, dt, steps)
end

return Puppet
