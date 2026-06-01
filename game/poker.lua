-- poker.lua — Video Poker (Jacks or Better, 5-card draw)
-- A 5-credit bet is taken each deal. Hold the cards you want, draw new ones
-- for the rest, and you're paid for the resulting hand. Payouts (per bet):
-- Royal Flush 250x, Straight Flush 50x, Four 25x, Full House 9x, Flush 6x,
-- Straight 4x, Three 3x, Two Pair 2x, a pair of Jacks-or-better 1x. Your
-- bankroll persists; if you bust, a fresh 100-credit stake is granted.
--
--   UP/DOWN : move the selector (5 cards, then the DEAL/DRAW button)
--   OK      : toggle HOLD on a card / press DRAW / press DEAL for a new hand
--   BACK    : exit (bankroll is saved)
--
-- Bankroll persists to /unigeek/games/poker.txt.

local lcd = require("uni.lcd")
local nav = require("uni.nav")
local sd  = require("uni.sd")

local W, H = lcd.w(), lcd.h()

local C_BG       = lcd.color(  6,  20,  16)
local C_HUD_BG   = lcd.color( 18,  34,  28)
local C_TEXT     = lcd.color(220, 235, 225)
local C_DIM      = lcd.color(130, 160, 145)
local C_HI       = lcd.color(255, 210,  70)
local C_GOOD     = lcd.color(110, 230, 140)
local C_CARD     = lcd.color(245, 245, 250)
local C_CARD_RED = lcd.color(210,  40,  40)
local C_CARD_BLK = lcd.color( 20,  20,  32)
local C_HOLD     = lcd.color( 90, 220, 130)
local C_CURSOR   = lcd.color(255, 210,  70)
local C_BTN      = lcd.color( 40,  70,  58)
local C_BTN_SEL  = lcd.color(255, 210,  70)

local SAVE_PATH = "/unigeek/games/poker.txt"
local START = 100
local BET   = 5

-- ── Layout ────────────────────────────────────────────────
local HUD_H    = 12
local GAP      = 4
local CARD_W   = math.max(20, math.floor((W - GAP * 6) / 5))
local CARD_H   = math.min(math.floor(CARD_W * 1.5), H - HUD_H - 64)
local CARDS_X0 = math.floor((W - (CARD_W * 5 + GAP * 4)) / 2)
local CARDS_Y  = HUD_H + 16
local RANK_SZ  = (CARD_W >= 34) and 2 or 1
local ACT_W    = math.min(W - 20, 110)
local ACT_H    = 18
local ACT_X    = math.floor((W - ACT_W) / 2)
local ACT_Y    = CARDS_Y + CARD_H + 12
local MSG_Y    = ACT_Y + ACT_H + 6
local HINT_Y   = H - 12

-- ── State ─────────────────────────────────────────────────
local credits
local deck, deck_top
local hand   = {}            -- hand[i] = { rank = 2..14, suit = 1..4 }
local hold   = { false, false, false, false, false }
local cursor = 1             -- 1..5 cards, 6 = action button
local phase  = "hold"        -- "hold" | "result"
local msg, msg_color, restake_note

math.randomseed(uni.millis())

local SUIT_CH = { "S", "H", "D", "C" }   -- spade heart diamond club

-- ── Save / load ───────────────────────────────────────────
local function loadCredits()
  if not sd.exists(SAVE_PATH) then return START end
  return tonumber(sd.read(SAVE_PATH) or "") or START
end

local function saveCredits()
  if not sd.exists("/unigeek/games") then sd.mkdir("/unigeek/games") end
  sd.write(SAVE_PATH, tostring(credits))
end

