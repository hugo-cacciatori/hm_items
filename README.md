# HM Items

A quality-of-life mod for Pokémon games running on the Love2D engine.

Allows triggering field HM moves (Cut, Fly, Surf, Strength, Flash, Rock Smash, Waterfall, Dive) directly from the overworld or context menus as long as you carry the corresponding HM item in your bag and have earned the necessary gym badge, without requiring any Pokémon in your party to learn or know the move.

## Supported Games

Supports all generations:
- **Generation 1:** Red, Blue, Yellow
- **Generation 2:** Gold, Silver, Crystal
- **Generation 3:** FireRed, LeafGreen, Ruby, Sapphire, Emerald

## Prerequisites

To perform a field HM move:
1. You must own the corresponding HM item in your inventory (e.g. `HM01`–`HM08`).
2. You must have earned the required gym badge for that field move in your game version.
3. You must have at least one Pokémon in your party (non-egg) to perform the action.

Your Pokémon do not need to learn the move or sacrifice a move slot. Save data is never modified.

## Building and Verification

Run tests headlessly:
```bash
python tools/test.py
python tools/package.py
python tools/test_package.py
python tools/test_installed.py
```
