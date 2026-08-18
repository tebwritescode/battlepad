-- BattlePad headless suite: drives the real loader through the modkit SDK,
-- then exercises every pure decision the mod makes -- compass math, queue
-- validation, brand detection, option cycling -- and the input funnel's
-- forward-when-unclaimed guarantee against the real src.core.Input.
--
-- Run from the engine root:  luajit mods/battle_pad/tests/battle_pad_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")

-- ---- loads clean through the real loader ----

local run = T.sdk.loadMod("mods/battle_pad", {})
T.eq(#run.errors, 0, "battle_pad loads clean through the production loader")

local mod = run.mods.battle_pad
T.check(mod ~= nil, "the loader discovered battle_pad")

local exports = run.loader.exports.battle_pad
T.check(exports ~= nil and exports.lib ~= nil, "battle_pad publishes its lib")
T.eq(exports.version, mod.manifest.version, "exported version matches the manifest")

-- the incompatibility is a manifest fact the loader can enforce
local declared = false
for _, spec in ipairs(mod.manifest.conflicts or {}) do
  local id = type(spec) == "table" and spec.id or spec
  if tostring(id):find("USEFUL_BATTLE_CAM", 1, true) then declared = true end
end
T.check(declared, "USEFUL_BATTLE_CAM is declared incompatible in the manifest")

-- ---- loads on a Gen 2 boot (state, not just error count: a gate skip
-- is deliberately not an error) ----

local run2 = T.sdk.loadMod("mods/battle_pad", { generation = 2 })
T.eq(run2.mod and run2.mod.state, "loaded",
  "runs on gen 2: " .. tostring(run2.mod and run2.mod.skipReason))
T.eq(#run2.errors, 0, "gen 2 load carries no boot errors")
run2.release()

local V = exports.lib
local Config = V.require("Config")
local Deck = V.require("Deck")
local PadIcons = V.require("PadIcons")
local Capture = V.require("Capture")

-- ---- Config: defaults, persistence bucket, option rows ----

local stubGame = { save = { options = {} } }
T.eq(Config.get(stubGame, "enabled"), true, "BATTLEPAD defaults ON")
T.eq(Config.get(stubGame, "quick_moves"), false, "QUICK MOVES defaults OFF")
T.eq(Config.get(stubGame, "queueing"), true, "QUEUE NEXT defaults ON")
T.eq(Config.get(stubGame, "icons"), "auto", "PAD ICONS defaults AUTO")

Config.set(stubGame, "quick_moves", true)
T.eq(Config.get(stubGame, "quick_moves"), true, "a set value reads back")
T.eq(stubGame.save.options.modOptions.battle_pad.quick_moves, true,
  "values persist in the engine's own modOptions bucket")

local rows = Config.optionRows(stubGame)
T.eq(#rows, #Config.schema, "one OPTIONS row per schema entry")
local iconsRow
for _, row in ipairs(rows) do
  if row.id == "battle_pad:icons" then iconsRow = row end
end
T.check(iconsRow ~= nil, "the PAD ICONS row exists")
T.eq(iconsRow.value(), "AUTO", "PAD ICONS row shows AUTO")
iconsRow.step(stubGame, 1)
T.eq(Config.get(stubGame, "icons"), "xbox", "stepping AUTO forward lands on XBOX")
iconsRow.step(stubGame, -1)
T.eq(Config.get(stubGame, "icons"), "auto", "stepping back returns to AUTO")

-- ---- PadIcons: brand detection ----

T.eq(PadIcons.detect("Sony DualSense Wireless Controller"), "ps", "DualSense reads PS")
T.eq(PadIcons.detect("PS4 Controller"), "ps", "PS4 pad reads PS")
T.eq(PadIcons.detect("Xbox Series X Controller"), "xbox", "Xbox pad reads Xbox")
T.eq(PadIcons.detect("Nintendo Switch Pro Controller"), "nin", "Pro Controller reads Nintendo")
T.eq(PadIcons.detect("XInput Controller #1"), "xbox", "XInput reads Xbox")
-- vendor id from the SDL GUID when the name says nothing: 054c / 045e / 057e
T.eq(PadIcons.detect("Generic Pad", "030000004c050000c405000000000000"), "ps",
  "Sony vendor id in the GUID reads PS")
T.eq(PadIcons.detect("Generic Pad", "030000005e040000e002000000000000"), "xbox",
  "Microsoft vendor id in the GUID reads Xbox")
T.eq(PadIcons.detect("Generic Pad", "030000007e050000062000000000000"), "nin",
  "Nintendo vendor id in the GUID reads Nintendo")
T.eq(PadIcons.detect("Some Fight Stick"), nil, "an unknown pad stays undecided")
T.eq(PadIcons.styleFor("ps", nil), "ps", "a pinned OPTIONS choice wins over detection")
T.eq(PadIcons.styleFor("auto", nil), "xbox", "AUTO with no pad lands on Xbox lettering")

-- ---- Deck: compass math ----

local q
q = Deck.quadrant(0, -1); T.eq(q, "north", "stick up is north")
q = Deck.quadrant(0, 1); T.eq(q, "south", "stick down is south")
q = Deck.quadrant(1, 0); T.eq(q, "east", "stick right is east")
q = Deck.quadrant(-1, 0); T.eq(q, "west", "stick left is west")
q = Deck.quadrant(0.7, -0.7); T.eq(q, "north", "the 45-degree corner rounds north")
local none, mag = Deck.quadrant(0, 0)
T.check(none == nil and mag == 0, "a centred stick names no quadrant")

-- ---- Deck: radial episodes ----

local ep = { peak = 0 }
local verb
q, verb = Deck.radialStep(ep, 0, -0.95, false)
T.check(q == "north" and verb == "hold", "a full deflection holds its quadrant")
q, verb = Deck.radialStep(ep, 0, -0.1, false)
T.check(q == "north" and verb == "commit", "releasing after a full push commits")
q, verb = Deck.radialStep(ep, 0, -0.6, false)
T.eq(verb, "hold", "a partial push holds")
q, verb = Deck.radialStep(ep, 0, 0, false)
T.eq(verb, "idle", "releasing a partial push commits nothing")
ep = { peak = 0 }
q, verb = Deck.radialStep(ep, 0.95, 0, true)
T.check(q == "east" and verb == "commit", "QUICK MOVES commits at full push")
q, verb = Deck.radialStep(ep, 0.95, 0, true)
T.eq(verb, "hold", "one episode commits once")

-- ---- Deck: queue validation ----

local mon = { hp = 20 }
local battle = {
  player = {
    mon = mon,
    curMoves = { { id = "TACKLE", pp = 10 }, { id = "GROWL", pp = 0 } },
    disabledSlot = nil,
  },
}
local wish = { kind = "move", index = 1, mon = mon }
T.check(Deck.validQueued(battle, wish) ~= nil, "a healthy queued move survives")
T.eq(Deck.validQueued(battle, { kind = "move", index = 2, mon = mon }), nil,
  "a queued move with no PP dissolves")
battle.player.disabledSlot = 1
T.eq(Deck.validQueued(battle, wish), nil, "a queued move that got disabled dissolves")
battle.player.disabledSlot = nil
T.eq(Deck.validQueued(battle, { kind = "move", index = 1, mon = { hp = 5 } }), nil,
  "a queued move for a different battler dissolves")
mon.hp = 0
T.eq(Deck.validQueued(battle, wish), nil, "a queued move for a fainted battler dissolves")
mon.hp = 20
T.check(Deck.validQueued(battle, { kind = "run", mon = mon }) ~= nil,
  "a queued command survives with the battler alive")
T.eq(Deck.validQueued(battle, nil), nil, "no wish, no action")

-- ---- Capture: the funnel forwards untouched when unclaimed ----

Capture.install()
local Input = require("src.core.Input")

Input:init()
Input:gamepadpressed(nil, "dpleft")
T.check(Input:isDown("left"), "unclaimed, a d-pad press still presses its direction")
Input:gamepadreleased(nil, "dpleft")
T.check(not Input:isDown("left"), "and releases it")
Input:gamepadpressed(nil, "x")
Input:gamepadreleased(nil, "x")

-- claimed and valid: consumed, recorded, and release-paired
Capture.validator = function() return true end
Capture.setClaim(Capture.DECK)
Input:gamepadpressed(nil, "dpleft")
T.check(not Input:isDown("left"), "claimed, the engine never sees the press")
local edges = Capture.takeEdges()
T.eq(#edges, 1, "the consumed press lands in the edge buffer")
T.eq(edges[1], "dpleft", "and names its button")
T.check(Capture.isDown("dpleft"), "physical down-state tracks while claimed")
Input:gamepadreleased(nil, "dpleft")
T.check(not Input:isDown("left"), "the paired release is consumed too")

-- claim set but validator says no (bag on top, battle popped, ...): forward
Capture.validator = function() return false end
Input:gamepadpressed(nil, "dpright")
T.check(Input:isDown("right"), "an invalid claim forwards the pad untouched")
Input:gamepadreleased(nil, "dpright")
T.check(not Input:isDown("right"), "including the release")

-- ---- a stood-down stick is left completely alone ----
--
-- The regression this guards: with a camera mod owning the sticks,
-- settle() used to force-centre the engine's stick on every claimed frame,
-- starting the instant a battle opened.  A stood-down stick must forward
-- untouched and receive no injected centring at all.

-- count the injections themselves: settle/setClaim write through the saved
-- original (Capture.innerAxis), not through the patched table field
local injected = 0
local realAxis = Capture.innerAxis
Capture.innerAxis = function(self, joystick, axis, value)
  injected = injected + 1
  return realAxis(self, joystick, axis, value)
end

Capture.sticksAllowed = function() return false end
Capture.validator = function() return true end
Capture.setClaim(Capture.DECK)
injected = 0
Capture.settle()
T.eq(injected, 0, "a stood-down stick gets no injected centring from settle")

Input:reset()
Input:gamepadaxis(nil, "leftx", -1)
T.check(Input:isDown("left"),
  "a stood-down stick still reaches the engine while BattlePad claims buttons")
Input:gamepadaxis(nil, "leftx", 0)
T.check(not Input:isDown("left"), "and releases")
T.eq(select(1, Capture.stick("left")), 0,
  "BattlePad itself reads a stood-down stick as centred")

-- and with the sticks allowed, the claim still centres exactly once
Capture.sticksAllowed = function() return true end
Capture.setClaim(nil)
Capture.setClaim(Capture.DECK)
injected = 0
Capture.settle()
local firstSettle = injected
Capture.settle()
T.check(firstSettle > 0, "an allowed stick is centred when the claim opens")
T.eq(injected, firstSettle, "and is not re-centred every frame")

Capture.innerAxis = realAxis
Capture.sticksAllowed = function() return true end
Capture.setClaim(nil)
Capture.validator = nil
Input:reset()

run.release()
T.finish("battle_pad")
