-- scoreboard.lua — Unified high-score viewer
-- Reads every game's save file under /unigeek/games/ and lists each one's
-- best result on a single screen. Games store scores in different shapes
-- (a bare number, a best time in ms, or a wins/losses JSON record), so each
-- entry below declares how to format its file. Games that haven't been
-- played yet show a dim dash.
--
--   UP/DOWN : scroll the list (when it doesn't all fit)
--   OK      : re-read the files (refresh after playing something)
--   BACK    : exit
--
-- Read-only — this script never writes to the save files.

local lcd  = require("uni.lcd")
local nav  = require("uni.nav")
local sd   = require("uni.sd")
local json = require("uni.json")

local W, H = lcd.w(), lcd.h()

-- ── Colours ───────────────────────────────────────────────
local C_BG      = lcd.color(  8,  10,  26)
local C_HUD_BG  = lcd.color( 22,  22,  38)
local C_HUD_LN  = lcd.color( 60,  60,  90)
local C_TEXT    = lcd.color(220, 220, 240)
local C_DIM     = lcd.color(120, 120, 155)
local C_NONE    = lcd.color( 80,  80, 110)
local C_HI      = lcd.color(255, 200,  60)
local C_ROW     = lcd.color( 16,  18,  40)   -- alternating row tint

local DIR = "/unigeek/games/"

-- Each entry: file under DIR, display name, and how to format the contents.
--   num   = bare number (higher is better)
--   ms    = bare number, a best time in milliseconds
--   tries = bare number, fewest attempts to win
--   wld   = JSON { wins, losses, draws }
--   wl    = JSON { wins, losses }
--   money = JSON { money }
local GAMES = {
  { file = "invader.txt",        name = "Invader",      fmt = "num"   },
  { file = "snake.txt",          name = "Snake",        fmt = "num"   },
  { file = "stacker.txt",        name = "Stacker",      fmt = "num"   },
  { file = "simon.txt",          name = "Simon",        fmt = "num"   },
  { file = "higher-lower.txt",   name = "Higher/Lower", fmt = "num"   },
  { file = "poker.txt",          name = "Poker",        fmt = "num"   },
  { file = "reaction.txt",       name = "Reaction",     fmt = "ms"    },
  { file = "mastermind.txt",     name = "Mastermind",   fmt = "tries" },
  { file = "tic-tac-toe.txt",    name = "Tic-Tac-Toe",  fmt = "wld"   },
  { file = "pong.txt",           name = "Pong",         fmt = "wl"    },
  { file = "fishing-legend.txt", name = "Fishing",      fmt = "money" },
}

-- ── Layout ────────────────────────────────────────────────
local HUD_H    = 12
local HINT_Y   = H - 12
local LIST_TOP = HUD_H + 4
local ROW_H    = 14
local VISIBLE  = math.max(1, math.floor((HINT_Y - LIST_TOP) / ROW_H))

-- ── State ─────────────────────────────────────────────────
local rows       = {}     -- { name, value, played } per game
local offset     = 0      -- index of the first visible row (0-based)
local list_dirty = true

-- ── Loading / formatting ──────────────────────────────────
local function readNumber(path)
  if not sd.exists(path) then return nil end
  return tonumber(sd.read(path) or "")
end

local function readJson(path)
  if not sd.exists(path) then return nil end
  local data = json.decode(sd.read(path) or "")
  if type(data) ~= "table" then return nil end
  return data
end

local function formatEntry(g)
  local path = DIR .. g.file
  if g.fmt == "num" then
    local n = readNumber(path)
    if not n then return nil end
    return string.format("%d", n)
  elseif g.fmt == "ms" then
    local n = readNumber(path)
    if not n then return nil end
    return string.format("%d ms", n)
  elseif g.fmt == "tries" then
    local n = readNumber(path)
    if not n then return nil end
    return string.format("%d %s", n, (n == 1) and "try" or "tries")
  elseif g.fmt == "wld" then
    local d = readJson(path)
    if not d then return nil end
    return string.format("W%d L%d D%d", d.wins or 0, d.losses or 0, d.draws or 0)
  elseif g.fmt == "wl" then
    local d = readJson(path)
    if not d then return nil end
    return string.format("W%d L%d", d.wins or 0, d.losses or 0)
  elseif g.fmt == "money" then
    local d = readJson(path)
    if not d or not d.money then return nil end
    return string.format("$%d", d.money)
  end
  return nil
end

local function loadAll()
  rows = {}
  for i = 1, #GAMES do
    local g = GAMES[i]
    local v = formatEntry(g)
    rows[i] = { name = g.name, value = v or "—", played = (v ~= nil) }
  end
end

-- ── Rendering ─────────────────────────────────────────────
local function drawHUD()
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_HUD_LN)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, "Scoreboard")
end

local function drawHint()
  lcd.rect(0, HINT_Y, W, 10, C_BG)
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  local s = (#GAMES > VISIBLE) and "UP/DOWN scroll   OK refresh   BACK exit"
                                or  "OK refresh   BACK exit"
  lcd.print(math.floor((W - lcd.textWidth(s)) / 2), HINT_Y, s)
end

local function drawList()
  -- clear the whole list region, then paint the visible window
  lcd.rect(0, LIST_TOP, W, HINT_Y - LIST_TOP, C_BG)
  lcd.textSize(1)
  for r = 0, VISIBLE - 1 do
    local idx = offset + r + 1
    local row = rows[idx]
    if row then
      local y = LIST_TOP + r * ROW_H
      if idx % 2 == 0 then lcd.rect(0, y, W, ROW_H, C_ROW) end
      local rbg = (idx % 2 == 0) and C_ROW or C_BG
      lcd.textColor(C_TEXT, rbg)
      lcd.print(4, y + 3, row.name)
      lcd.textColor(row.played and C_HI or C_NONE, rbg)
      lcd.print(W - lcd.textWidth(row.value) - 4, y + 3, row.value)
    end
  end
  -- scroll markers
  if offset > 0 then
    lcd.textColor(C_DIM, C_BG)
    lcd.print(W - 8, LIST_TOP, "^")
  end
  if offset + VISIBLE < #GAMES then
    lcd.textColor(C_DIM, C_BG)
    lcd.print(W - 8, HINT_Y - 9, "v")
  end
  list_dirty = false
end

local function maxOffset()
  return math.max(0, #GAMES - VISIBLE)
end

-- ── Init ──────────────────────────────────────────────────
lcd.fillScreen(C_BG)
drawHUD()
drawHint()
loadAll()

-- ── Main loop ─────────────────────────────────────────────
while true do
  local btn = nav.btn()
  if btn == "back" then break end

  if btn == "up" then
    if offset > 0 then offset = offset - 1; list_dirty = true end
  elseif btn == "down" then
    if offset < maxOffset() then offset = offset + 1; list_dirty = true end
  elseif btn == "ok" then
    loadAll()
    list_dirty = true
  end

  if list_dirty then drawList() end

  uni.delay(33)
end
