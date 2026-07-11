--[[
@title Crypto Price Tracker
@description Live BTC/USD and ETH/USD prices from the CoinGecko API, refreshed over WiFi.
@category Network
@author lshaf
]]
-- crypto-price.lua — Crypto Price Tracker
-- Fetches BTC/USD and ETH/USD from the CoinGecko public API every
-- 60 s and displays them. If WiFi isn't already up, the script
-- prompts for an SSID and password, then connects.
--
-- Password lookup follows the firmware's WifiUtility convention:
-- passwords live in /unigeek/wifi/passwords/<BSSID>_<SSID>.pass (the
-- format the eapol bruteforce uses to save cracked passwords). On
-- lookup we scan that directory for any file ending in `_<SSID>.pass`,
-- so cracked, firmware-saved, and manually-placed entries all work.
-- We do NOT save passwords back from Lua — `uni.wifi` has no scan, so
-- we can't fill in the BSSID half of the filename and would diverge
-- from the firmware's format. Drop a file there yourself if you want
-- auto-fill.
--
--   OK   : refresh now / retry on error / start the connect prompt
--          when no wifi yet
--   BACK : exit (also dismisses any prompt)

local lcd   = require("uni.lcd")
local nav   = require("uni.nav")
local sd    = require("uni.sd")
local input = require("uni.input")
local wifi  = require("uni.wifi")
local http  = require("uni.http")
local json  = require("uni.json")

local W, H = lcd.w(), lcd.h()

-- ── Colours ───────────────────────────────────────────────
local C_BG     = lcd.color(  8,  10,  30)
local C_HUD_BG = lcd.color( 22,  22,  38)
local C_TEXT   = lcd.color(220, 220, 240)
local C_DIM    = lcd.color(140, 140, 180)
local C_BTC    = lcd.color(255, 170,  60)
local C_ETH    = lcd.color(140, 180, 255)
local C_GOOD   = lcd.color(120, 220, 130)
local C_BAD    = lcd.color(255, 110, 110)

-- ── Constants ─────────────────────────────────────────────
local URL = "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum&vs_currencies=usd"
local REFRESH_MS  = 60 * 1000
local CONNECT_TMO = 15000

local PASS_DIR = "/unigeek/wifi/passwords"

-- ── Layout ────────────────────────────────────────────────
local HUD_H        = 12
local PRICE_SIZE   = (W >= 240) and 3 or 2
local PRICE_BAND_H = PRICE_SIZE * 8

local BTC_LABEL_Y = HUD_H + 8
local BTC_PRICE_Y = BTC_LABEL_Y + 12
local ETH_LABEL_Y = BTC_PRICE_Y + PRICE_BAND_H + 8
local ETH_PRICE_Y = ETH_LABEL_Y + 12
local STATUS_Y    = H - 24
local HINT_Y      = H - 12

-- ── State ─────────────────────────────────────────────────
local btc_price       = nil
local eth_price       = nil
local last_fetch_ms   = 0
local last_status     = "\0"
local last_remaining  = -1
local error_active    = false
local last_ssid       = ""      -- remembered for the next prompt within this session

-- ── Helpers (pre-allocated) ───────────────────────────────
local function trimWS(s)
  return string.match(s, "^%s*(.-)%s*$")
end

local function withCommas(n)
  local s    = tostring(n)
  local sign = ""
  if string.sub(s, 1, 1) == "-" then
    sign = "-"
    s    = string.sub(s, 2)
  end
  local result = ""
  local count  = 0
  for i = #s, 1, -1 do
    if count > 0 and count % 3 == 0 then result = "," .. result end
    result = string.sub(s, i, i) .. result
    count  = count + 1
  end
  return sign .. result
end

local function fmtPrice(p)
  if p == nil then return "---" end
  if p >= 1 then
    local int_part = math.floor(p)
    local frac     = math.floor((p - int_part) * 100 + 0.5)
    return "$" .. withCommas(int_part) .. string.format(".%02d", frac)
  end
  return string.format("$%.4f", p)
end

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

