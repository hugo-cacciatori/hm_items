-- HM Items Mod
-- Allows executing field HM moves when carrying the HM item and holding the requisite badge,
-- without requiring any Pokémon in the party to know the move.
-- The logic lives in the bundled `field_moves` lib (lib/field_moves/); this file only wires it.
return function(mod)
  local use = assert(load(assert(mod:read("lib/init.lua"), "missing lib/init.lua"), "@lib/init.lua"))(mod)
  use("field_moves").install(mod)
end
