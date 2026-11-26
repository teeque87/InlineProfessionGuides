# Inline Profession Guides

A World of Warcraft **Forever** addon that puts profession leveling guides into the game: the profession window
highlights what to craft next, a panel next to it says how far to go, where to learn missing recipes and what to buy, and vendors, trainers and tooltips mark what the guide still needs.

Covers Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking, Tailoring, Cooking and First Aid (1-300).

## In game

| Where | What you get |
|---|---|
| Profession window | Green border + "N to go" on the guide's current recipe (target skill - current skill) |
| Guide panel (right of the window) | Current step, routes (`[switch]`), alternatives (`[use]`), how to learn a missing recipe with `[map]` waypoints, skill-cap hint, guide notes, next step, shopping list with craft-or-buy advice and an Auctionator list button. Headings fold with a click. |
| Vendors / trainers | Colored border on guide patterns, materials and recipes (green = now, yellow = later, blue = alternative) |
| Tooltips | "Guide (Cooking): needed at 50", "Guide: buy 39 more for Tailoring 150-200" |

Commands: `/ipg` (status), `/ipg help`, `/ipg options`, `/ipg reset`, `/ipg dump`, `/ipg test <spellID>`.
Options: Game Menu > Options > AddOns > Inline Profession Guides.

Optional: **Auctionator** (prices, shopping lists), **TomTom** (arrow instead of the Blizzard map pin).
Open your bank once so the shopping list can count it.

## Install

1. Download `InlineProfessionGuides-<version>.zip` from the [latest release](https://github.com/teeque87/InlineProfessionGuides/releases/latest).
2. Extract it into `World of Warcraft\_forever_\Interface\AddOns\`, so you end up with
   `AddOns\InlineProfessionGuides\InlineProfessionGuides.toc`.
3. Restart the game (or log out to the character screen) and check that the addon is enabled under **AddOns**.

## Install (development)

The addon folder is linked into the game, so edits show up after `/reload`:

```powershell
New-Item -ItemType Junction -Path "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\InlineProfessionGuides" -Target "<repo>\InlineProfessionGuides"
```

New files in the TOC need a full game restart, not just `/reload`.

## Guide data

Addons can't go online, so the guide data ships pre-built in `InlineProfessionGuides/Data/*.lua`.

## Sources and credits

- Leveling routes: based on the Forever leveling guides at [wow-professions.com](https://www.wow-professions.com/forever)
- Reagents and NPC locations: [Wowhead](https://www.wowhead.com/forever) tooltips; NPC map pins from the guide's NPC pages
- Recipe sources (trainer, vendor, quest, reputation): [What's Training?](https://www.curseforge.com/wow/addons/whats-training)
  by Sveng, MIT License
