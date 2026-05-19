-- hacker-news.lua — Top 10 stories from Hacker News
-- Pulls /topstories.json once to get the ID list, then fetches the
-- first ten items individually. UP / DOWN scroll the cursor through
-- the list (with wrap-around). The footer panel shows the score,
-- comment count, and author for the highlighted story. OK forces a
-- manual refresh; the list also auto-refreshes every 10 minutes.
--
-- WiFi follows the same convention as crypto-price.lua: passwords
-- live in /unigeek/wifi/passwords/<BSSID>_<SSID>.pass. If no stored
-- password is found, the script prompts on the first connect attempt.
--
--   UP / DOWN : move cursor (wrap-around)
--   OK        : refresh / retry on error / start the WiFi prompt
--   BACK      : exit (also dismisses any prompt)

local lcd   = require("uni.lcd")
local nav   = require("uni.nav")
local sd    = require("uni.sd")
local input = require("uni.input")
local wifi  = require("uni.wifi")
local http  = require("uni.http")
local json  = require("uni.json")

local W, H = lcd.w(), lcd.h()

-- ── Colours ───────────────────────────────────────────────
local C_BG      = lcd.color( 24,  18,   8)
local C_HUD_BG  = lcd.color( 44,  28,  16)
local C_TEXT    = lcd.color(230, 220, 210)
local C_DIM     = lcd.color(150, 140, 130)
local C_SEL_BG  = lcd.color( 80,  44,  16)
local C_SEL_FG  = lcd.color(255, 200, 120)
local C_ARROW   = lcd.color(255, 140,  40)
local C_SCORE   = lcd.color(255, 180,  60)
local C_AUTHOR  = lcd.color(140, 200, 255)
local C_GOOD    = lcd.color(120, 220, 130)
local C_BAD     = lcd.color(255, 110, 110)

-- ── Constants ─────────────────────────────────────────────
local URL_TOP      = "https://hacker-news.firebaseio.com/v0/topstories.json"
local URL_ITEM_FMT = "https://hacker-news.firebaseio.com/v0/item/%d.json"
local N_STORIES    = 10
local REFRESH_MS   = 10 * 60 * 1000     -- 10 min auto-refresh
local CONNECT_TMO  = 15000
local PASS_DIR     = "/unigeek/wifi/passwords"

-- ── Layout ────────────────────────────────────────────────
local HUD_H        = 12
local ROW_H        = 12
local STATUS_Y     = H - 24
local HINT_Y       = H - 12
local FOOTER_H     = 22
local FOOTER_Y     = STATUS_Y - 2 - FOOTER_H
local LIST_TOP     = HUD_H + 2
local LIST_BOTTOM  = FOOTER_Y - 2
local VISIBLE_ROWS = math.max(3, math.min(N_STORIES, math.floor((LIST_BOTTOM - LIST_TOP) / ROW_H)))

-- Each row gets "> 10. " as the widest prefix (6 chars), so the title
-- starts at the same x for every row. ~6px per char for the small font.
local TITLE_X     = 4 + 6 * 6
local TITLE_MAXCH = math.max(8, math.floor((W - TITLE_X - 4) / 6))

-- ── State ─────────────────────────────────────────────────
local stories = {}                 -- array of {id, title, url, score, descendants, by}
local cur_idx       = 1
local top_idx       = 1            -- first visible row in the list
local prev_cur_idx  = -1
local prev_top_idx  = -1
local last_fetch_ms = 0
local last_status   = "\0"
local error_active  = false
local last_ssid     = ""

-- ── Helpers (pre-allocated) ───────────────────────────────
local function trimWS(s) return string.match(s, "^%s*(.-)%s*$") end

