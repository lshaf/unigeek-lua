-- fishing-legend.lua — Port of @metalgalz's "Fishing Legend" (originally a
-- JavaScript app for the Bruce launcher). Rarity-tiered fishing with a
-- shop, durable rods, stackable charms, drop-rate luck mechanics + pity
-- bonus, day/night animated scene, and per-rarity sell prices.
--
-- Controls (default UniGeek 4-button board):
--   UP / DOWN : cursor / scroll. While fishing: toggle MAN <-> AUTO mode.
--   OK        : confirm / cast / mash-reel (MAN) / sell / equip / buy / toggle.
--   BACK      : back / exit.
--
-- The fishing scene composes into a half-screen off-screen sprite that is
-- pushed once per frame. The right-half sidebar (Recent / Top Luck / Stats)
-- renders directly with lcd.* and only repaints on need_full_redraw. Menu
-- screens render directly via lcd.* with diff-rendered cursor rows.
--
-- All state persists to /unigeek/games/fishing-legend.txt as JSON
-- (money, fish items, rod inventory, charm inventory). Fish / rod / charm
-- databases are hardcoded above — edit the tables in this file to mod.

local lcd    = require("uni.lcd")
local nav    = require("uni.nav")
local sd     = require("uni.sd")
local json   = require("uni.json")
local notify = require("uni.notify")

local W, H = lcd.w(), lcd.h()

-- ── Layout ─────────────────────────────────────────────────
local function alignDown(n, m) return n - (n % m) end
local GAME_W = math.max(8, alignDown(math.floor(W * 0.5), 8))
local SIDE_X = GAME_W + 2
local SIDE_W = W - SIDE_X
local SKY_H  = math.floor(H / 2)
local DECK_H = math.min(20, math.floor(H * 0.10))

-- ── Colours ────────────────────────────────────────────────
local cBlack   = lcd.color(  0,   0,   0)
local cWhite   = lcd.color(255, 255, 255)
local cBar     = lcd.color(255, 200,   0)
local cSun     = lcd.color(255, 255,   0)
local cMoon    = lcd.color(240, 240, 255)
local cStar    = lcd.color(180, 180, 180)
local cWave    = lcd.color( 30,  30, 150)
local cBird    = lcd.color( 50,  50,  50)
local cIsl     = lcd.color( 30,  80,  30)
local cShip    = lcd.color(100, 100, 100)
local cRodDef  = lcd.color(139,  69,  19)
local cRed     = lcd.color(255,   0,   0)
local cMenuBg  = lcd.color( 40,  40,  40)
local cBorder  = lcd.color(180, 180, 180)
local cSep     = lcd.color(100, 100, 100)
local cGrn     = lcd.color(  0, 255,   0)
local cYel     = lcd.color(255, 255,   0)
local cBoat    = lcd.color(139,  69,  19)
local cMenuSel = lcd.color(  0, 255, 255)
local cGold    = lcd.color(255, 215,   0)
local cCloudN  = lcd.color(100, 100, 100)
local cMountD  = lcd.color( 60,  60,  60)
local cMountN  = lcd.color( 20,  20,  40)
local cRain    = lcd.color(150, 150, 200)
local cRainSky = lcd.color( 70,  70,  80)
local cDanger  = lcd.color(255,  50,  50)
local cDim     = lcd.color(100, 100, 100)

local rCols = {
  lcd.color(200, 200, 200),  -- 0 Common
  lcd.color( 50, 255,  50),  -- 1 Uncommon
  lcd.color( 50, 100, 255),  -- 2 Rare
  lcd.color(200,   0, 255),  -- 3 Epic
  lcd.color(255, 165,   0),  -- 4 Legend
  lcd.color(255,  50,  50),  -- 5 Mythic
  lcd.color(  0, 255, 255),  -- 6 Secret
}
local function rarityColor(r) return rCols[r + 1] or rCols[1] end

-- ── Databases (hardcoded; edit to mod) ────────────────────
local fishDB = {
  { n = "Goldfish",   r = 0 },
  { n = "Nemo",       r = 1 },
  { n = "Piranha",    r = 2 },
  { n = "GreatWhite", r = 3 },
  { n = "Megalodon",  r = 4 },
  { n = "Kraken",     r = 5 },
  { n = "Cthulhu",    r = 6 },
}

local rodDB = {
  { n = "Starter Rod", r = 0, p = 100, d = 40, l = 10 },
}

local charmDB = {
  { n = "Rusty Coin", r = 1, p = 15000, d = 15, l = 500 },
}

local SELL_PRICE = { 20, 80, 650, 4500, 25000, 150000, 750000 }
local SAVE_PATH  = "/unigeek/games/fishing-legend.txt"

-- ── Persistent state ──────────────────────────────────────
local money    = 0
local items    = {}    -- name → { q, r }
local myRods   = {}    -- { n, r, p, d, curD, l, q, use }
local myCharms = {}    -- { n, r, d, curD, l, q, use }

-- ── Volatile state ────────────────────────────────────────
local appState = "title"
local menuIdx  = 0
local invScroll, invSel = 0, 0

local fishSt = 0   -- 0=cast, 1=wait, 2=fight, 5=escaped
local mode   = 0   -- 0=MAN, 1=AUTO
local tmCast, tmBite, tmAct = 0, 0, 0
local curFish, fStam, maxStam = nil, 0, 0
local tmDay, tmSpd = 0, 0.25
local wOff = 0
local rec, luck = {}, {}

local clouds, mountains, stars = {}, {}, {}
local bird = { x = -20, y = 10, a = false }
local isl  = { x = -40, a = false }
local ship = { x = -40, a = false }
local jmp  = { x = 0, y = 0, vy = 0, a = false }
local rain = { a = false, t = 0, tm = 0, drops = {} }
local dayCount = 0
local nextRainDay = 5 + math.random(0, 2)

local need_full_redraw = true
local prev_menu_idx    = -1
local sidebar_dirty    = true
local exit_requested   = false

for i = 1, 10 do
  stars[i] = { x = math.random(0, GAME_W - 1), y = math.random(0, SKY_H - 1) }
end

-- ── Formatting ────────────────────────────────────────────
local function fmtP(n)
  local i = math.floor(n)
  local f = math.floor((n - i) * 100)
  if f < 0 then f = -f end
  return string.format("%d.%02d%%", i, f)
end

local function fmtM(n)
  n = math.floor(n)
  local s = tostring(n)
  local out, cnt = {}, 0
  for i = #s, 1, -1 do
    table.insert(out, 1, s:sub(i, i))
    cnt = cnt + 1
    if cnt % 3 == 0 and i ~= 1 then table.insert(out, 1, ",") end
  end
  return table.concat(out)
