-- HM Items Mod
-- Allows executing field HM moves when carrying the HM item and holding the requisite badge,
-- without requiring any Pokémon in the party to know the move.

local HM_MOVE_ITEMS = {
  CUT = "HM01",
  FLY = "HM02",
  SURF = "HM03",
  STRENGTH = "HM04",
  FLASH = "HM05",
  ROCK_SMASH = "HM06",
  WATERFALL = "HM07",
  DIVE = "HM08",
  WHIRLPOOL = "HM06", -- Gen 2 maps Whirlpool to HM06, Waterfall to HM07
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

local function hasGen1or2Item(save, itemKey)
  if not save or not save.inventory then return false end
  local inv = save.inventory
  if (inv[itemKey] or 0) > 0 then return true end
  local alt = "ITEM_" .. itemKey
  if (inv[alt] or 0) > 0 then return true end
  local stripped = itemKey:gsub("^HM0?", "HM_"):gsub("^HM0?", "HM")
  if (inv[stripped] or 0) > 0 then return true end
  return false
end

local function playerHasHmItem(save, session, data, moveKey)
  local itemKey = HM_MOVE_ITEMS[moveKey]
  if not itemKey then return false end

  -- Gen 2 special case: Waterfall is HM07 in Gen 2 (Whirlpool is HM06)
  if moveKey == "WATERFALL" then
    local isGen2 = false
    local FieldMovesGen2 = package.loaded["src.world.gen2.FieldMoves"]
    if FieldMovesGen2 and FieldMovesGen2.BADGE and FieldMovesGen2.BADGE.WHIRLPOOL then
      isGen2 = true
    end
    if isGen2 then itemKey = "HM07" end
  end

  -- Check Gen 3 first
  if hasGen3Item(save, session, itemKey) then return true end

  -- Check Gen 1 / 2
  if hasGen1or2Item(save, itemKey) then return true end

  return false
end

local function playerHasBadge(save, session, data, moveKey)
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

  -- 2) Gen 2 check via FieldMovesGen2.hasBadge
  local FieldMovesGen2 = package.loaded["src.world.gen2.FieldMoves"]
  if FieldMovesGen2 and FieldMovesGen2.hasBadge and FieldMovesGen2.BADGE then
    local badgeName = FieldMovesGen2.BADGE[moveKey]
    if badgeName then
      local ok, res = pcall(FieldMovesGen2.hasBadge, save, badgeName)
      if ok and res ~= nil then return res == true end
    end
  end

  -- 3) Gen 1 check via FieldDefaults / hmBadges
  local FieldDefaults = package.loaded["src.world.FieldDefaults"]
  local hmBadges = (FieldDefaults and data and FieldDefaults.constant(data, "hmBadges")) or {}
  local badgeEntry = hmBadges[moveKey]
  if badgeEntry and badgeEntry.badge and save and save.inventory then
    return (save.inventory[badgeEntry.badge] or 0) > 0 or save.inventory[badgeEntry.badge] == true
  end

  -- Direct save.player.badges lookup
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

  mod.hooks:wrap("fieldmove.eligibility", function(nextFn, moveId, ctx)
    -- 1) Vanilla / higher-priority check
    local mon = nextFn(moveId, ctx)
    if mon then return mon end

    -- 2) Normalize move
    local moveKey = normalizeMoveKey(moveId)
    if not moveKey then return nil end

    local party = ctx and ctx.party
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
    if not playerHasHmItem(save, session, data, moveKey) then
      return nil
    end

    -- 4) Check player possesses the required gym badge
    if not playerHasBadge(save, session, data, moveKey) then
      return nil
    end

    -- Both prerequisites satisfied: party Pokémon is eligible
    return actor
  end)
end
