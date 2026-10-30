# HM Items

A quality-of-life mod for Pokémon games running on the Love2D engine.

Allows triggering field HM moves (Cut, Fly, Surf, Strength, Flash, Rock Smash, Waterfall, Dive) directly from the overworld or context menus as long as you carry the corresponding HM item in your bag, have earned the necessary gym badge, and have a Pokémon in your party that could learn the move, without it having to know the move.

## Supported Games

Supports all generations:
- **Generation 1:** Red, Blue, Yellow
- **Generation 2:** Gold, Silver, Crystal
- **Generation 3:** FireRed, LeafGreen, Ruby, Sapphire, Emerald

## Prerequisites

To perform a field HM move:
1. You must own the corresponding HM item in your inventory (e.g. `HM01`–`HM08`).
2. You must have earned the required gym badge for that field move in your game version.
3. A Pokémon in your party (not an egg) must be able to learn the move from its HM. The first such Pokémon in your party performs it.

That Pokémon does not need to actually learn the move or give up a move slot. Save data is never modified.

## Development

The repository holds the mod's source and its headless test suites. Releases are built and verified with the project's build tooling: the suites run on the packaged zip in an external engine copy, then against a staged copy of the installed game and its imported data. Install the release zip.