local function findStoredPassword(ssid)
  if not sd.exists(PASS_DIR) then return nil end
  local entries = sd.list(PASS_DIR)
  if not entries then return nil end
  local suffix = "_" .. ssid .. ".pass"
  for _, e in ipairs(entries) do
    if (not e.isDir) and string.sub(e.name, -#suffix) == suffix then
      local raw = sd.read(PASS_DIR .. "/" .. e.name)
      if raw and raw ~= "" then
        local trimmed = trimWS(raw)
        if trimmed ~= "" then return trimmed end
      end
    end
  end
  return nil
end

local function truncate(s, max_chars)
  if s == nil then return "" end
  if #s <= max_chars then return s end
  if max_chars <= 1 then return string.sub(s, 1, max_chars) end
  return string.sub(s, 1, max_chars - 1) .. "."
end

local function drawHUD()
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_DIM)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, "Hacker News")

  local right, color
  if wifi.status() == "connected" then
    right = wifi.ip()
    if right == "" then right = "wifi up" end
    color = C_GOOD
  else
    right = "no wifi"
    color = C_BAD
  end
  lcd.textColor(color, C_HUD_BG)
  local rw = lcd.textWidth(right)
  lcd.print(W - rw - 2, 2, right)
end

local function rowY(visible_pos)
  return LIST_TOP + (visible_pos - 1) * ROW_H
end

local function drawRow(visible_pos, idx)
  local y = rowY(visible_pos)
  local is_sel = (idx == cur_idx)
  local bg = is_sel and C_SEL_BG or C_BG

  lcd.rect(0, y, W, ROW_H, bg)

  local story = stories[idx]
  lcd.textSize(1)

  if is_sel then
    lcd.textColor(C_ARROW, bg)
    lcd.print(4, y + 2, ">")
  end

  -- Rank ("1." through "10.") — left-padded so titles line up.
  lcd.textColor(is_sel and C_SEL_FG or C_DIM, bg)
  lcd.print(4 + 8, y + 2, string.format("%2d.", idx))

  if story and story.title then
    lcd.textColor(is_sel and C_SEL_FG or C_TEXT, bg)
    lcd.print(TITLE_X, y + 2, truncate(story.title, TITLE_MAXCH))
  else
    lcd.textColor(C_DIM, bg)
    lcd.print(TITLE_X, y + 2, "...")
  end
end

local function drawList()
  for v = 1, VISIBLE_ROWS do
    local idx = top_idx + v - 1
    if idx <= N_STORIES then
      drawRow(v, idx)
    else
      lcd.rect(0, rowY(v), W, ROW_H, C_BG)
    end
  end
  prev_cur_idx = cur_idx
  prev_top_idx = top_idx
end

local function drawFooter()
  lcd.rect(0, FOOTER_Y - 1, W, 1, C_DIM)
  lcd.rect(0, FOOTER_Y, W, FOOTER_H, C_BG)
  local story = stories[cur_idx]
  if not story or not story.score then return end

  lcd.textSize(1)
  local pts = string.format("%d pts", story.score or 0)
  local cmt = string.format("%d cmts", story.descendants or 0)
  local sep = "   "
  local line = pts .. sep .. cmt
  lcd.textColor(C_SCORE, C_BG)
  local lw = lcd.textWidth(line)
  lcd.print(math.floor((W - lw) / 2), FOOTER_Y + 2, line)

  if story.by then
    local by = "by " .. truncate(story.by, math.max(6, math.floor((W - 8) / 6) - 3))
    lcd.textColor(C_AUTHOR, C_BG)
    local bw = lcd.textWidth(by)
    lcd.print(math.floor((W - bw) / 2), FOOTER_Y + 12, by)
  end
end

local function drawStatus(text, color)
  if text == last_status then return end
  lcd.rect(0, STATUS_Y, W, 10, C_BG)
  last_status = text
  if text == "" then return end
  lcd.textSize(1)
  lcd.textColor(color, C_BG)
  local sw = lcd.textWidth(text)
  lcd.print(math.floor((W - sw) / 2), STATUS_Y, text)
end

local function drawHint()
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  local s = "UP/DOWN scroll  OK refresh"
  local sw = lcd.textWidth(s)
  lcd.print(math.floor((W - sw) / 2), HINT_Y, s)
end

local function drawScene()
  lcd.fillScreen(C_BG)
  drawHUD()
  drawList()
  drawFooter()
  last_status = "\0"
  drawHint()
end

