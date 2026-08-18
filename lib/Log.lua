-- Opt-in debug log: the DEBUG LOG row in OPTIONS turns on a plain-text
-- trail at battle_pad_log.txt in the save directory (the same folder that
-- carries the engine's own lua-error.log crash trace), so a misbehaving
-- session can be handed over as two small files.
--
-- Everything here is pcall-wrapped and OFF by default: with the row off,
-- every call is one boolean read.

local V = ...
local Config = V.require("Config")

local Log = { game = nil }

local FILE = "battle_pad_log.txt"

function Log.on()
  local g = Log.game
  return g ~= nil and Config.get(g, "debug_log") == true
end

local function stamp()
  local ok, s = pcall(function() return os.date("%H:%M:%S") end)
  return ok and s or "--:--:--"
end

function Log.line(fmt, ...)
  if not Log.on() then return end
  local n = select("#", ...)
  local args = { ... }
  local ok, err = pcall(function()
    local msg = n > 0 and string.format(fmt, (unpack or table.unpack)(args)) or fmt
    local wrote, werr = love.filesystem.append(FILE, ("[%s] %s\n"):format(stamp(), msg))
    if wrote == false then error(tostring(werr), 0) end
  end)
  if not ok then Log.lastError = tostring(err) end
end

-- Session header: everything worth knowing before the first symptom.
function Log.session(game, modVersion)
  Log.game = game
  if not Log.on() then return end
  pcall(function()
    local Version = require("src.core.Version")
    local GameVersion = require("src.core.GameVersion")
    local Capture = V.require("Capture")
    local pad = "no gamepad seen"
    if Capture.joystick then
      local okN, name = pcall(Capture.joystick.getName, Capture.joystick)
      local okG, guid = pcall(Capture.joystick.getGUID, Capture.joystick)
      pad = ("%s (%s)"):format(okN and tostring(name) or "?",
                               okG and tostring(guid) or "?")
    end
    local mods = {}
    local st = game.modStatus or {}
    for _, m in ipairs(st.available or {}) do
      if m.state == "loaded" then
        mods[#mods + 1] = tostring(m.id) .. " v" .. tostring(m.version)
      end
    end
    love.filesystem.append(FILE, ("\n==== BattlePad %s session %s\n" ..
      "engine %s | game %s (gen %d) | pad: %s\nmods: %s\n"):format(
      tostring(modVersion),
      os.date("%Y-%m-%d %H:%M:%S"),
      tostring(Version.engine), tostring(GameVersion.current),
      GameVersion.generation and GameVersion.generation(GameVersion.current) or 1,
      pad, table.concat(mods, ", ")))
  end)
end

-- ---- crash capture ----
--
-- Android keeps Android/data unreadable, so the crash trace has to reach
-- the player on screen instead of as a file: wrap love.errorhandler to
-- persist the message + live stack, and on the next boot (DEBUG LOG on)
-- the Skin shows it as a panel to screenshot.

local CRASH = "battle_pad_crash.txt"

function Log.installCrashCapture()
  pcall(function()
    local prev = love.errorhandler
    love.errorhandler = function(msg)
      pcall(function()
        love.filesystem.write(CRASH,
          os.date("%Y-%m-%d %H:%M:%S") .. "\n" .. tostring(msg) .. "\n"
          .. debug.traceback("", 2) .. "\n")
      end)
      if prev then return prev(msg) end
    end
  end)
end

-- The last crash's text, or nil.  Read once per boot.
function Log.crashReport()
  if Log._crash == nil then
    local ok, data = pcall(love.filesystem.read, CRASH)
    Log._crash = (ok and type(data) == "string" and #data > 0) and data or false
  end
  return Log._crash or nil
end

return Log
