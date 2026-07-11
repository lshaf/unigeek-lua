--[[
@title Stacker
@description Time your taps to stack the sliding blocks as high as you can without missing.
@category Game
@author lshaf
]]
-- stacker.lua — Block Stacker
-- A coloured block slides left and right along the top of the screen.
-- Press OK to drop it on the stack below — any overhang past the
-- previous block is trimmed off, so the tower narrows over time.
--
-- Endless climb: when the tower reaches the ceiling the whole stack
-- scrolls down one block to make room, so you keep stacking the same
-- width forever — no wipe, no reset. Each scroll counts as a level: the
-- slider starts faster and the in-level speed cap lifts a notch, so timing
-- gets tighter the higher you climb. The run ends only when a drop misses.
--
--   OK   : drop the moving block
--   BACK : exit (also dismisses Game Over)
--
-- High score persists to /unigeek/games/stacker.txt.

local lcd = require("uni.lcd")
local nav = require("uni.nav")
local sd  = require("uni.sd")

local W, H = lcd.w(), lcd.h()

-- ── Colours ───────────────────────────────────────────────
local C_BG       = lcd.color(  8,   8,  24)
local C_HUD_BG   = lcd.color( 22,  22,  38)
local C_HUD_LINE = lcd.color( 60,  60,  90)
local C_TEXT     = lcd.color(220, 220, 240)
local C_DIM      = lcd.color(140, 140, 180)
local C_HI       = lcd.color(255, 200,  60)
local C_BAD      = lcd.color(255, 110, 110)
local C_GOOD     = lcd.color( 80, 220, 120)
local C_PLATFORM = lcd.color( 90, 220, 130)

local PALETTE = {
  lcd.color(120, 200, 255),
  lcd.color(255, 120, 200),
  lcd.color(220, 200,  80),
  lcd.color(160, 240, 120),
  lcd.color(200, 120, 255),
  lcd.color(255, 180,  60),
}

-- ── Layout ────────────────────────────────────────────────
local HUD_H    = 12
local PLAY_TOP = HUD_H + 1
local PLAY_BOT = H - 2

-- ── Dimensions ────────────────────────────────────────────
local BLOCK_H         = 8
local INIT_WIDTH      = math.min(80, math.floor(W * 0.36))
local SLIDE_SPEED_0   = 3
local SLIDE_SPEED_MAX = 7
local FALL_SPEED      = 5
local SAVE_PATH       = "/unigeek/games/stacker.txt"

-- ── State (declared once) ─────────────────────────────────
local score, highScore
local game_state                                  -- "sliding" | "dropping" | "over"
local level, level_score
local cur_x, cur_y, cur_width, cur_dir, prev_cx
local top_x, top_y, top_width
local slide_speed
local color_idx
local popup_drawn
local last_score_shown
local stack                                       -- landed blocks: { {x, w, y, ci}, ... }