-- ── Deck ──────────────────────────────────────────────────
local function buildDeck()
  deck = {}
  for s = 1, 4 do
    for r = 2, 14 do deck[#deck + 1] = { rank = r, suit = s } end
  end
  for i = #deck, 2, -1 do
    local j = math.random(i)
    deck[i], deck[j] = deck[j], deck[i]
  end
  deck_top = 1
end

local function draw()
  local c = deck[deck_top]
  deck_top = deck_top + 1
  return c
end

-- ── Hand evaluation ───────────────────────────────────────
local function evaluate(h)
  local cnt, suits, ranks = {}, {}, {}
  for i = 1, 5 do
    cnt[h[i].rank]  = (cnt[h[i].rank] or 0) + 1
    suits[h[i].suit] = (suits[h[i].suit] or 0) + 1
    ranks[i] = h[i].rank
  end
  table.sort(ranks)

  local flush = false
  for _, c in pairs(suits) do if c == 5 then flush = true end end

  local distinct = true
  for i = 2, 5 do if ranks[i] == ranks[i - 1] then distinct = false end end
  local straight = false
  if distinct then
    if ranks[5] - ranks[1] == 4 then straight = true
    elseif ranks[1] == 2 and ranks[2] == 3 and ranks[3] == 4
       and ranks[4] == 5 and ranks[5] == 14 then straight = true end  -- wheel
  end

  local fours, threes, npairs, pairHigh = 0, 0, 0, 0
  for r, c in pairs(cnt) do
    if c == 4 then fours = fours + 1 end
    if c == 3 then threes = threes + 1 end
    if c == 2 then npairs = npairs + 1; if r > pairHigh then pairHigh = r end end
  end

  if straight and flush and ranks[1] == 10 then return "Royal Flush", 250 end
  if straight and flush then return "Straight Flush", 50 end
  if fours == 1 then return "Four of a Kind", 25 end
  if threes == 1 and npairs == 1 then return "Full House", 9 end
  if flush then return "Flush", 6 end
  if straight then return "Straight", 4 end
  if threes == 1 then return "Three of a Kind", 3 end
  if npairs == 2 then return "Two Pair", 2 end
  if npairs == 1 and pairHigh >= 11 then return "Jacks or Better", 1 end
  return "No Win", 0
end

-- ── Card labels ───────────────────────────────────────────
local function rankLabel(r)
  if r == 11 then return "J" end
  if r == 12 then return "Q" end
  if r == 13 then return "K" end
  if r == 14 then return "A" end
  return tostring(r)
end

-- ── Rendering ─────────────────────────────────────────────
local function cardX(i) return CARDS_X0 + (i - 1) * (CARD_W + GAP) end

local function drawCard(i)
  local x = cardX(i)
  -- clear the card + marker strip above it
  lcd.rect(x - 1, CARDS_Y - 10, CARD_W + 2, CARD_H + 24, C_BG)

  lcd.fillRoundRect(x, CARDS_Y, CARD_W, CARD_H, 4, C_CARD)
  local c   = hand[i]
  local fg  = (c.suit == 2 or c.suit == 3) and C_CARD_RED or C_CARD_BLK
  local lbl = rankLabel(c.rank)

  lcd.textSize(RANK_SZ)
  lcd.textColor(fg, C_CARD)
  local bw, bh = lcd.textWidth(lbl), RANK_SZ * 8
  lcd.print(x + math.floor((CARD_W - bw) / 2),
            CARDS_Y + math.floor((CARD_H - bh) / 2) - 4, lbl)
  lcd.textSize(1)
  local su = SUIT_CH[c.suit]
  lcd.print(x + math.floor((CARD_W - lcd.textWidth(su)) / 2),
            CARDS_Y + CARD_H - 12, su)
  lcd.print(x + 3, CARDS_Y + 3, lbl)

  -- hold border
  if hold[i] then
    lcd.rect(x, CARDS_Y, CARD_W, 2, C_HOLD)
    lcd.rect(x, CARDS_Y + CARD_H - 2, CARD_W, 2, C_HOLD)
    lcd.rect(x, CARDS_Y, 2, CARD_H, C_HOLD)
    lcd.rect(x + CARD_W - 2, CARDS_Y, 2, CARD_H, C_HOLD)
  end
  -- cursor marker above the card
  if cursor == i then
    local ax = x + math.floor(CARD_W / 2)
    lcd.rect(ax - 1, CARDS_Y - 9, 2, 6, C_CURSOR)
    lcd.rect(ax - 3, CARDS_Y - 5, 6, 2, C_CURSOR)
  end
end

local function drawAction()
  lcd.rect(ACT_X - 2, ACT_Y - 2, ACT_W + 4, ACT_H + 4, C_BG)
  local sel = (cursor == 6)
  lcd.fillRoundRect(ACT_X, ACT_Y, ACT_W, ACT_H, 4, sel and C_BTN_SEL or C_BTN)
  local label = (phase == "hold") and "DRAW" or ("DEAL  -" .. BET)
  lcd.textSize(1)
  lcd.textColor(sel and C_CARD_BLK or C_TEXT, sel and C_BTN_SEL or C_BTN)
  lcd.print(ACT_X + math.floor((ACT_W - lcd.textWidth(label)) / 2),
            ACT_Y + math.floor((ACT_H - 8) / 2), label)
end

local function drawHUD()
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_DIM)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, "Poker")
  lcd.textColor(C_HI, C_HUD_BG)
  local s = string.format("CR %d", credits)
  lcd.print(W - lcd.textWidth(s) - 2, 2, s)