end

local function fmtKg(w)
  local i = math.floor(w)
  local f = math.floor((w - i) * 100)
  return string.format("%d.%02dkg", i, f)
end

local function lerp(a, b, t) return a + (b - a) * t end

-- ── Sky / sea palette interpolation ───────────────────────
local SKY_N = {10,10,50}; local SKY_D = {60,60,100}; local SKY_M = {135,206,235}; local SKY_S = {255,160,120}
local SEA_N = {5,5,30};   local SEA_D = {20,40,100}; local SEA_M = {0,60,150};    local SEA_S = {60,40,90}

local function phaseColor(t, n, d, m, s)
  local c1, c2, p
  if     t < 300  then c1, c2, p = n, d, t / 300
  elseif t < 500  then c1, c2, p = d, m, (t - 300) / 200
  elseif t < 1500 then c1, c2, p = m, m, 0
  elseif t < 1700 then c1, c2, p = m, s, (t - 1500) / 200
  elseif t < 1900 then c1, c2, p = s, n, (t - 1700) / 200
  else                 c1, c2, p = n, n, 0 end
  return lcd.color(
    math.floor(lerp(c1[1], c2[1], p)),
    math.floor(lerp(c1[2], c2[2], p)),
    math.floor(lerp(c1[3], c2[3], p))
  )
end

local function getSkyColor(t) return phaseColor(t, SKY_N, SKY_D, SKY_M, SKY_S) end
local function getSeaColor(t) return phaseColor(t, SEA_N, SEA_D, SEA_M, SEA_S) end

-- ── Save / load ───────────────────────────────────────────
local function ensureDir()
  if not sd.exists("/unigeek/games") then sd.mkdir("/unigeek/games") end
end

local function saveAll()
  ensureDir()
  sd.write(SAVE_PATH, json.encode({
    money  = money,
    items  = items,
    rods   = myRods,
    charms = myCharms,
  }))
end

local function loadAll()
  if not sd.exists(SAVE_PATH) then return end
  local raw = sd.read(SAVE_PATH) or ""
  if #raw == 0 then return end
  local data = json.decode(raw)
  if type(data) ~= "table" then return end
  money    = tonumber(data.money) or 0
  items    = (type(data.items)  == "table") and data.items  or {}
  myRods   = (type(data.rods)   == "table") and data.rods   or {}
  myCharms = (type(data.charms) == "table") and data.charms or {}
end

-- ── Toast (uses firmware notify) ──────────────────────────
local function showToast(msg)
  notify.show(msg, 1500)
  need_full_redraw = true
end

-- ── Rod system ────────────────────────────────────────────
local function getCurRod()
  for _, r in ipairs(myRods) do
    if r.use then return r end
  end
  if #myRods == 0 then
    table.insert(myRods, { n = "Bamboo Rod", r = 0, p = 0, d = 0, curD = 0, l = 0, q = 1, use = true })
  else
    myRods[1].use = true
  end
  return myRods[1]
end

local function autoEquip(brokenRarity)
  for _, r in ipairs(myRods) do r.use = false end
  local bestIdx, bestR = 0, -1
  for i, r in ipairs(myRods) do
    if r.r <= brokenRarity and r.r > bestR then bestR = r.r; bestIdx = i end
  end
  if bestIdx == 0 and #myRods > 0 then
    local minR = 999
    for i, r in ipairs(myRods) do
      if r.r < minR then minR = r.r; bestIdx = i end
    end
  end
  if bestIdx > 0 then
    myRods[bestIdx].use = true
    showToast("Equipped: " .. myRods[bestIdx].n)
  else
    table.insert(myRods, { n = "Bamboo Rod", r = 0, p = 0, d = 0, curD = 0, l = 0, q = 1, use = true })
    showToast("Equipped: Bamboo Rod")
  end
end

local function useRod()
  local rod = getCurRod()
  if (rod.d or 0) <= 0 then return end
  rod.curD = rod.curD - 1
  if rod.curD <= 0 then
    uni.beep(100, 500)
    rod.q = rod.q - 1
    if rod.q > 0 then
      rod.curD = rod.d
      showToast(rod.n .. " Broke! (Spare)")
    else
      local brokenRarity = rod.r
      local brokenIdx
      for i, r in ipairs(myRods) do if r == rod then brokenIdx = i; break end end
      if brokenIdx then table.remove(myRods, brokenIdx) end
      autoEquip(brokenRarity)
    end
  end
end

local function buyRod(idx)
  local rb = rodDB[idx + 1]
  if not rb then return end
  if money < rb.p then
    showToast("NOT ENOUGH MONEY!"); uni.beep(200, 200); return
  end
  money = money - rb.p
  local existing
  for i, r in ipairs(myRods) do if r.n == rb.n then existing = i; break end end
  if existing then
    myRods[existing].q = myRods[existing].q + 1
  else
    table.insert(myRods, { n = rb.n, r = rb.r, p = rb.p, d = rb.d, curD = rb.d, l = rb.l, q = 1, use = false })
  end
  saveAll()
  showToast("BOUGHT " .. rb.n)
  uni.beep(1000, 100); uni.delay(50); uni.beep(2000, 200)
end

local function equipRod(idx)
  if not myRods[idx + 1] then return end
  for _, r in ipairs(myRods) do r.use = false end
  myRods[idx + 1].use = true
  saveAll()
  uni.beep(1500, 100)
end

-- ── Charm system ──────────────────────────────────────────
local function buyCharm(idx)
  local ch = charmDB[idx + 1]
  if not ch then return end
  if money < ch.p then
    showToast("NOT ENOUGH MONEY!"); uni.beep(200, 200); return
  end
  money = money - ch.p
  local existing
  for i, c in ipairs(myCharms) do if c.n == ch.n then existing = i; break end end
  if existing then
    myCharms[existing].q = myCharms[existing].q + 1
  else
    table.insert(myCharms, { n = ch.n, r = ch.r, d = ch.d, curD = ch.d, l = ch.l, q = 1, use = false })
  end
  saveAll()
  showToast("BOUGHT " .. ch.n)
  uni.beep(1000, 100); uni.delay(50); uni.beep(2000, 200)
end

local function toggleCharm(idx)
  if not myCharms[idx + 1] then return end
  myCharms[idx + 1].use = not myCharms[idx + 1].use
  saveAll()
  uni.beep(1500, 50)
end

local function useCharms()
  local broken
  for i = #myCharms, 1, -1 do
    local ch = myCharms[i]
    if ch.use then
      ch.curD = ch.curD - 1
      if ch.curD <= 0 then
        ch.q = ch.q - 1
        if ch.q > 0 then ch.curD = ch.d
        else
          table.remove(myCharms, i)
          broken = broken or ch.n
        end
      end
    end
  end
  if broken then
    uni.beep(100, 500)
    showToast("Charm Depleted: " .. broken)
  end