-- ── Helpers (pre-allocated) ───────────────────────────────
local function rowColor()
  return PALETTE[((color_idx - 1) % #PALETTE) + 1]
end

-- ci == 0 is the original platform; anything else cycles the palette.
local function colorForCi(ci)
  if ci == 0 then return C_PLATFORM end
  return PALETTE[((ci - 1) % #PALETTE) + 1]
end

-- Difficulty curves indexed by `level` (starts at 1).
local function levelSlideBase()
  return math.min(6, SLIDE_SPEED_0 + (level - 1))
end

local function levelSlideMax()
  return math.min(10, SLIDE_SPEED_MAX + math.floor((level - 1) / 2))
end

local function loadHigh()
  if not sd.exists(SAVE_PATH) then return 0 end
  return tonumber(sd.read(SAVE_PATH) or "") or 0
end

local function saveHigh(n)
  if not sd.exists("/unigeek/games") then sd.mkdir("/unigeek/games") end
  sd.write(SAVE_PATH, tostring(n))
end

local function drawHUD()
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  local sStr = string.format("SCORE %-5d", score)
  lcd.print(2, 2, sStr)

  -- Level is shown between SCORE and HI. Fixed widths (%-5d / %2d / %-4d)
  -- mean each field's pixel width is stable, so textColor bg overdraws
  -- the previous render without leaving residue.
  local lvStr = string.format("LV %2d", level)
  lcd.textColor(C_GOOD, C_HUD_BG)
  lcd.print(2 + lcd.textWidth(sStr) + 6, 2, lvStr)

  local hiStr = string.format("HI %-4d", highScore)
  lcd.textColor(C_HI, C_HUD_BG)
  local hw = lcd.textWidth(hiStr)
  lcd.print(W - hw - 2, 2, hiStr)
end

local function drawSceneBackground()
  lcd.fillScreen(C_BG)
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_HUD_LINE)
end

local function drawBlock(x, y, w, color)
  lcd.rect(x, y, w, BLOCK_H, color)
end

local function drawPopup()
  local boxW = math.min(W - 16, 200)
  local boxH = 86
  local bx = math.floor((W - boxW) / 2)
  local by = math.floor((H - boxH) / 2)
  lcd.rect(bx, by, boxW, boxH, C_HUD_BG)
  lcd.rect(bx, by, boxW, 1, C_DIM)
  lcd.rect(bx, by + boxH - 1, boxW, 1, C_DIM)
  lcd.rect(bx, by, 1, boxH, C_DIM)
  lcd.rect(bx + boxW - 1, by, 1, boxH, C_DIM)

  lcd.textSize(2)
  local title = "MISSED!"
  lcd.textColor(C_BAD, C_HUD_BG)
  local tw = lcd.textWidth(title)
  lcd.print(bx + math.floor((boxW - tw) / 2), by + 8, title)

  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  local lv = string.format("Level: %d", level)
  local lvw = lcd.textWidth(lv)
  lcd.print(bx + math.floor((boxW - lvw) / 2), by + 32, lv)

  local s = string.format("Score: %d", score)
  local sw = lcd.textWidth(s)
  lcd.print(bx + math.floor((boxW - sw) / 2), by + 44, s)

  local hi = string.format("Best: %d", highScore)
  lcd.textColor(C_HI, C_HUD_BG)
  local hiw = lcd.textWidth(hi)
  lcd.print(bx + math.floor((boxW - hiw) / 2), by + 56, hi)

  lcd.textColor(C_DIM, C_HUD_BG)
  local hint = "OK: again   BACK: exit"
  local hw = lcd.textWidth(hint)
  lcd.print(bx + math.floor((boxW - hw) / 2), by + boxH - 14, hint)
end

local function spawnNextBlock()
  cur_width = top_width
  cur_x     = 0
  cur_y     = PLAY_TOP
  cur_dir   = 1
  prev_cx   = cur_x
end

local function resetTower()
  level_score = 0
  slide_speed = levelSlideBase()
  top_width   = INIT_WIDTH
  top_x       = math.floor((W - top_width) / 2)
  top_y       = PLAY_BOT - BLOCK_H
  stack       = { { x = top_x, w = top_width, y = top_y, ci = 0 } }
  spawnNextBlock()
end

local function resetGame()
  score            = 0
  level            = 1
  game_state       = "sliding"
  color_idx        = 1
  popup_drawn      = false
  last_score_shown = -1

  resetTower()
end

-- Tower hit the ceiling: scroll every landed block down one row, drop any
-- that fall off the bottom, and redraw so the climb continues seamlessly.
-- Counts as a level — the slider speeds up another notch.
local function scrollDown()
  local kept = {}
  for i = 1, #stack do
    local b = stack[i]
    b.y = b.y + BLOCK_H
    if b.y <= PLAY_BOT - BLOCK_H then kept[#kept + 1] = b end
  end
  stack = kept
  top_y = top_y + BLOCK_H

  lcd.rect(0, PLAY_TOP, W, PLAY_BOT - PLAY_TOP + 1, C_BG)
  for i = 1, #stack do
    local b = stack[i]
    drawBlock(b.x, b.y, b.w, colorForCi(b.ci))
  end
  drawHUD()   -- repaint the bar in case a block grazed it before scrolling
  last_score_shown = score

  level       = level + 1
  level_score = 0
  slide_speed = levelSlideBase()
  uni.beep(1200, 60)
end

-- ── Init ──────────────────────────────────────────────────
highScore = loadHigh()
resetGame()
drawSceneBackground()
drawHUD()
last_score_shown = score
drawBlock(top_x, top_y, top_width, C_PLATFORM)
drawBlock(cur_x, cur_y, cur_width, rowColor())

-- ── Main loop ─────────────────────────────────────────────
while true do
  local btn = nav.btn()
  if btn == "back" then break end

  if game_state == "sliding" then
    prev_cx = cur_x
    cur_x = cur_x + slide_speed * cur_dir
    if cur_x <= 0 then
      cur_x   = 0
      cur_dir = 1
    elseif cur_x + cur_width >= W then
      cur_x   = W - cur_width
      cur_dir = -1
    end

    if cur_x > prev_cx then
      lcd.rect(prev_cx, cur_y, cur_x - prev_cx, BLOCK_H, C_BG)
    elseif cur_x < prev_cx then
      lcd.rect(cur_x + cur_width, cur_y, prev_cx - cur_x, BLOCK_H, C_BG)
    end
    drawBlock(cur_x, cur_y, cur_width, rowColor())

    if btn == "ok" then
      game_state = "dropping"
    end

  elseif game_state == "dropping" then
    local prev_y = cur_y
    cur_y = cur_y + FALL_SPEED
    local target_y = top_y - BLOCK_H

    if cur_y >= target_y then
      cur_y = target_y
      lcd.rect(cur_x, prev_y, cur_width, BLOCK_H, C_BG)

      local left      = math.max(cur_x, top_x)
      local right     = math.min(cur_x + cur_width, top_x + top_width)
      local new_width = right - left

      if new_width <= 0 then
        game_state = "over"
        uni.beep(140, 250)
      else
        top_x     = left
        top_y     = cur_y
        top_width = new_width
        drawBlock(top_x, top_y, top_width, rowColor())
        stack[#stack + 1] = { x = top_x, w = top_width, y = top_y, ci = color_idx }
        score       = score + 1
        level_score = level_score + 1
        uni.beep(700 + level_score * 25, 35)

        -- Reached the ceiling: scroll the tower down to keep climbing.
        if top_y <= PLAY_TOP then scrollDown() end

        color_idx   = color_idx + 1
        slide_speed = math.min(levelSlideMax(), levelSlideBase() + math.floor(level_score / 4))
        spawnNextBlock()
        drawBlock(cur_x, cur_y, cur_width, rowColor())
        game_state = "sliding"
      end
    else
      lcd.rect(cur_x, prev_y, cur_width, cur_y - prev_y, C_BG)
      drawBlock(cur_x, cur_y, cur_width, rowColor())
    end

  else
    -- "over"
    if not popup_drawn then
      if score > highScore then
        highScore = score
        saveHigh(highScore)
        drawHUD()
        last_score_shown = score
      end
      drawPopup()
      popup_drawn = true
    end
    if btn == "ok" then
      drawSceneBackground()
      resetGame()
      drawHUD()
      last_score_shown = score
      drawBlock(top_x, top_y, top_width, C_PLATFORM)
      drawBlock(cur_x, cur_y, cur_width, rowColor())
    end
  end

  if (game_state == "sliding" or game_state == "dropping") and score ~= last_score_shown then
    drawHUD()
    last_score_shown = score
  end

  uni.delay(33)
end