end

local function drawMsg()
  lcd.rect(0, MSG_Y, W, H - MSG_Y - 12, C_BG)
  lcd.textSize(1)
  if msg then
    lcd.textColor(msg_color, C_BG)
    lcd.print(math.floor((W - lcd.textWidth(msg)) / 2), MSG_Y, msg)
  end
  if restake_note then
    lcd.textColor(C_DIM, C_BG)
    lcd.print(math.floor((W - lcd.textWidth(restake_note)) / 2), MSG_Y + 11, restake_note)
  end
end

local function drawHint()
  local text = "UP/DOWN move   OK hold/deal   BACK exit"
  lcd.rect(0, HINT_Y, W, 12, C_BG)
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  if lcd.textWidth(text) > W then text = "UP/DN move  OK hold/deal" end
  lcd.print(math.floor((W - lcd.textWidth(text)) / 2), HINT_Y, text)
end

local function drawAll()
  lcd.fillScreen(C_BG)
  drawHUD()
  for i = 1, 5 do drawCard(i) end
  drawAction()
  drawMsg()
  drawHint()
end

-- ── Game flow ─────────────────────────────────────────────
local function startHand()
  restake_note = nil
  if credits < BET then
    credits = START
    restake_note = "Busted - new stake of " .. START
  end
  credits = credits - BET
  saveCredits()
  buildDeck()
  for i = 1, 5 do hand[i] = draw(); hold[i] = false end
  cursor = 1
  phase  = "hold"
  msg, msg_color = "Hold cards, then DRAW", C_DIM
end

local function doDraw()
  for i = 1, 5 do
    if not hold[i] then hand[i] = draw() end
  end
  local name, mult = evaluate(hand)
  local pay = mult * BET
  credits = credits + pay
  saveCredits()
  phase  = "result"
  cursor = 6
  if pay > 0 then
    msg, msg_color = string.format("%s  +%d", name, pay), C_GOOD
    uni.beep(700 + math.min(mult, 40) * 20, 80)
  else
    msg, msg_color = name, C_DIM
    uni.beep(180, 120)
  end
end

-- ── Init ──────────────────────────────────────────────────
credits = loadCredits()
startHand()
drawAll()

-- ── Main loop ─────────────────────────────────────────────
while true do
  local btn = nav.btn()
  if btn == "back" then saveCredits(); break end

  if phase == "hold" then
    if btn == "up" or btn == "down" then
      local prev = cursor
      local d = (btn == "down") and 1 or -1
      cursor = ((cursor - 1 + d) % 6) + 1
      if prev <= 5 then drawCard(prev) else drawAction() end
      if cursor <= 5 then drawCard(cursor) else drawAction() end
    elseif btn == "ok" then
      if cursor <= 5 then
        hold[cursor] = not hold[cursor]
        drawCard(cursor)
        uni.beep(900, 12)
      else
        doDraw()
        for i = 1, 5 do drawCard(i) end
        drawAction()
        drawHUD()
        drawMsg()
      end
    end
  else
    -- result: only DEAL matters
    if btn == "ok" then
      startHand()
      drawAll()
    end
  end

  uni.delay(33)
end
