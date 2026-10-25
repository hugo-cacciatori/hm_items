-- HM Items Mod
-- Allows executing field HM moves when carrying the HM item and holding the requisite badge,
-- without requiring any Pokémon in the party to know the move.

-- Gen 3 numbers its HMs; Gen 1 and Gen 2 name them after the move instead
-- (save.inventory["HM_CUT"], src/import/RomExtractor.lua), so Gen 2's Rock
-- Smash, a TM there, has no HM item and stays locked.
local GEN3_HM_ITEMS = {
  CUT = "HM01",
  FLY = "HM02",
  SURF = "HM03",
  STRENGTH = "HM04",
  FLASH = "HM05",
  ROCK_SMASH = "HM06",
  WATERFALL = "HM07",
  DIVE = "HM08",
}

local function normalizeMoveKey(moveId)
  if type(moveId) == "string" then
    local s = moveId:upper():gsub("%s+", "_"):gsub("%-", "_")
    if s == "ROCKSMASH" then return "ROCK_SMASH" end
    return s
  end
  if type(moveId) == "number" then
    -- Gen 3 numeric IDs
    local m = {
      [15] = "CUT",
      [19] = "FLY",
      [57] = "SURF",
      [70] = "STRENGTH",
      [148] = "FLASH",
      [249] = "ROCK_SMASH",
      [127] = "WATERFALL",
      [291] = "DIVE",
    }
    return m[moveId]
  end
  return nil
end

local function hasGen3Item(save, session, itemKey)
  -- 1) Save / Session bag check
  local bag = (session and session.bag) or (save and save.bag)
  local BagMod = package.loaded["src.core.game3.bag"]
  if bag and BagMod and BagMod.has then
    local ok, res = pcall(BagMod.has, bag, itemKey)
    if ok and res then return true end
  end

  if bag and bag.pockets then
    local tmPocket = bag.pockets.TM_CASE or bag.pockets.ITEMS
    if tmPocket then
      for _, slot in ipairs(tmPocket) do
        local idStr = tostring(slot.id or ""):upper()
        if idStr == itemKey or idStr == ("ITEM_" .. itemKey) or idStr == itemKey:gsub("^HM0?", "HM") then
          if (slot.qty or 0) > 0 or (slot.quantity or 0) > 0 or slot.qty == nil then
            return true
          end
        end
        local ItemsData = package.loaded["src.core.game3.items_data"]
        if ItemsData and ItemsData.toNumericId then
          local num = ItemsData.toNumericId(slot.id)
          local targetNum = ItemsData.toNumericId(itemKey)
          if num and targetNum and num == targetNum then
            return true
          end
        end
      end
    end
  end

  -- Host inventory fallback
  if save and save.inventory then
    if (save.inventory[itemKey] or 0) > 0 then return true end
    local alt = "ITEM_" .. itemKey
    if (save.inventory[alt] or 0) > 0 then return true end
  end

  return false
end

local function hasGen1or2Item(save, moveKey)
  local count = save and save.inventory and save.inventory["HM_" .. moveKey]
  return count ~= nil and count ~= false and count ~= 0
end

local function playerHasHmItem(generation, save, session, moveKey)
  if generation ~= 3 then return hasGen1or2Item(save, moveKey) end
  local itemKey = GEN3_HM_ITEMS[moveKey]
  return itemKey ~= nil and hasGen3Item(save, session, itemKey)
end

local function playerHasBadge(generation, save, session, data, moveKey)
  if generation == 1 then
    local FieldDefaults = require("src.world.FieldDefaults")
    local gate = (FieldDefaults.constant(data, "hmBadges") or {})[moveKey]
    if not gate or not gate.badge then return true end
    return save and save.inventory and save.inventory[gate.badge] and true or false
  end
  if generation == 2 then
    local FieldMovesGen2 = require("src.world.gen2.FieldMoves")
    return FieldMovesGen2.hasBadge(save, FieldMovesGen2.BADGE[moveKey])
  end

  -- 1) Gen 3 check via FieldMoves.hasBadge
  local FieldMovesGen3 = package.loaded["src.core.game3.field_moves"]
  if FieldMovesGen3 and FieldMovesGen3.hasBadge then
    local Space = package.loaded["src.core.game3.scripting.space"]
    local ctx = {
      save = save,
      session = session,
      store = Space and Space.store,
      ctx = Space and Space.ctx,
    }
    local ok, res = pcall(FieldMovesGen3.hasBadge, ctx, moveKey)
    if ok and res ~= nil then return res == true end
  end

  -- 2) Direct save.player.badges lookup
  if save and save.player and save.player.badges then
    local b = save.player.badges
    if b[moveKey] ~= nil then return b[moveKey] == true end
  end

  return false
end

local function selectFirstPartyMon(party)
  if not party then return nil end
  for _, mon in ipairs(party) do
    if mon and not mon.isEgg and not mon.egg then
      return mon
    end
  end
  return nil
end

return function(mod)
  if not (mod and mod.hooks and mod.hooks.wrap) then return end

  local generation = tonumber(mod.generation)
    or tonumber(mod.game and mod.game.generation)
    or tonumber(require("src.core.GameVersion").generation())

  mod.hooks:wrap("fieldmove.eligibility", function(nextFn, moveId, ctx)
    -- 1) Vanilla / higher-priority check
    local mon = nextFn(moveId, ctx)
    if mon then return mon end

    -- 2) Normalize move
    local moveKey = normalizeMoveKey(moveId)
    if not moveKey then return nil end

    -- Gen 1's ctx carries only save and data; its party lives on the save.
    local party = ctx and (ctx.party or (ctx.save and ctx.save.party))
    if not party or #party == 0 then return nil end

    -- Find first available non-egg mon in party
    local actor = selectFirstPartyMon(party)
    if not actor then return nil end

    local save = ctx and ctx.save
    local data = ctx and ctx.data
    local session = ctx and ctx.session
    if not session then
      local RuntimeG3 = package.loaded["src.core.game3.runtime"]
      if RuntimeG3 and RuntimeG3.getSession then session = RuntimeG3.getSession() end
    end

    -- 3) Check player possesses the corresponding HM item
    if not playerHasHmItem(generation, save, session, moveKey) then
      return nil
    end

    -- 4) Check player possesses the required gym badge
    if not playerHasBadge(generation, save, session, data, moveKey) then
      return nil
    end

    -- Both prerequisites satisfied: party Pokémon is eligible
    return actor
  end)
end
