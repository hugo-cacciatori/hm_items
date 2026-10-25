package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local Sdk = require("tests.modkit.sdk")
local GameVersion = require("src.core.GameVersion")
local Runtime = require("src.mods.Runtime")
local Logger = require("src.core.Logger")
if Logger.warn then Logger.warn = function() end end

local total = 0
local function check(value, message)
  total = total + 1
  assert(value, message)
end

-- ------------------------------------------------------------ 1. Profiles
local PROFILES = {
  { version = "firered", gen = 3 },
  { version = "leafgreen", gen = 3 },
  { version = "ruby", gen = 3 },
  { version = "sapphire", gen = 3 },
  { version = "emerald", gen = 3 },
  { version = "red", gen = 1 },
  { version = "blue", gen = 1 },
  { version = "yellow", gen = 1 },
  { version = "gold", gen = 2 },
  { version = "silver", gen = 2 },
  { version = "crystal", gen = 2 },
}

local function sampleData(gen)
  if gen == 3 then
    local d = Sdk.gen3Data()
    return d
  end
  return {
    field = {
      hmBadges = {
        CUT = { badge = "CASCADEBADGE" },
        FLY = { badge = "THUNDERBADGE" },
        SURF = { badge = "SOULBADGE" },
        STRENGTH = { badge = "RAINBOWBADGE" },
        FLASH = { badge = "BOULDERBADGE" },
      }
    },
    pokemon = {
      PIDGEY = { name = "PIDGEY", id = "PIDGEY" },
    }
  }
end

-- ------------------------------------------------------------ 2. Run across profiles
for _, p in ipairs(PROFILES) do
  GameVersion.set(p.version)
  Runtime.reset()

  local mon = {
    species = (p.gen == 3 and 16) or "PIDGEY",
    nickname = "BIRDY",
    moves = { { id = (p.gen == 3 and 33) or "TACKLE" } }, -- Tackle
    hp = 20, maxHp = 20, level = 5,
  }
  local party = { mon }

  local bag = {}
  if p.gen == 3 then
    bag = {
      pockets = {
        TM_CASE = {
          { id = "HM01", qty = 1 },
          { id = "HM03", qty = 1 },
        }
      }
    }
  end

  local inventory = {
    HM01 = 1,
    HM03 = 1,
  }

  local save = {
    party = party,
    bag = bag,
    inventory = inventory,
    player = { badges = {} },
  }
  local session = {
    party = party,
    bag = bag,
    flags = {},
    badges = {},
  }

  local opts = {
    version = p.version,
    generation = p.gen,
    data = sampleData(p.gen),
    save = save,
    session = session,
  }

  local run = Sdk.loadMod(MOD_PATH, opts)
  check(#run.errors == 0, p.version .. ": load error: " .. table.concat(run.errors, "\n"))
  check(run.mod and run.mod.state == "loaded", p.version .. ": mod loaded")

  local loader = run.loader
  local ctxCut = { save = save, session = session, party = party, data = opts.data }

  -- Case A: No badge owned -> fieldmove.eligibility returns nil
  local resNoBadge = loader.hooks:call("fieldmove.eligibility", function() return nil end, "CUT", ctxCut)
  check(resNoBadge == nil, p.version .. ": refused when badge is missing")

  -- Grant CUT badge
  if p.gen == 3 then
    if p.version == "firered" or p.version == "leafgreen" then
      session.flags[0x821] = true -- FLAG_BADGE02_GET (Cascade)
      save.player.badges.CUT = true
    else
      -- RSE Stone Badge (Cut)
      session.flags[0x867] = true -- FLAG_BADGE01_GET
      save.player.badges.CUT = true
    end
  elseif p.gen == 2 then
    save.player.badges.HIVE = true -- Hive Badge for Cut in Gen 2
    save.player.badges.CUT = true
  else
    -- Gen 1
    inventory.CASCADEBADGE = 1
    save.player.badges.CUT = true
  end

  -- Case B: Has HM01 AND has Cut Badge -> fieldmove.eligibility returns party mon!
  local resCutOk = loader.hooks:call("fieldmove.eligibility", function() return nil end, "CUT", ctxCut)
  check(resCutOk ~= nil, p.version .. ": accepts CUT when HM item and badge are owned")

  -- Case C: Has Surf Badge but missing HM item -> returns nil
  if p.gen == 3 then
    if p.version == "firered" or p.version == "leafgreen" then
      session.flags[0x824] = true -- Soul Badge
      save.player.badges.SURF = true
    else
      session.flags[0x86B] = true -- Balance Badge
      save.player.badges.SURF = true
    end
  elseif p.gen == 2 then
    save.player.badges.FOG = true -- Fog Badge
    save.player.badges.SURF = true
  else
    inventory.SOULBADGE = 1
    save.player.badges.SURF = true
  end

  -- Remove HM03
  if p.gen == 3 then
    bag.pockets.TM_CASE[2] = nil
  end
  inventory.HM03 = nil

  local ctxSurf = { save = save, session = session, party = party, data = opts.data }
  local resSurfNoItem = loader.hooks:call("fieldmove.eligibility", function() return nil end, "SURF", ctxSurf)
  check(resSurfNoItem == nil, p.version .. ": refused when HM item is missing even if badge is owned")

  -- Restore HM03
  if p.gen == 3 then
    bag.pockets.TM_CASE[2] = { id = "HM03", qty = 1 }
  end
  inventory.HM03 = 1

  -- Now Surf succeeds
  local resSurfOk = loader.hooks:call("fieldmove.eligibility", function() return nil end, "SURF", ctxSurf)
  check(resSurfOk ~= nil, p.version .. ": accepts SURF when both HM item and badge are owned")

  -- Case D: Egg mon exclusion (party only has eggs)
  party[1].isEgg = true
  party[1].egg = true
  local resEgg = loader.hooks:call("fieldmove.eligibility", function() return nil end, "SURF", ctxSurf)
  check(resEgg == nil, p.version .. ": egg is not eligible to perform field move")
  party[1].isEgg = false
  party[1].egg = false

  -- Case E: Rollback cleanly restores vanilla refusal
  loader:_rollback("hm_items")
  local resRollback = loader.hooks:call("fieldmove.eligibility", function() return nil end, "CUT", ctxCut)
  check(resRollback == nil, p.version .. ": rollback restores vanilla refusal")
end

print(string.format("Integration suite passed: %d assertions across %d profiles", total, #PROFILES))
