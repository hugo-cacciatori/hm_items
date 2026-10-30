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
      PIDGEY = { name = "PIDGEY", id = "PIDGEY", tmhm = { "FLY" } },
      BULBASAUR = { name = "BULBASAUR", id = "BULBASAUR", tmhm = { "CUT" } },
      SQUIRTLE = { name = "SQUIRTLE", id = "SQUIRTLE", tmhm = { "SURF", "STRENGTH" } },
    }
  }
end

-- Gen 3 learnsets come from the engine's TM/HM table (the import's data, exercised by the release gate); here a
-- stand-in with the same answers: Pidgey (16) learns Fly, Bulbasaur (1) Cut, Squirtle (7) Surf and Strength.
local Pokemon3 = require("src.core.game3.pokemon")
local realCanLearn = Pokemon3.canLearnTmItem
local LEARNS = { [16] = { HM02 = true }, [1] = { HM01 = true }, [7] = { HM03 = true, HM04 = true } }
Pokemon3.canLearnTmItem = function(species, item) return (LEARNS[tonumber(species)] or {})[item] == true end

-- ------------------------------------------------------------ 2. Run across profiles
for _, p in ipairs(PROFILES) do
  GameVersion.set(p.version)
  Runtime.reset()

  local function member(species3, species, name)
    return { species = (p.gen == 3 and species3) or species, nickname = name,
             moves = { { id = (p.gen == 3 and 33) or "TACKLE" } }, hp = 20, maxHp = 20, level = 5 }
  end
  -- nobody knows an HM; only Bulbasaur can learn Cut and only Squirtle Surf
  local party = { member(16, "PIDGEY", "BIRDY"), member(1, "BULBASAUR", "BULBA"), member(7, "SQUIRTLE", "SQUIRT") }

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

  -- Gen 3 numbers its HMs; Gen 1/2 inventories name them after the move.
  local inventory = (p.gen == 3) and { HM01 = 1, HM03 = 1 }
    or { HM_CUT = 1, HM_SURF = 1 }

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
  -- Gen 3 badges live in the script flag store the engine's badge check reads first (as in the game)
  local Space3, Flags3
  if p.gen == 3 then
    Space3, Flags3 = require("src.core.game3.scripting.space"), require("src.core.game3.scripting.flags")
    Space3.store = Flags3.newStore()
  end
  local function badge3(flag)
    session.flags[flag] = true
    if Space3 then Flags3.setFlag(Space3.store, nil, flag, true) end
  end
  check(run.mod and run.mod.state == "loaded", p.version .. ": mod loaded")

  local loader = run.loader
  local ctxCut = { save = save, session = session, party = party, data = opts.data }

  -- Case A: No badge owned -> fieldmove.eligibility returns nil
  local resNoBadge = loader.hooks:call("fieldmove.eligibility", function() return nil end, "CUT", ctxCut)
  check(resNoBadge == nil, p.version .. ": refused when badge is missing")

  -- Grant CUT badge
  if p.gen == 3 then
    -- each version's own badge flag for Cut (Cascade in FRLG, Stone in RSE), as the engine maps it
    badge3(require("src.core.game3.field_moves").badgeFlag("CUT"))
    save.player.badges.CUT = true
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
  check(resCutOk == party[2], p.version .. ": CUT with the HM item and badge is performed by the one Pokémon able to learn it")
  local onlyPidgey = { party[1] }
  local resNobody = loader.hooks:call("fieldmove.eligibility", function() return nil end, "CUT",
    { save = save, session = session, party = onlyPidgey, data = opts.data })
  check(resNobody == nil, p.version .. ": refused when no party Pokémon can learn CUT")

  -- Case C: Has Surf Badge but missing HM item -> returns nil
  if p.gen == 3 then
    badge3(require("src.core.game3.field_moves").badgeFlag("SURF")) -- Soul (FRLG) / Balance (RSE)
    save.player.badges.SURF = true
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
  inventory.HM03, inventory.HM_SURF = nil, nil

  local ctxSurf = { save = save, session = session, party = party, data = opts.data }
  local resSurfNoItem = loader.hooks:call("fieldmove.eligibility", function() return nil end, "SURF", ctxSurf)
  check(resSurfNoItem == nil, p.version .. ": refused when HM item is missing even if badge is owned")

  -- Restore HM03
  if p.gen == 3 then
    bag.pockets.TM_CASE[2] = { id = "HM03", qty = 1 }
  end
  if p.gen == 3 then inventory.HM03 = 1 else inventory.HM_SURF = 1 end

  -- Now Surf succeeds
  local resSurfOk = loader.hooks:call("fieldmove.eligibility", function() return nil end, "SURF", ctxSurf)
  check(resSurfOk == party[3], p.version .. ": SURF is performed by the Pokémon able to learn it")

  -- Case D: an egg never performs, even when its species could learn the move
  party[3].isEgg = true
  party[3].egg = true
  local resEgg = loader.hooks:call("fieldmove.eligibility", function() return nil end, "SURF", ctxSurf)
  check(resEgg == nil, p.version .. ": egg is not eligible to perform field move")
  party[3].isEgg = false
  party[3].egg = false

  -- Case E: Rollback cleanly restores vanilla refusal
  loader:_rollback("hm_items")
  local resRollback = loader.hooks:call("fieldmove.eligibility", function() return nil end, "CUT", ctxCut)
  check(resRollback == nil, p.version .. ": rollback restores vanilla refusal")