end

-- ── Drop-rate / catch ─────────────────────────────────────
local function getTotalLuck()
  local rod = getCurRod()
  local l = rod.l or 0
  if (rod.d or 0) > 0 then
    if rod.curD <= rod.d * 0.25 then l = l + rod.l * 0.45
    elseif rod.curD <= rod.d * 0.5 then l = l + rod.l * 0.20 end
  end
  for _, ch in ipairs(myCharms) do
    if ch.use then l = l + (ch.l or 0) end
  end
  return math.floor(l)
end

local function getW(r)
  local lo, hi = 1, 5
  if     r == 1 then lo, hi = 2, 10
  elseif r == 2 then lo, hi = 10, 50
  elseif r == 3 then lo, hi = 50, 200
  elseif r == 4 then lo, hi = 200, 1000
  elseif r == 5 then lo, hi = 1000, 5000
  elseif r == 6 then lo, hi = 5000, 9999 end
  return lo + math.random() * (hi - lo)
end

local function randF()
  local luckBonus = getTotalLuck()
  local mult = 1.0 + (luckBonus / 100.0)
  local roll = math.random() * 100

  local t6 = math.min(50,  0.01 * mult)
  local t5 = math.min(65,  0.15 * mult)
  local t4 = math.min(95,  0.60 * mult)
  local t3 = math.min(99,  2.50 * mult)
  local t2 = math.min(100, 12.0 * mult)
  local t1 = math.min(100, 45.0 * mult)

  local r
  if     roll < t6 then r = 6
  elseif roll < t5 then r = 5
  elseif roll < t4 then r = 4
  elseif roll < t3 then r = 3
  elseif roll < t2 then r = 2
  elseif roll < t1 then r = 1
  else                  r = 0 end

  local cand = {}
  for _, f in ipairs(fishDB) do
    if f.r == r then table.insert(cand, f) end
  end
  if #cand == 0 and #fishDB > 0 then cand[1] = fishDB[1] end
  local picked = cand[math.random(1, #cand)]
  local weight = getW(picked.r)
  return { n = picked.n, r = picked.r, w = weight, hp = 15 + (picked.r * 10) + (weight * 0.01) }
end

local function sortLuck(a, b)
  if a.r ~= b.r then return a.r > b.r end
  return a.w > b.w
end

local function sortByRarityLuckAsc(a, b)
  if a.r ~= b.r then return a.r < b.r end
  return (a.l or 0) < (b.l or 0)
end

local function fishKeySort(a, b)
  local rA, rB = items[a].r, items[b].r
  if rA ~= rB then return rA > rB end
  return a < b
end

local function addCatch(f)
  table.insert(rec, 1, { name = f.n, w = f.w, r = f.r })
  while #rec > 3 do table.remove(rec) end
  if f.r >= 3 then
    table.insert(luck, { name = f.n, r = f.r, w = f.w })
    table.sort(luck, sortLuck)
    while #luck > 3 do table.remove(luck) end
  end
  if not items[f.n] then items[f.n] = { q = 0, r = f.r } end
  items[f.n].q = items[f.n].q + 1
  if items[f.n].r < f.r then items[f.n].r = f.r end
  useRod()
  useCharms()
  saveAll()
end

-- ── Sell ──────────────────────────────────────────────────
local function countItems()
  local c = 0
  for _ in pairs(items) do c = c + 1 end
  return c
end

local function sellOne(name)
  local item = items[name]
  if not item or item.q <= 0 then return end
  money = money + SELL_PRICE[item.r + 1] * item.q
  items[name] = nil
  local n = countItems()
  if invSel >= n and invSel > 0 then invSel = invSel - 1 end
  saveAll()
  uni.beep(1200, 50); uni.delay(50); uni.beep(1800, 100)
end

local function sellAll()
  local total, count = 0, 0
  for _, it in pairs(items) do
    total = total + SELL_PRICE[it.r + 1] * it.q
    count = count + 1
  end
  if count == 0 then
    showToast("NOTHING TO SELL!"); uni.beep(200, 200); return
  end
  money = money + total
  items = {}
  saveAll()
  showToast("SOLD ALL! +$" .. fmtM(total))
  uni.beep(1000, 50); uni.delay(50); uni.beep(2000, 50); uni.delay(50); uni.beep(3000, 100)
end

-- ── Sprite allocation ─────────────────────────────────────
local game_sp = lcd.sprite(GAME_W, H)
if not game_sp then
  lcd.fillScreen(cBlack)
  lcd.textSize(1)
  lcd.textColor(cRed, cBlack)
  lcd.print(10, 10, "Fishing Legend: heap too low")
  lcd.print(10, 28, string.format("Need ~%d KB, free %d KB",
    math.floor(GAME_W * H * 2 / 1024), math.floor(uni.heap() / 1024)))
  lcd.textColor(cWhite, cBlack)
  lcd.print(10, 56, "Press BACK to exit.")
  while nav.btn() ~= "back" do uni.delay(100) end
  return
end

-- ── Sidebar draw helpers ──────────────────────────────────
local function drawSidebarBox(x, y, w, h, title, titleColor)
  lcd.rect(x, y, w, h, cMenuBg)
  lcd.rect(x,         y,         w, 1, cBorder)
  lcd.rect(x,         y + h - 1, w, 1, cBorder)
  lcd.rect(x,         y,         1, h, cBorder)
  lcd.rect(x + w - 1, y,         1, h, cBorder)
  lcd.textSize(1)
  lcd.textColor(titleColor, cMenuBg)
  local tw = lcd.textWidth(title)
  lcd.print(x + math.floor((w - tw) / 2), y + 3, title)
end

local function drawSidebar()
  lcd.rect(GAME_W, 0, 2, H, cSep)
  local bH1 = math.floor(H / 3)
  local bH2 = math.floor(H / 3)
  local bH3 = H - bH1 - bH2
  local boxW = SIDE_W

  -- RECENT
  drawSidebarBox(SIDE_X, 0, boxW, bH1, "RECENT", cMenuSel)
  lcd.textSize(1)
  for i, f in ipairs(rec) do
    if i > 3 then break end
    local y = 18 + (i - 1) * 10
    local name = f.name
    if #name > 10 then name = name:sub(1, 10) end
    lcd.textColor(rarityColor(f.r), cMenuBg)
    lcd.print(SIDE_X + 3, y, name)
    lcd.textColor(cWhite, cMenuBg)
    local ws = fmtKg(f.w)
    lcd.print(SIDE_X + boxW - 3 - lcd.textWidth(ws), y, ws)
  end

  -- TOP LUCK
  drawSidebarBox(SIDE_X, bH1, boxW, bH2, "TOP LUCK", cBar)
  if #luck == 0 then
    lcd.textColor(cDim, cMenuBg)
    lcd.print(SIDE_X + 3, bH1 + 18, "- Empty -")
  else
    for i, f in ipairs(luck) do
      if i > 3 then break end
      local y = bH1 + 18 + (i - 1) * 10
      local name = f.name
      if #name > 10 then name = name:sub(1, 10) end
      lcd.textColor(rarityColor(f.r), cMenuBg)
      lcd.print(SIDE_X + 3, y, name)
      lcd.textColor(cWhite, cMenuBg)
      local ws = fmtKg(f.w)
      lcd.print(SIDE_X + boxW - 3 - lcd.textWidth(ws), y, ws)
    end
  end

  -- STATS
  local y3 = bH1 + bH2
  drawSidebarBox(SIDE_X, y3, boxW, bH3, "STATS", cGrn)
  local rod = getCurRod()
  local rodCol = (rod.r == 0 and rod.p == 0) and cRodDef or rarityColor(rod.r)
  local totalL = getTotalLuck()
  local mult = 1.0 + (totalL / 100.0)

  lcd.textColor(rodCol, cMenuBg)
  local rn = rod.n
  if #rn > 14 then rn = rn:sub(1, 14) .. ".." end
  lcd.print(SIDE_X + 3, y3 + 16, rn)

  local durText = ((rod.d or 0) == 0) and "Inf" or (rod.curD .. "/" .. rod.d)
  local durCol = ((rod.d or 0) > 0 and rod.curD < 10) and cDanger or cWhite
  lcd.textColor(durCol, cMenuBg)
  lcd.print(SIDE_X + 3, y3 + 26, "D:" .. durText)

  local activeCharms = 0
  for _, ch in ipairs(myCharms) do if ch.use then activeCharms = activeCharms + 1 end end
  lcd.textColor(cWhite, cMenuBg)
  lcd.print(SIDE_X + 3, y3 + 36, "Charm:" .. activeCharms)

  local pityActive = (rod.d or 0) > 0 and rod.curD <= rod.d * 0.5
  lcd.textColor(pityActive and cGold or cWhite, cMenuBg)
  lcd.print(SIDE_X + 3, y3 + 46, "Luck:+" .. totalL .. "%")

  local rX = SIDE_X + boxW - 3
  local t4 = math.min(95, 0.60 * mult)
  local t5 = math.min(65, 0.15 * mult)
  local t6 = math.min(50, 0.01 * mult)

  lcd.textColor(rarityColor(3), cMenuBg)
  local s = "Epic++"; lcd.print(rX - lcd.textWidth(s), y3 + 16, s)
  lcd.textColor(rarityColor(4), cMenuBg)
  s = fmtP(t4); lcd.print(rX - lcd.textWidth(s), y3 + 26, s)
  lcd.textColor(rarityColor(5), cMenuBg)
  s = fmtP(t5); lcd.print(rX - lcd.textWidth(s), y3 + 36, s)
  lcd.textColor(rarityColor(6), cMenuBg)
  s = fmtP(t6); lcd.print(rX - lcd.textWidth(s), y3 + 46, s)
end

-- ── Fishing-scene draw (into sprite) ──────────────────────
local function drawTriangleMountain(x, mc)
  for row = 0, 15 do
    local rw = math.floor((row + 1) * 32 / 16)
    game_sp:rect(x + math.floor((32 - rw) / 2), SKY_H - 16 + row, rw, 1, mc)
  end
end

local function drawFishingScene(now_ms)
  local sky_color = getSkyColor(tmDay)
  local sea_color = getSeaColor(tmDay)
  local isNight   = (tmDay < 400 or tmDay > 1800)
  if rain.a and not isNight then sky_color = cRainSky end

  -- Sky / sea / deck
  game_sp:rect(0, 0, GAME_W, SKY_H, sky_color)
  game_sp:rect(0, SKY_H, GAME_W, H - SKY_H - DECK_H, sea_color)
  game_sp:rect(0, H - DECK_H, GAME_W, DECK_H, cBoat)

  -- Mountains
  local mc = isNight and cMountN or cMountD
  for _, m in ipairs(mountains) do
    drawTriangleMountain(math.floor(m.x), mc)
  end

  -- Stars / sun / moon
  if isNight then
    for j, s in ipairs(stars) do
      if (math.floor(tmDay) + j) % 3 ~= 0 then
        game_sp:rect(s.x, s.y, 1, 1, cStar)
      end
    end
    local mX
    if tmDay > 1700 then mX = math.floor((tmDay - 1700) / 800 * GAME_W)
    else mX = math.floor((300 + tmDay) / 800 * GAME_W) + math.floor(GAME_W / 2) end
    game_sp:fillCircle(mX, 10, 4, cMoon)
  else
    local sXPos = math.floor((tmDay - 500) / 1200 * GAME_W)
    local sYPos = 30 - math.floor(math.sin((tmDay - 500) / 1200 * math.pi) * 20)
    if not rain.a then game_sp:fillCircle(sXPos, sYPos, 4, cSun) end
  end

  -- Clouds
  local cloudCol = isNight and cCloudN or cWhite
  for _, c in ipairs(clouds) do
    local cx = math.floor(c.x)
    local cy = math.floor(c.y)
    game_sp:fillCircle(cx + 4, cy + 4, 4, cloudCol)
    game_sp:fillCircle(cx + 10, cy + 4, 4, cloudCol)
    game_sp:fillCircle(cx + 7, cy + 2, 3, cloudCol)
  end

  -- Island (semicircle clipped at sea line)
  if isl.a then
    local ix = math.floor(isl.x)
    local ic = isNight and cBird or cIsl
    game_sp:fillCircle(ix + 32, SKY_H - 4, 14, ic)
    game_sp:rect(ix, SKY_H, 64, 16, sea_color)
  end

  -- Ship
  if ship.a then
    local shx = math.floor(ship.x)
    local sc = isNight and cBird or cShip
    game_sp:rect(shx + 4, SKY_H - 6, 16, 4, sc)
    game_sp:rect(shx + 10, SKY_H - 10, 2, 4, sc)
  end

  -- Jumping fish splash
  if jmp.a then
    game_sp:fillCircle(math.floor(jmp.x), math.floor(jmp.y), 2, cWhite)
  end

  -- Bird
  if not isNight and bird.a then
    local bx = math.floor(bird.x)
    local by = math.floor(bird.y)
    game_sp:line(bx,     by + 2, bx + 2, by,     cBird)
    game_sp:line(bx + 2, by,     bx + 4, by + 2, cBird)
  end

  -- Wave stripes
  for y = SKY_H + 5, H - DECK_H - 2, 8 do
    if ((tmDay / 5) + y) % 10 > 5 then
      local wy = math.floor(y + wOff)
      if wy < H - DECK_H then game_sp:line(5, wy, GAME_W - 5, wy, cWave) end
    end
  end

  -- Rain
  for _, p in ipairs(rain.drops) do
    local px = math.floor(p.x)
    local py = math.floor(p.y)
    if rain.t == 1 then
      game_sp:line(px, py, px - 2, py + p.l, cRain)
    else
      game_sp:line(px, py, px, py + p.l, cRain)
    end
  end

  -- Rod
  local rod = getCurRod()
  local rodCol = (rod.r == 0 and rod.p == 0) and cRodDef or rarityColor(rod.r)
  local rbX, rbY = GAME_W + 10, H + 10
  local rtX, rtY = math.floor(GAME_W / 2), math.floor(H / 2) - 20
  if fishSt == 2 and math.floor(now_ms / 200) % 2 == 0 then
    rtY = rtY - 8; rtX = rtX + 3
  end
  for t = 0, 2 do
    game_sp:line(rbX + t, rbY, rtX + t, rtY, (t == 1) and rodCol or cRodDef)
  end

  -- Bobber + line
  if fishSt == 1 or fishSt == 2 then
    local bX = math.floor(GAME_W / 2)
    local bY = math.floor(H / 2) + 10 + wOff
    if fishSt == 2 then
      bX = bX + math.random(-3, 3)
      bY = bY + math.random(-2, 2)
    end
    game_sp:line(rtX, rtY, bX, bY, cBlack)
    if fishSt == 1 then
      bY = bY + math.floor(math.sin(now_ms / 300) * 2)
      local bobColor = cRed
      if (rod.d or 0) > 0 then
        local spd
        if rod.curD <= rod.d * 0.25 then spd = 2
        elseif rod.curD <= rod.d * 0.5 then spd = 7 end
        if spd then
          bobColor = lcd.color(
            math.floor(128 + 127 * math.sin(now_ms / spd)),
            math.floor(128 + 127 * math.sin((now_ms / spd) + 2.09)),
            math.floor(128 + 127 * math.sin((now_ms / spd) + 4.18))
          )
        end
      end
      game_sp:rect(bX - 2, bY - 2, 4, 4, bobColor)
    else
      game_sp:textSize(1)
      game_sp:textColor(cWhite, sea_color)
      game_sp:print(bX - 2, bY - 15, "!")
    end
  end

  -- Status text
  game_sp:textSize(1)
  local cX = math.floor(GAME_W / 2)
  if fishSt == 0 then
    game_sp:textColor(cWhite, cBoat)
    local s = "CASTING..."
    game_sp:print(cX - math.floor(game_sp:textWidth(s) / 2), H - 10, s)
  elseif fishSt == 1 then
    game_sp:textColor(cWhite, cBoat)
    local s = "WAITING..."
    game_sp:print(cX - math.floor(game_sp:textWidth(s) / 2), H - 20, s)
    local m = (mode == 1) and "< AUTO >" or "< MAN >"
    game_sp:textColor(mode == 1 and cGrn or cYel, cBoat)
    game_sp:print(cX - math.floor(game_sp:textWidth(m) / 2), H - 10, m)
  elseif fishSt == 2 then
    game_sp:textColor(cWhite, cBoat)
    local s = (mode == 1) and "REELING..." or "MASH OK!"
    game_sp:print(cX - math.floor(game_sp:textWidth(s) / 2), H - 15, s)
    local barW = math.max(8, GAME_W - 20)
    local bX = math.floor((GAME_W - barW) / 2)
    local barY = H - 35
    local pct = fStam / maxStam
    if pct < 0 then pct = 0 end
    game_sp:rect(bX, barY, barW, 6, cWhite)
    local fW = math.floor((barW - 2) * pct)
    if fW > 0 then game_sp:rect(bX + 1, barY + 1, fW, 4, cBar) end
  elseif fishSt == 5 then
    game_sp:textColor(cRed, sea_color)
    local s = "ESCAPED!"
    game_sp:print(cX - math.floor(game_sp:textWidth(s) / 2), math.floor(H / 2), s)
    game_sp:textColor(cWhite, sea_color)
    s = "Too Slow!"
    game_sp:print(cX - math.floor(game_sp:textWidth(s) / 2), math.floor(H / 2) + 15, s)
  end

  game_sp:push(0, 0)
end

-- ── Menu rendering helpers ────────────────────────────────
local function eraseRow(y, h)
  lcd.rect(0, y, W, h, cBlack)
end

local function drawCenteredText(y, text, color, sz)
  lcd.textSize(sz or 1)
  lcd.textColor(color, cBlack)
  lcd.print(math.floor((W - lcd.textWidth(text)) / 2), y, text)
end

local function drawTitleHeader(title, withMoney)
  lcd.fillScreen(cBlack)
  drawCenteredText(20, title, cWhite, 1)
  lcd.rect(20, 32, W - 40, 1, cSep)
  if withMoney then
    drawCenteredText(45, "$ " .. fmtM(money), cGold, 1)
  end
end

local function drawSimpleMenu(opts, startY)
  lcd.textSize(1)
  for i, opt in ipairs(opts) do
    local y = startY + (i - 1) * 16
    local label = ((i - 1) == menuIdx) and ("> " .. opt .. " <") or ("  " .. opt .. "  ")
    local color = ((i - 1) == menuIdx) and cMenuSel or cDim
    eraseRow(y, 12)
    lcd.textColor(color, cBlack)
    lcd.print(math.floor((W - lcd.textWidth(label)) / 2), y, label)
  end
end

local function drawHint(text)
  drawCenteredText(H - 12, text, cMenuSel, 1)
end

local function clampMenu(opts, btn)
  if btn == "down" then
    menuIdx = menuIdx + 1
    if menuIdx >= #opts then menuIdx = 0 end
    uni.beep(600, 20)
  elseif btn == "up" then
    menuIdx = menuIdx - 1
    if menuIdx < 0 then menuIdx = #opts - 1 end
    uni.beep(600, 20)
  end
end

local function clampScroll(count, maxLines, btn)
  if btn == "down" then
    invSel = invSel + 1
    if invSel >= count then invSel = count - 1 end
    if invSel >= invScroll + maxLines then invScroll = invSel - maxLines + 1 end
    uni.beep(600, 20)
  elseif btn == "up" then
    invSel = invSel - 1
    if invSel < 0 then invSel = 0 end
    if invSel < invScroll then invScroll = invSel end
    uni.beep(600, 20)
  end
end

local function drawSelectionBox(x, y, w, h)
  lcd.rect(x,         y,         w, 1, cMenuSel)
  lcd.rect(x,         y + h - 1, w, 1, cMenuSel)
  lcd.rect(x,         y,         1, h, cMenuSel)
  lcd.rect(x + w - 1, y,         1, h, cMenuSel)
end

-- ── State steps ───────────────────────────────────────────
local function step_title(now, btn)
  local opts = { "START GAME", "SHOP", "INVENTORY", "EXIT" }
  if need_full_redraw then
    lcd.fillScreen(cBlack)
    drawCenteredText(20, "FISHING LEGEND", cWhite, 2)
    lcd.textSize(1)
    drawCenteredText(50, "$ " .. fmtM(money), cGold, 1)
    drawCenteredText(H - 22, "by hxd57 / metalgalz", cDim, 1)
    drawCenteredText(H - 10, "Lua port: lshaf",      cDim, 1)
    need_full_redraw = false
    prev_menu_idx = -1
  end
  clampMenu(opts, btn)
  if menuIdx ~= prev_menu_idx then
    drawSimpleMenu(opts, 75)
    prev_menu_idx = menuIdx
  end
  if btn == "ok" then
    uni.beep(800, 100)
    if     menuIdx == 0 then appState = "fish";  fishSt = 0; rec = {}; luck = {}; need_full_redraw = true
    elseif menuIdx == 1 then appState = "shop";  menuIdx = 0; need_full_redraw = true
    elseif menuIdx == 2 then appState = "inv";   menuIdx = 0; need_full_redraw = true
    elseif menuIdx == 3 then exit_requested = true end
    uni.delay(150)
  end
end

local function step_fish(now, btn)
  if need_full_redraw then
    lcd.fillScreen(cBlack)
    drawSidebar()
    need_full_redraw = false
    sidebar_dirty = false
  end

  tmDay = tmDay + tmSpd
  if tmDay > 2000 then
    tmDay = 0
    dayCount = dayCount + 1
    if dayCount >= nextRainDay then
      rain.a = true
      rain.t = (math.random() > 0.7) and 1 or 0
      rain.tm = 800 + math.random(0, 399)
      nextRainDay = dayCount + 5 + math.random(0, 2)
    end
  end

  if rain.a then
    rain.tm = rain.tm - 1
    if rain.tm <= 0 then rain.a = false end
    if now % 2 == 0 then
      local spawn = (rain.t == 1) and 2 or 1
      for _ = 1, spawn do
        if #rain.drops < 40 then
          table.insert(rain.drops, {
            x = math.random(0, GAME_W - 1),
            y = -10,
            l = (rain.t == 1) and 6 or 3,
            s = (rain.t == 1) and 5 or 3,
          })
        end
      end
    end
  end
  for i = #rain.drops, 1, -1 do
    local p = rain.drops[i]
    p.y = p.y + p.s
    if rain.t == 1 then p.x = p.x - 2 end
    if p.y > H - DECK_H then table.remove(rain.drops, i) end
  end

  if math.random() > 0.985 and #clouds < 3 then
    table.insert(clouds, { x = GAME_W + 10, y = 5 + math.random() * 20, s = 0.1 + math.random() * 0.2 })
  end
  for i = #clouds, 1, -1 do
    clouds[i].x = clouds[i].x - clouds[i].s
    if clouds[i].x < -40 then table.remove(clouds, i) end
  end

  if math.random() > 0.995 and #mountains < 2 then
    table.insert(mountains, { x = GAME_W + 20 })
  end
  for i = #mountains, 1, -1 do
    mountains[i].x = mountains[i].x - 0.05
    if mountains[i].x < -40 then table.remove(mountains, i) end
  end

  local isN = (tmDay < 400 or tmDay > 1800)
  if not isN and math.random() > 0.98 and not bird.a then
    bird.a = true; bird.x = -10; bird.y = 5 + math.random() * 20
  end
  if bird.a then bird.x = bird.x + 1; if bird.x > GAME_W then bird.a = false end end

  if not isl.a and math.random() > 0.995 then isl.a = true; isl.x = GAME_W end
  if isl.a then isl.x = isl.x - 0.2; if isl.x < -70 then isl.a = false end end

  if not ship.a and math.random() > 0.993 then ship.a = true; ship.x = GAME_W + 10 end
  if ship.a then ship.x = ship.x - 0.3; if ship.x < -30 then ship.a = false end end

  if not jmp.a and math.random() > 0.99 then
    jmp.a = true; jmp.x = 20 + math.random() * (GAME_W - 40); jmp.y = SKY_H + 5; jmp.vy = -2.5
  end
  if jmp.a then
    jmp.y = jmp.y + jmp.vy; jmp.vy = jmp.vy + 0.2
    if jmp.y > SKY_H + 10 then jmp.a = false end
  end

  if now % 200 < 20 then wOff = math.random(0, isN and 1 or 3) end

  local activeRod = getCurRod()
  if fishSt == 0 then
    fishSt = 1
    tmCast = now
    tmBite = tmCast + 1000 + math.random(0, 1999)
  elseif fishSt == 1 then
    if btn == "up" or btn == "down" then
      mode = (mode == 0) and 1 or 0
      uni.beep(600, 50)
    end
    if now > tmBite then
      curFish = randF()
      fStam = curFish.hp
      maxStam = fStam
      fishSt = 2
      tmAct = now
      uni.beep(800, 80); uni.beep(800, 80)
    end
  elseif fishSt == 2 then
    if btn == "up" or btn == "down" then
      mode = (mode == 0) and 1 or 0
      if mode == 0 then tmAct = now end
      uni.beep(600, 50)
    end
    fStam = fStam + (0.3 + curFish.r * 0.1)
    if fStam > maxStam then fStam = maxStam end

    local totalL = getTotalLuck()
    local rodPwr = math.sqrt(totalL) * 0.1
    local dmgMan  = 8 + (activeRod.r * 2) + rodPwr
    local dmgAuto = 1.0 + (activeRod.r * 0.8) + (rodPwr * 0.5)

    if mode == 0 then
      if btn == "ok" then
        fStam = fStam - dmgMan
        tmAct = now
        uni.beep(200, 20)
      end
      if now - tmAct > 3000 then
        fishSt = 5
        uni.beep(100, 500)
      end
    else
      fStam = fStam - dmgAuto
      if now % 500 < 50 then uni.beep(200, 10) end
    end

    if fStam <= 0 then
      addCatch(curFish)
      uni.beep(1000, 100); uni.beep(1500, 200)
      fishSt = 0
      sidebar_dirty = true
    end
  elseif fishSt == 5 then
    if btn == "ok" or (now - tmAct > 1500) then fishSt = 0 end
  end

  drawFishingScene(now)
  if sidebar_dirty then drawSidebar(); sidebar_dirty = false end
end

local function step_inv(now, btn)
  local opts = { "FISH", "ROD", "CHARM", "SELL ALL", "BACK" }
  if need_full_redraw then
    drawTitleHeader("INVENTORY", false)
    need_full_redraw = false; prev_menu_idx = -1
  end
  clampMenu(opts, btn)
  if menuIdx ~= prev_menu_idx then drawSimpleMenu(opts, 55); prev_menu_idx = menuIdx end
  if btn == "ok" then
    uni.beep(800, 100)
    if menuIdx == 0 then
      appState = "fishinv"; invScroll = 0; invSel = 0; need_full_redraw = true
    elseif menuIdx == 1 then
      table.sort(myRods, sortByRarityLuckAsc)
      appState = "rodinv"; invScroll = 0; invSel = 0; need_full_redraw = true
    elseif menuIdx == 2 then
      table.sort(myCharms, sortByRarityLuckAsc)
      appState = "charminv"; invScroll = 0; invSel = 0; need_full_redraw = true
    elseif menuIdx == 3 then
      sellAll(); need_full_redraw = true
    elseif menuIdx == 4 then
      appState = "title"; menuIdx = 0; need_full_redraw = true
    end
    uni.delay(150)
  end
end

local function step_shop(now, btn)
  local opts = { "ROD", "CHARM", "BACK" }
  if need_full_redraw then
    drawTitleHeader("SHOP", true)
    need_full_redraw = false; prev_menu_idx = -1
  end
  clampMenu(opts, btn)
  if menuIdx ~= prev_menu_idx then drawSimpleMenu(opts, 70); prev_menu_idx = menuIdx end
  if btn == "ok" then
    uni.beep(800, 100)
    if     menuIdx == 0 then appState = "rodshop";   invScroll = 0; invSel = 0; need_full_redraw = true
    elseif menuIdx == 1 then appState = "charmshop"; invScroll = 0; invSel = 0; need_full_redraw = true
    elseif menuIdx == 2 then appState = "title"; menuIdx = 0; need_full_redraw = true end
    uni.delay(150)
  end
end

-- ── Inventory: fish ───────────────────────────────────────
local function step_fishinv(now, btn)
  local was_full = need_full_redraw
  local key_count = 0
  for _ in pairs(items) do key_count = key_count + 1 end

  if need_full_redraw then
    lcd.fillScreen(cBlack)
    drawCenteredText(10, "FISH (" .. key_count .. ")  $" .. fmtM(money), cWhite, 1)
    lcd.rect(20, 22, W - 40, 1, cSep)
    drawHint("[OK] SELL   [BACK] EXIT")
    if key_count == 0 then
      drawCenteredText(math.floor(H / 2), "(Empty - Catch fish!)", cDim, 1)
    end
    need_full_redraw = false
  end

  if key_count == 0 then return end

  local maxLines = 5
  clampScroll(key_count, maxLines, btn)

  local list_dirty = was_full or btn == "up" or btn == "down" or btn == "ok"
  if not list_dirty then return end

  local keys = {}
  for k in pairs(items) do table.insert(keys, k) end
  table.sort(keys, fishKeySort)

  if btn == "ok" then
    sellOne(keys[invSel + 1])
    need_full_redraw = true
    uni.delay(150)
    return
  end

  for i = 0, maxLines - 1 do
    local idx = invScroll + i
    local y = 35 + i * 18
    eraseRow(y - 2, 18)
    if idx < #keys then
      local name = keys[idx + 1]
      local it = items[name]
      local price = SELL_PRICE[it.r + 1] or 0
      if idx == invSel then drawSelectionBox(18, y - 2, W - 36, 16) end
      lcd.textColor(rarityColor(it.r), cBlack)
      lcd.print(22, y, name)
      lcd.textColor(cWhite, cBlack)
      lcd.print(100, y, "x" .. tostring(it.q))
      lcd.textColor(cGold, cBlack)
      local ps = "$" .. fmtM(price)
      lcd.print(W - 5 - lcd.textWidth(ps), y, ps)
    end
  end

  if #keys > maxLines then
    eraseRow(H - 22, 8)
    drawCenteredText(H - 22, (invSel + 1) .. "/" .. #keys, cDim, 1)
  end
end

-- ── Inventory: rods ───────────────────────────────────────
local function step_rodinv(now, btn)
  local was_full = need_full_redraw
  if need_full_redraw then
    lcd.fillScreen(cBlack)
    drawCenteredText(20, "MY RODS", cWhite, 1)
    lcd.rect(20, 32, W - 40, 1, cSep)
    drawHint("[OK] EQUIP   [BACK] EXIT")
    if #myRods == 0 then
      drawCenteredText(math.floor(H / 2), "(No rods?)", cDim, 1)
    end
    need_full_redraw = false
  end

  if #myRods == 0 then return end
  local maxLines = 5
  clampScroll(#myRods, maxLines, btn)
  if btn == "ok" then equipRod(invSel); need_full_redraw = true; uni.delay(150); return end

  if not (was_full or btn == "up" or btn == "down") then return end

  for i = 0, maxLines - 1 do
    local idx = invScroll + i
    local y = 38 + i * 22
    eraseRow(y - 4, 22)
    if idx < #myRods then
      local rod = myRods[idx + 1]
      if idx == invSel then drawSelectionBox(5, y - 4, W - 10, 20) end
      local xOff = 10
      if rod.use then
        lcd.textColor(cGrn, cBlack); lcd.print(xOff, y, "[E]"); xOff = xOff + 22
      end
      lcd.textColor(rarityColor(rod.r), cBlack)
      lcd.print(xOff, y, rod.n .. " x" .. tostring(rod.q))
      local durT = ((rod.d or 0) == 0) and "INF" or (rod.curD .. "/" .. rod.d)
      local warn = ((rod.d or 0) > 0 and rod.curD < 10) and cDanger or cDim
      lcd.textColor(warn, cBlack)
      lcd.print(xOff, y + 10, "L:+" .. tostring(rod.l or 0) .. "%  D:" .. durT)
    end
  end

  if #myRods > maxLines then
    eraseRow(H - 22, 8)
    drawCenteredText(H - 22, (invSel + 1) .. "/" .. #myRods, cDim, 1)
  end
end

-- ── Inventory: charms ─────────────────────────────────────
local function step_charminv(now, btn)
  local was_full = need_full_redraw
  if need_full_redraw then
    lcd.fillScreen(cBlack)
    drawCenteredText(20, "MY CHARMS", cWhite, 1)
    lcd.rect(20, 32, W - 40, 1, cSep)
    drawHint("[OK] TOGGLE   [BACK] EXIT")
    if #myCharms == 0 then
      drawCenteredText(math.floor(H / 2), "(No charms)", cDim, 1)
    end
    need_full_redraw = false
  end

  if #myCharms == 0 then return end
  local maxLines = 5
  clampScroll(#myCharms, maxLines, btn)
  if btn == "ok" then toggleCharm(invSel); need_full_redraw = true; uni.delay(150); return end

  if not (was_full or btn == "up" or btn == "down") then return end

  for i = 0, maxLines - 1 do
    local idx = invScroll + i
    local y = 38 + i * 22
    eraseRow(y - 4, 22)
    if idx < #myCharms then
      local ch = myCharms[idx + 1]
      if idx == invSel then drawSelectionBox(5, y - 4, W - 10, 20) end
      local xOff = 10
      if ch.use then
        lcd.textColor(cGrn, cBlack); lcd.print(xOff, y, "[ON]")
      else
        lcd.textColor(cDim, cBlack); lcd.print(xOff, y, "[  ]")
      end
      xOff = xOff + 28
      lcd.textColor(rarityColor(ch.r), cBlack)
      lcd.print(xOff, y, ch.n .. " x" .. tostring(ch.q))
      local warn = (ch.curD < 20) and cDanger or cDim
      lcd.textColor(warn, cBlack)
      lcd.print(xOff, y + 10, "L:+" .. tostring(ch.l or 0) .. "%  D:" .. tostring(ch.curD) .. "/" .. tostring(ch.d))
    end
  end

  if #myCharms > maxLines then
    eraseRow(H - 22, 8)
    drawCenteredText(H - 22, (invSel + 1) .. "/" .. #myCharms, cDim, 1)
  end
end

-- ── Shop: rods ────────────────────────────────────────────
local function step_rodshop(now, btn)
  local was_full = need_full_redraw
  if need_full_redraw then
    lcd.fillScreen(cBlack)
    drawCenteredText(20, "ROD SHOP", cWhite, 1)
    lcd.rect(20, 32, W - 40, 1, cSep)
    drawCenteredText(45, "$ " .. fmtM(money), cGold, 1)
    drawHint("[OK] BUY   [BACK] EXIT")
    need_full_redraw = false
  end

  local maxLines = 5
  clampScroll(#rodDB, maxLines, btn)
  if btn == "ok" then buyRod(invSel); need_full_redraw = true; uni.delay(200); return end

  if not (was_full or btn == "up" or btn == "down") then return end

  for i = 0, maxLines - 1 do
    local idx = invScroll + i
    local y = 58 + i * 22
    eraseRow(y - 4, 22)
    if idx < #rodDB then
      local rb = rodDB[idx + 1]
      if idx == invSel then drawSelectionBox(5, y - 4, W - 10, 20) end
      lcd.textColor(rarityColor(rb.r), cBlack)
      lcd.print(10, y, rb.n)
      local durT = (rb.d == 0) and "INF" or tostring(rb.d)
      lcd.textColor(cDim, cBlack)
      lcd.print(10, y + 10, "L:+" .. tostring(rb.l) .. "% D:" .. durT)
      if rb.p > 0 then
        lcd.textColor(cGold, cBlack)
        local ps = "$" .. fmtM(rb.p)
        lcd.print(W - 5 - lcd.textWidth(ps), y, ps)
      else
        lcd.textColor(cGrn, cBlack)
        local fs = "FREE"
        lcd.print(W - 5 - lcd.textWidth(fs), y, fs)
      end
    end
  end
end

-- ── Shop: charms ──────────────────────────────────────────
local function step_charmshop(now, btn)
  local was_full = need_full_redraw
  if need_full_redraw then
    lcd.fillScreen(cBlack)
    drawCenteredText(20, "CHARM SHOP", cWhite, 1)
    lcd.rect(20, 32, W - 40, 1, cSep)
    drawCenteredText(45, "$ " .. fmtM(money), cGold, 1)
    drawHint("[OK] BUY   [BACK] EXIT")
    need_full_redraw = false
  end

  local maxLines = 5
  clampScroll(#charmDB, maxLines, btn)
  if btn == "ok" then buyCharm(invSel); need_full_redraw = true; uni.delay(200); return end

  if not (was_full or btn == "up" or btn == "down") then return end

  for i = 0, maxLines - 1 do
    local idx = invScroll + i
    local y = 58 + i * 22
    eraseRow(y - 4, 22)
    if idx < #charmDB then
      local ch = charmDB[idx + 1]
      if idx == invSel then drawSelectionBox(5, y - 4, W - 10, 20) end
      lcd.textColor(rarityColor(ch.r), cBlack)
      lcd.print(10, y, ch.n)
      lcd.textColor(cDim, cBlack)
      lcd.print(10, y + 10, "L:+" .. tostring(ch.l) .. "% D:" .. tostring(ch.d))
      lcd.textColor(cGold, cBlack)
      local ps = "$" .. fmtM(ch.p)
      lcd.print(W - 5 - lcd.textWidth(ps), y, ps)
    end
  end
end

-- ── Dispatch ──────────────────────────────────────────────
local steps = {
  title     = step_title,
  fish      = step_fish,
  inv       = step_inv,
  shop      = step_shop,
  fishinv   = step_fishinv,
  rodinv    = step_rodinv,
  charminv  = step_charminv,
  rodshop   = step_rodshop,
  charmshop = step_charmshop,
}

-- ── Init ──────────────────────────────────────────────────
loadAll()
if #myRods == 0 then
  table.insert(myRods, { n = "Bamboo Rod", r = 0, p = 0, d = 0, curD = 0, l = 0, q = 1, use = true })
  saveAll()
end

-- ── Main loop ─────────────────────────────────────────────
while true do
  local now = uni.millis()
  local btn = nav.btn()

  if btn == "back" then
    uni.beep(400, 50)
    if appState == "title" then break
    elseif appState == "fishinv"   then appState = "inv"
    elseif appState == "rodinv"    then appState = "inv"
    elseif appState == "charminv"  then appState = "inv"
    elseif appState == "rodshop"   then appState = "shop"
    elseif appState == "charmshop" then appState = "shop"
    elseif appState == "fish"      then appState = "title"
    elseif appState == "inv"       then appState = "title"
    elseif appState == "shop"      then appState = "title"
    end
    menuIdx = 0
    need_full_redraw = true
    btn = "none"
    uni.delay(150)
  end

  if exit_requested then break end

  steps[appState](now, btn)

  uni.delay(30)
end

if game_sp then game_sp:free() end
