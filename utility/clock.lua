-- clock.lua — Clock
-- Big HH:MM:SS in the centre with date + weekday underneath. Reads
-- the device RTC via uni.time. If the RTC hasn't been synced (no NTP
-- since boot) it will read 1970-01-01 — a warning shows in that case.
--
--   BACK : exit

local lcd  = require("uni.lcd")
local nav  = require("uni.nav")
local time = require("uni.time")

local W, H = lcd.w(), lcd.h()

-- ── Colours ───────────────────────────────────────────────
local C_BG    = lcd.color(  8,  10,  30)
local C_TEXT  = lcd.color(220, 220, 240)
local C_DIM   = lcd.color(140, 140, 180)
local C_TIME  = lcd.color(120, 230, 255)
local C_DATE  = lcd.color(220, 220, 240)
local C_WDAY  = lcd.color(255, 200,  60)
local C_WARN  = lcd.color(255, 130, 130)

local DAYS   = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

-- Pick the biggest font where "HH:MM:SS" (8 chars × 6 px at size 1) fits.
local TIME_SIZE
if     W >= 240 then TIME_SIZE = 5
elseif W >= 192 then TIME_SIZE = 4
elseif W >= 144 then TIME_SIZE = 3
else                 TIME_SIZE = 2
end

local TIME_Y = math.floor(H * 0.30)
local TIME_H = TIME_SIZE * 8
local DATE_Y = TIME_Y + TIME_H + 12
local WDAY_Y = DATE_Y + 16
local WARN_Y = H - 26
local HINT_Y = H - 12

-- ── State (for diff render) ───────────────────────────────
local last_time = ""
local last_date = ""
local last_wday = ""
local last_warn = false

local function drawTime(s)
  lcd.textSize(TIME_SIZE)
  lcd.textColor(C_TIME, C_BG)
  local sw = lcd.textWidth(s)
  lcd.print(math.floor((W - sw) / 2), TIME_Y, s)
  lcd.textSize(1)
end

local function drawDate(s)
  lcd.rect(0, DATE_Y, W, 10, C_BG)
  lcd.textSize(1)
  lcd.textColor(C_DATE, C_BG)
  local sw = lcd.textWidth(s)
  lcd.print(math.floor((W - sw) / 2), DATE_Y, s)
end

local function drawWeekday(s)
  lcd.rect(0, WDAY_Y, W, 10, C_BG)
  lcd.textSize(1)
  lcd.textColor(C_WDAY, C_BG)
  local sw = lcd.textWidth(s)
  lcd.print(math.floor((W - sw) / 2), WDAY_Y, s)
end

local function drawWarn(show)
  lcd.rect(0, WARN_Y, W, 10, C_BG)
  if not show then return end
  lcd.textSize(1)
  lcd.textColor(C_WARN, C_BG)
  local s = "RTC not synced (no NTP since boot)"
  if lcd.textWidth(s) > W then s = "RTC not synced" end
  local sw = lcd.textWidth(s)
  lcd.print(math.floor((W - sw) / 2), WARN_Y, s)
end

local function drawHint()
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  local s = "BACK to exit"
  local sw = lcd.textWidth(s)
  lcd.print(math.floor((W - sw) / 2), HINT_Y, s)
end

local function drawTitle()
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  lcd.print(2, 2, "Clock")
end

-- ── Init ──────────────────────────────────────────────────
lcd.fillScreen(C_BG)
drawTitle()
drawHint()

-- ── Main loop ─────────────────────────────────────────────
while true do
  if nav.btn() == "back" then break end

  local t = time.now()
  local time_str = string.format("%02d:%02d:%02d", t.hour, t.min, t.sec)
  local date_str = string.format("%d %s %d", t.day, MONTHS[t.month] or "?", t.year)
  local wday_str = DAYS[t.wday + 1] or "?"
  local warn     = (t.year < 2000)

  if time_str ~= last_time then
    drawTime(time_str)
    last_time = time_str
  end
  if date_str ~= last_date then
    drawDate(date_str)
    last_date = date_str
  end
  if wday_str ~= last_wday then
    drawWeekday(wday_str)
    last_wday = wday_str
  end
  if warn ~= last_warn then
    drawWarn(warn)
    last_warn = warn
  end

  uni.delay(200)
end
