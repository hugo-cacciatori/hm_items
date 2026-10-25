package.path = "./?.lua;./?/init.lua;" .. package.path
love = {
  data = {
    compress = function(_, _, bytes, level) return deflate(bytes, level) end,
    decompress = function(_, _, bytes) return inflate(bytes) end,
  },
  graphics = {
    newQuad = function() return {} end,
    newImage = function() return { getDimensions = function() return 256, 256 end } end,
  },
}
local GameVersion = require("src.core.GameVersion")
GameVersion.set(TEST_VERSION)
assert(require("src.core.Version").engine == "0.3.96", "wrong installed engine")

local fs, overlay = {}, {}
function fs.read(p) return overlay[p] or fs_read(p) end
function fs.getInfo(p) return overlay[p] and { type = "file" } or fs_info(p) end
function fs.getDirectoryItems(p) return fs_list(p) end
function fs.load(p)
  local bytes = fs.read(p)
  return bytes and loadstring(bytes, "@" .. p)
end
function fs.write(p, bytes) overlay[p] = bytes return true end
function fs.createDirectory() return true end
fs.root = "."

local generation = GameVersion.generation()
local Loader = require("src.mods.Loader")
local game = { data = {} }

if generation == 3 then
  local Dataset = require("src.core.game3.dataset")
  Dataset.cacheRootOverride = CACHE_ROOT
  assert(Dataset.hydrate(game), "installed dataset did not hydrate")
else
  local dir = TEST_VERSION .. "/data/generated/"
  for _, name in ipairs({ "constants", "moves", "items", "pokemon", "type_chart" }) do
    local chunk = fs.load(dir .. name .. ".lua")
    if chunk then game.data[name] = chunk() end
  end
end

local loader = Loader.new({ fs = fs, generation = generation })
loader:load(game.data)
assert(#loader.errors == 0, table.concat(loader.errors, "\n"))
local mod = loader.mods.hm_items
assert(mod and mod.state == "loaded", "installed mod did not load for " .. TEST_VERSION)

local mon = {
  species = (generation == 3 and 16) or "PIDGEY",
  nickname = "BIRDY",
  moves = { { id = (generation == 3 and 33) or "TACKLE" } },
  hp = 20, maxHp = 20, level = 5,
}
local party = { mon }

if generation == 3 then
  local bag = {
    pockets = {
      TM_CASE = {
        { id = "HM01", qty = 1 },
        { id = "HM03", qty = 1 },
      }
    }
  }
  local save = { bag = bag, player = { badges = {} } }
  local session = { bag = bag, flags = {}, badges = {} }
  local ctxCut = { save = save, session = session, party = party, data = game.data }

  -- 1) Without badge -> nil
  local res1 = loader.hooks:call("fieldmove.eligibility", function() return nil end, "CUT", ctxCut)
  assert(res1 == nil, "CUT allowed without badge")

  -- Grant CUT badge
  if TEST_VERSION == "firered" or TEST_VERSION == "leafgreen" then
    session.flags[0x821] = true
    save.player.badges.CUT = true
  else
    session.flags[0x867] = true
    save.player.badges.CUT = true
  end

  -- 2) With HM01 and badge -> returns mon
  local res2 = loader.hooks:call("fieldmove.eligibility", function() return nil end, "CUT", ctxCut)
  assert(res2 ~= nil, "CUT refused with HM item and badge")

  -- 3) Missing HM item -> nil
  bag.pockets.TM_CASE[2] = nil
  local ctxSurf = { save = save, session = session, party = party, data = game.data }
  if TEST_VERSION == "firered" or TEST_VERSION == "leafgreen" then
    session.flags[0x824] = true
    save.player.badges.SURF = true
  else
    session.flags[0x86B] = true
    save.player.badges.SURF = true
  end
  local res3 = loader.hooks:call("fieldmove.eligibility", function() return nil end, "SURF", ctxSurf)
  assert(res3 == nil, "SURF allowed without HM03")

  -- Restore HM03
  bag.pockets.TM_CASE[2] = { id = "HM03", qty = 1 }
  local res4 = loader.hooks:call("fieldmove.eligibility", function() return nil end, "SURF", ctxSurf)
  assert(res4 ~= nil, "SURF refused with HM03 and badge")

  -- 4) Egg exclusion
  party[1].isEgg = true
  local resEgg = loader.hooks:call("fieldmove.eligibility", function() return nil end, "SURF", ctxSurf)
  assert(resEgg == nil, "Egg allowed to use field move")
  party[1].isEgg = false

  -- 5) Rollback restores vanilla refusal
  loader:_rollback("hm_items")
  local resRollback = loader.hooks:call("fieldmove.eligibility", function() return nil end, "CUT", ctxCut)
  assert(resRollback == nil, "Rollback did not restore vanilla refusal")

  print("PASS installed " .. TEST_VERSION .. ": HM field moves, badge checks, egg check, and rollback")
  return