end

Pokemon3.canLearnTmItem = realCanLearn

-- ------------------------------------------------------------ 3. Real engine call paths
-- The cases above call the hook directly with a hand-built ctx. These go
-- through the engine's own callers, so they see the ctx the game really passes.

local function setUpvalue(fn, name, value)
  for i = 1, math.huge do
    local upName = debug.getupvalue(fn, i)
    if not upName then error("no upvalue " .. name) end
    if upName == name then debug.setupvalue(fn, i, value); return end
  end
end

-- A Squirtle that knows only Tackle; learnsets below are stand-ins for the game data the engine passes.
local function knowsTackle()
  return { species = "SQUIRTLE", hp = 20, maxHp = 20, level = 5, moves = { { id = "TACKLE" } } }
end
local LEARNSETS = { pokemon = { SQUIRTLE = { tmhm = { "SURF", "STRENGTH", "WHIRLPOOL" } } } }

-- Gen 1: OverworldState:partyKnows passes only { save, data }.
local OverworldState = require("src.world.OverworldController")
for _, version in ipairs({ "red", "blue", "yellow" }) do
  GameVersion.set(version)
  Runtime.reset()
  local mon = knowsTackle()
  local save = { party = { mon }, inventory = {} }
  local function partyKnows(run, move)
    setUpvalue(OverworldState.partyKnows, "Game", { save = save, data = LEARNSETS })
    return OverworldState.partyKnows({}, move)
  end

  local vanilla = Sdk.loadNone({ generation = 1 })
  save.inventory = { HM_CUT = 1, CASCADEBADGE = 1 }
  check(partyKnows(vanilla, "CUT") == nil, version .. ": vanilla refuses CUT without a mon that knows it")
  vanilla.release()

  local run = Sdk.loadMod(MOD_PATH, { generation = 1 })
  check(#run.errors == 0, version .. ": load error: " .. table.concat(run.errors, "\n"))
  save.inventory = { CASCADEBADGE = 1 }
  check(partyKnows(run, "CUT") == nil, version .. ": engine path refuses CUT without HM_CUT")
  save.inventory = { HM_CUT = 1 }
  check(partyKnows(run, "CUT") == nil, version .. ": engine path refuses CUT without CASCADEBADGE")
  save.inventory = { HM_CUT = 1, CASCADEBADGE = 1 }
  check(partyKnows(run, "CUT") == nil, version .. ": engine path refuses CUT: Squirtle cannot learn it")
  save.inventory = { HM_SURF = 1, SOULBADGE = 1 }
  check(partyKnows(run, "SURF") == mon, version .. ": engine path grants SURF from the bag")
  run.release()
end

-- Gen 2: FieldMoves.partyMoveUser and the overworld try* functions.
local FieldMoves2 = require("src.world.gen2.FieldMoves")
for _, version in ipairs({ "gold", "silver", "crystal" }) do
  GameVersion.set(version)
  Runtime.reset()
  local mon = knowsTackle()
  local party = { mon }
  local save = {
    party = party,
    inventory = { HM_STRENGTH = 1, HM_WHIRLPOOL = 1 },
    player = { badges = { PLAIN = true, GLACIER = true } },
  }
  local fieldCtx = { party = party, save = save, data = LEARNSETS }

  local vanilla = Sdk.loadNone({ generation = 2 })
  check(not FieldMoves2.tryStrengthOW(fieldCtx).ok, version .. ": vanilla refuses STRENGTH without a mon that knows it")
  vanilla.release()

  local run = Sdk.loadMod(MOD_PATH, { generation = 2 })
  check(#run.errors == 0, version .. ": load error: " .. table.concat(run.errors, "\n"))
  local strength = FieldMoves2.tryStrengthOW(fieldCtx)
  check(strength.ok and strength.mon == mon, version .. ": engine path grants STRENGTH from the bag")
  check(FieldMoves2.partyMoveUser(party, "WHIRLPOOL", fieldCtx) == mon, version .. ": engine path grants WHIRLPOOL from HM_WHIRLPOOL")
  check(FieldMoves2.partyMoveUser(party, "ROCK_SMASH", fieldCtx) == nil, version .. ": HM_WHIRLPOOL does not unlock ROCK_SMASH (a TM in Gen 2)")
  save.player.badges.PLAIN = nil
  check(not FieldMoves2.tryStrengthOW(fieldCtx).ok, version .. ": engine path refuses STRENGTH without PLAINBADGE")
  run.release()
end

print(string.format("Integration suite passed: %d assertions across %d profiles", total, #PROFILES))