local function drawHUD()
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_DIM)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, "Crypto")

  local right_label, right_color
  if wifi.status() == "connected" then
    right_label = wifi.ip()
    if right_label == "" then right_label = "wifi up" end
    right_color = C_GOOD
  else
    right_label = "no wifi"
    right_color = C_BAD
  end
  lcd.textColor(right_color, C_HUD_BG)
  local rw = lcd.textWidth(right_label)
  lcd.print(W - rw - 2, 2, right_label)
end

local function drawLabel(y, text, color)
  lcd.textSize(1)
  lcd.textColor(color, C_BG)
  lcd.print(4, y, text)
end

local function drawPrice(y, price, color)
  lcd.rect(0, y, W, PRICE_BAND_H, C_BG)
  lcd.textSize(PRICE_SIZE)
  lcd.textColor(color, C_BG)
  local s = fmtPrice(price)
  local sw = lcd.textWidth(s)
  lcd.print(math.floor((W - sw) / 2), y, s)
  lcd.textSize(1)
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
  local s = "OK refresh    BACK exit"
  local sw = lcd.textWidth(s)
  lcd.print(math.floor((W - sw) / 2), HINT_Y, s)
end

local function drawPrices()
  drawPrice(BTC_PRICE_Y, btc_price, C_BTC)
  drawPrice(ETH_PRICE_Y, eth_price, C_ETH)
end

local function drawScene()
  lcd.fillScreen(C_BG)
  drawHUD()
  drawLabel(BTC_LABEL_Y, "BTC / USD", C_BTC)
  drawPrice(BTC_PRICE_Y, btc_price, C_BTC)
  drawLabel(ETH_LABEL_Y, "ETH / USD", C_ETH)
  drawPrice(ETH_PRICE_Y, eth_price, C_ETH)
  last_status = "\0"
  drawHint()
end

-- Returns true if WiFi is up after this call. Prompts when needed.
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

  -- Repaint behind the popups, then show "connecting..." before the blocking call.
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

local function fetchPrices()
  if wifi.status() ~= "connected" then return nil, "no wifi" end
  local body, code = http.get(URL)
  if code ~= 200 then return nil, string.format("HTTP %d", code) end
  local data = json.decode(body)
  if (not data) or (not data.bitcoin) or (not data.ethereum)
     or (not data.bitcoin.usd) or (not data.ethereum.usd) then
    return nil, "parse error"
  end
  return { BTC = data.bitcoin.usd, ETH = data.ethereum.usd }, nil
end

local function refresh()
  drawStatus("fetching...", C_DIM)
  local prices, err = fetchPrices()
  drawHUD()
  if err then
    btc_price    = nil
    eth_price    = nil
    error_active = true
    drawPrices()
    drawStatus("error: " .. err, C_BAD)
    uni.beep(220, 120)
    return
  end
  btc_price      = prices.BTC
  eth_price      = prices.ETH
  last_fetch_ms  = uni.millis()
  error_active   = false
  last_remaining = -1
  drawPrices()
  drawStatus("updated", C_GOOD)
  uni.beep(1300, 40)
end

-- ── Init ──────────────────────────────────────────────────
drawScene()

if ensureWifi() then
  refresh()
else
  error_active = true
  if last_status == "\0" then
    drawStatus("press OK to connect wifi", C_BAD)
  end
end

-- ── Main loop ─────────────────────────────────────────────
while true do
  local btn = nav.btn()
  if btn == "back" then break end

  if btn == "ok" then
    if wifi.status() ~= "connected" then
      if ensureWifi() then
        refresh()
      end
    else
      refresh()
    end
  end

  if (not error_active) and btc_price ~= nil then
    local elapsed = uni.millis() - last_fetch_ms
    if elapsed >= REFRESH_MS then
      refresh()
    else
      local remaining = math.floor((REFRESH_MS - elapsed) / 1000)
      if remaining ~= last_remaining then
        drawStatus(string.format("refresh in %ds", remaining), C_DIM)
        last_remaining = remaining
      end
    end
  end

  uni.delay(200)
end