-- After a cursor move: redraw only the rows whose selection state
-- changed; or redraw the whole list if the visible window scrolled.
local function refreshList()
  if top_idx ~= prev_top_idx then
    drawList()
  else
    if prev_cur_idx >= top_idx and prev_cur_idx < top_idx + VISIBLE_ROWS then
      drawRow(prev_cur_idx - top_idx + 1, prev_cur_idx)
    end
    if cur_idx >= top_idx and cur_idx < top_idx + VISIBLE_ROWS then
      drawRow(cur_idx - top_idx + 1, cur_idx)
    end
    prev_cur_idx = cur_idx
    prev_top_idx = top_idx
  end
  drawFooter()
end

local function moveCursor(delta)
  cur_idx = cur_idx + delta
  if cur_idx < 1 then cur_idx = N_STORIES end
  if cur_idx > N_STORIES then cur_idx = 1 end
  if cur_idx < top_idx then
    top_idx = cur_idx
  elseif cur_idx >= top_idx + VISIBLE_ROWS then
    top_idx = cur_idx - VISIBLE_ROWS + 1
  end
  refreshList()
end

local function ensureWifi()
  if wifi.status() == "connected" then return true end

  local ssid = input.text("WiFi SSID", last_ssid)
  if ssid == nil or ssid == "" then return false end
  last_ssid = ssid

  local pass = findStoredPassword(ssid)
  if not pass then
    pass = input.text("Password for " .. ssid, "")
    if pass == nil then return false end
  end

  drawScene()
  drawStatus(string.format("connecting to %s...", ssid), C_DIM)

  local ok = wifi.connect(ssid, pass, CONNECT_TMO)
  drawHUD()

  if not ok then
    drawStatus("connect failed", C_BAD)
    return false
  end

  drawStatus("connected", C_GOOD)
  return true
end

local function fetchItem(id)
  local body, code = http.get(string.format(URL_ITEM_FMT, id))
  if (not body) or code ~= 200 then return nil end
  local d = json.decode(body)
  if not d then return nil end
  return {
    id          = d.id,
    title       = d.title or "(untitled)",
    url         = d.url,
    score       = d.score or 0,
    descendants = d.descendants or 0,
    by          = d.by or "?",
  }
end

local function fetchStories()
  if wifi.status() ~= "connected" then return nil, "no wifi" end

  drawStatus("fetching top list...", C_DIM)
  local body, code = http.get(URL_TOP)
  if (not body) or code ~= 200 then
    return nil, string.format("HTTP %s", tostring(code))
  end
  local ids = json.decode(body)
  if type(ids) ~= "table" or ids[1] == nil then
    return nil, "parse error"
  end

  local out = {}
  for i = 1, N_STORIES do
    local id = ids[i]
    if id == nil then break end
    drawStatus(string.format("fetching %d/%d...", i, N_STORIES), C_DIM)
    local item = fetchItem(id)
    if item then
      out[i] = item
    else
      out[i] = { id = id, title = "(fetch failed)", score = 0, descendants = 0, by = "?" }
    end
  end
  return out, nil
end

local function refresh()
  local data, err = fetchStories()
  drawHUD()
  if err then
    error_active = true
    drawStatus("error: " .. err, C_BAD)
    uni.beep(220, 120)
    return
  end
  stories      = data
  error_active = false
  last_fetch_ms = uni.millis()
  if cur_idx > #stories then cur_idx = 1 end
  if top_idx > #stories then top_idx = 1 end
  drawList()
  drawFooter()
  drawStatus("updated", C_GOOD)
  uni.beep(1300, 40)
end

-- ── Init ──────────────────────────────────────────────────
drawScene()

if ensureWifi() then
  refresh()
else
  error_active = true
  drawStatus("press OK to connect wifi", C_BAD)
end

-- ── Main loop ─────────────────────────────────────────────
while true do
  local btn = nav.btn()
  if btn == "back" then break end

  if btn == "up" then
    if #stories > 0 then moveCursor(-1) end
  elseif btn == "down" then
    if #stories > 0 then moveCursor(1) end
  elseif btn == "ok" then
    if wifi.status() ~= "connected" then
      if ensureWifi() then refresh() end
    else
      refresh()
    end
  end

  if (not error_active) and #stories > 0 then
    local elapsed = uni.millis() - last_fetch_ms
    if elapsed >= REFRESH_MS then
      refresh()
    end
  end

  uni.delay(120)
end
