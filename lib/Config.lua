-- BattlePad configuration: one schema drives three surfaces -- the mod
-- manager (mod.options:define), the in-game OPTIONS menu (ui.options.rows),
-- and every runtime read.  Values live in the engine's own persisted options
-- bucket (game.save.options.modOptions.battle_pad), the exact table the
-- launcher's mod manager reads and writes, so both UIs edit the same fact.

local Config = {}

Config.MOD_ID = "battle_pad"

Config.schema = {
  { key = "enabled", label = "BATTLEPAD", type = "toggle", default = true },
  -- QUICK MOVES ON: one d-pad tap (or a full stick flick) fires the move.
  -- OFF: the first tap highlights and shows PP/type, the second commits.
  { key = "quick_moves", label = "QUICK MOVES", type = "toggle", default = false },
  -- QUEUE NEXT: pre-select the next action while the foe is still acting.
  { key = "queueing", label = "QUEUE NEXT", type = "toggle", default = true },
  -- STICKS: AUTO stands the radial sticks down while a Dramatic Shape
  -- family mod is active (its staged camera flies on them); ON keeps
  -- BattlePad's radial selection and overrides the voxel camera; OFF
  -- leaves the sticks alone everywhere.
  { key = "sticks", label = "STICKS", type = "choice",
    choices = {
      { "AUTO", "auto" },
      { "ON", "on" },
      { "OFF", "off" },
    }, default = "auto" },
  -- RUN HOLD: how long B is held before RUN commits.
  { key = "run_hold", label = "RUN HOLD", type = "choice",
    choices = {
      { "1S", 1 },
      { "3S", 3 },
      { "5S", 5 },
      { "7S", 7 },
      { "10S", 10 },
    }, default = 3 },
  -- 3D BATTLES: what happens inside a Dramatic Shape family staged battle.
  -- CLASSIC hands those battles wholly to the voxel mod's own presentation;
  -- BATTLEPAD keeps this mod's deck active there too.
  { key = "voxel_battles", label = "3D BATTLES", type = "choice",
    choices = {
      { "BATTLEPAD", "on" },
      { "CLASSIC", "classic" },
    }, default = "on" },
  -- DEBUG LOG: writes battle_pad_log.txt into the save directory (next to
  -- the engine's lua-error.log) so a misbehaving session can be sent over.
  { key = "debug_log", label = "DEBUG LOG", type = "toggle", default = false },
  { key = "icons", label = "PAD ICONS", type = "choice",
    choices = {
      { "AUTO", "auto" },
      { "XBOX", "xbox" },
      { "PS", "ps" },
      { "NIN", "nin" },
    }, default = "auto" },
}

-- The persisted per-mod bucket inside the engine's options table.  Absent
-- pieces are created on demand; a stub game (tests) simply yields nil and
-- every read falls back to the schema default.
function Config.bucket(game)
  local opts = game and game.save and game.save.options
  if type(opts) ~= "table" then return nil end
  opts.modOptions = opts.modOptions or {}
  opts.modOptions[Config.MOD_ID] = opts.modOptions[Config.MOD_ID] or {}
  return opts.modOptions[Config.MOD_ID]
end

function Config.default(key)
  for _, row in ipairs(Config.schema) do
    if row.key == key then return row.default end
  end
  return nil
end

function Config.get(game, key)
  local bucket = Config.bucket(game)
  if bucket ~= nil and bucket[key] ~= nil then return bucket[key] end
  return Config.default(key)
end

function Config.set(game, key, value)
  local bucket = Config.bucket(game)
  if bucket then bucket[key] = value end
end

-- Rows for the in-game OPTIONS menu (ui.options.rows shape: id / label /
-- value() -> display string / step(game, dir) -> true).  Cycling a choice
-- walks its list in either direction; a toggle flips.
function Config.optionRows(game)
  local rows = {}
  for _, def in ipairs(Config.schema) do
    rows[#rows + 1] = {
      id = Config.MOD_ID .. ":" .. def.key,
      label = def.label,
      value = function()
        local v = Config.get(game, def.key)
        if def.type == "toggle" then return v and "ON" or "OFF" end
        for _, c in ipairs(def.choices) do
          if c[2] == v then return c[1] end
        end
        return tostring(v)
      end,
      step = function(g, dir)
        g = g or game
        local v = Config.get(g, def.key)
        if def.type == "toggle" then
          Config.set(g, def.key, not v)
        else
          local idx = 1
          for i, c in ipairs(def.choices) do
            if c[2] == v then idx = i end
          end
          local n = #def.choices
          idx = ((idx - 1 + (dir or 1)) % n) + 1
          Config.set(g, def.key, def.choices[idx][2])
        end
        return true
      end,
    }
  end
  return rows
end

return Config
