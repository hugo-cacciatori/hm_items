# Changelog

All notable changes to the `hm_items` mod will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-10-25

### Added
- Native field HM item execution across Generation 1, Generation 2, and Generation 3 games without requiring any Pokémon in the party to know the move.
- Strict badge and HM possession validation:
  - Gen 1: Cut (HM01 / Cascade Badge), Fly (HM02 / Thunder Badge), Surf (HM03 / Soul Badge), Strength (HM04 / Rainbow Badge), Flash (HM05 / Boulder Badge).
  - Gen 2: Cut (HM01 / Hive Badge), Fly (HM02 / Storm Badge), Surf (HM03 / Fog Badge), Strength (HM04 / Plain Badge), Flash (HM05 / Zephyr Badge), Whirlpool (HM06 / Glacier Badge), Waterfall (HM07 / Rising Badge).
  - Gen 3: Cut (HM01 / Cascade or Stone Badge), Fly (HM02 / Thunder or Feather Badge), Surf (HM03 / Soul or Balance Badge), Strength (HM04 / Rainbow or Heat Badge), Flash (HM05 / Boulder or Knuckle Badge), Rock Smash (HM06 / Marsh or Dynamo Badge), Waterfall (HM07 / Volcano or Rain Badge), Dive (HM08 / Earth or Mind Badge).
- Full compatibility with vanilla move knowledge: if a Pokémon in the party already knows the required HM move, the native path executes with zero interference.
- Robust party actor selection: assigns field move actions to the first healthy, non-egg Pokémon in the party.
- Clean rollback: removing or disabling the mod immediately restores vanilla behavior without touching save files.