end

-- Gen 1/2 inventories key HMs by move name; the installed item table must agree.
if generation ~= 3 then
  local items = game.data.items or {}
  assert(items.HM_CUT and items.HM_SURF, "installed items lack HM_CUT/HM_SURF for " .. TEST_VERSION)
  assert(generation ~= 2 or items.HM_ROCK_SMASH == nil, "Gen 2 has an HM_ROCK_SMASH item")
end

if generation == 1 then
  local inventory = { HM_CUT = 1, HM_SURF = 1 }
  local save = { inventory = inventory, player = { badges = {} } }
  local ctxCut = { save = save, party = party, data = game.data }

  local res1 = loader.hooks:call("fieldmove.eligibility", function() return nil end, "CUT", ctxCut)
  assert(res1 == nil, "CUT allowed without badge")

  inventory.CASCADEBADGE = 1
  save.player.badges.CUT = true
  local res2 = loader.hooks:call("fieldmove.eligibility", function() return nil end, "CUT", ctxCut)
  assert(res2 ~= nil, "CUT refused with HM item and badge")

  inventory.HM_SURF = nil
  inventory.SOULBADGE = 1
  save.player.badges.SURF = true
  local ctxSurf = { save = save, party = party, data = game.data }
  local res3 = loader.hooks:call("fieldmove.eligibility", function() return nil end, "SURF", ctxSurf)
  assert(res3 == nil, "SURF allowed without HM_SURF")

  inventory.HM_SURF = 1
  local res4 = loader.hooks:call("fieldmove.eligibility", function() return nil end, "SURF", ctxSurf)
  assert(res4 ~= nil, "SURF refused with HM_SURF and badge")

  loader:_rollback("hm_items")
  local resRollback = loader.hooks:call("fieldmove.eligibility", function() return nil end, "CUT", ctxCut)
  assert(resRollback == nil, "Rollback did not restore vanilla refusal")

  print("PASS installed " .. TEST_VERSION .. ": Gen 1 HM field moves and rollback")
  return
end

if generation == 2 then
  local inventory = { HM_CUT = 1, HM_SURF = 1 }
  local save = { inventory = inventory, player = { badges = {} } }
  local ctxCut = { save = save, party = party, data = game.data }

  local res1 = loader.hooks:call("fieldmove.eligibility", function() return nil end, "CUT", ctxCut)
  assert(res1 == nil, "CUT allowed without badge")

  save.player.badges.HIVE = true
  save.player.badges.CUT = true
  local res2 = loader.hooks:call("fieldmove.eligibility", function() return nil end, "CUT", ctxCut)
  assert(res2 ~= nil, "CUT refused with HM item and badge")

  inventory.HM_SURF = nil
  save.player.badges.FOG = true
  save.player.badges.SURF = true
  local ctxSurf = { save = save, party = party, data = game.data }
  local res3 = loader.hooks:call("fieldmove.eligibility", function() return nil end, "SURF", ctxSurf)
  assert(res3 == nil, "SURF allowed without HM_SURF")

  inventory.HM_SURF = 1
  local res4 = loader.hooks:call("fieldmove.eligibility", function() return nil end, "SURF", ctxSurf)
  assert(res4 ~= nil, "SURF refused with HM_SURF and badge")

  loader:_rollback("hm_items")
  local resRollback = loader.hooks:call("fieldmove.eligibility", function() return nil end, "CUT", ctxCut)
  assert(resRollback == nil, "Rollback did not restore vanilla refusal")

  print("PASS installed " .. TEST_VERSION .. ": Gen 2 HM field moves and rollback")
  return
end
