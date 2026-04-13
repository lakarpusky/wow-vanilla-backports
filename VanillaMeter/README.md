# VanillaMeter

A modern DPS and healing meter for **World of Warcraft 1.12.1 (Vanilla)**, heavily inspired by [Details! Damage Meter](https://www.curseforge.com/wow/addons/details). Built from scratch for TurtleWoW and compatible vanilla clients.

---

## About

VanillaMeter is my personal take on what a DPS and healing meter should feel and look like in a vanilla client — clean, readable, and modern in spirit without requiring anything beyond the base 1.12.1 API.

This is **not a competitor** to any existing vanilla meter. Addons like [DPSMate](https://github.com/Athos1972/DPSMate) and [ShaguDPS](https://gitlab.com/shagu/ShaguDPS) have been serving the community for years and are excellent. VanillaMeter exists as a different take on the same problem — one focused on a modern UI feel inspired by Details! — not as a replacement for either of them.

---

## Features

- **Real-time DPS and healing tracking** for players and pets in your group or raid
- **Effective healing + overheal tracking** — healing bars display effective / raw split with HPS based on effective healing; tooltip shows Total, Effective %, and Overheal % per healer
- **Dual tab system** — open Damage Done and Healing Done simultaneously, switch between them, or detach either into an independent floating window
- **Class-colored bars** with class icons pulled from the game client
- **Spell breakdown tooltip** — hover any bar to see a full spell-by-spell breakdown with percentages
- **Segment tracking** — current fight and overall session data tracked independently
- **Pet merging** — pet damage optionally merged into owner totals
- **Transparent mode** — toggle full window transparency while keeping tabs readable
- **Resizable and draggable** — resize width and height within defined min/max bounds, drag anywhere on screen
- **Detachable windows** — detach any mode into a standalone floating window with its own reset and report controls
- **Report to chat** — send current meter results to Guild, Party, or Raid chat via right-click on the settings icon
- **Auto-reset** — optionally reset data automatically at the start of each new combat encounter
- **Locale-independent parsing** — uses GlobalStrings constants, works on all language clients

---

## Installation

1. Download the latest release or clone this repository
2. Copy the `VanillaMeter` folder into your addons directory:
   ```
   World of Warcraft/Interface/AddOns/VanillaMeter/
   ```
3. Make sure the folder structure looks like this:
   ```
   VanillaMeter/
   ├── core/
   │   ├── core.lua
   │   ├── combat.lua
   │   ├── data.lua
   │   └── parser.lua
   ├── ui/
   │   ├── bars.lua
   │   ├── config.lua
   │   ├── detach.lua
   │   ├── tabs.lua
   │   └── window.lua
   ├── textures/
   │   └── BantoBar.tga
   └── VanillaMeter.toc
   ```
4. Log in and type `/vm` to open the meter

---

## Slash Commands

| Command | Description |
|---|---|
| `/vm` | Toggle the meter window |
| `/vm reset` | Reset all current data |
| `/vm lock` | Toggle window lock (prevents moving) |
| `/vm autoreset` | Toggle auto-reset on new combat |
| `/vm config` | Open the settings panel |

---

## Usage

### Tabs
- **Left-click** a tab to switch between Damage Done and Healing Done
- **Right-click** a tab to switch its mode or detach it into a floating window
- Click **`+`** to add a second tab for the other mode
- **Left-click** the gear icon (⚙) to open settings
- **Right-click** the gear icon to report current results to chat

### Detached Windows
- Detached windows are independent — they have their own RESET button and right-click report menu
- Detached windows open at the same size as the main window
- Close a detached window with the `x` button in its title bar

### Settings Panel
| Toggle | Description |
|---|---|
| Auto-Reset | Resets segment data at the start of each new combat |
| Track All | Track all nearby units, not just group members |
| Merge Pets | Merge pet damage/healing into owner totals |
| Lock Window | Prevents the window from being moved or resized |
| Show Rank | Shows rank numbers on each bar |
| Transparent | Makes the window background fully transparent |

The **RESET** section in settings resets all data across all windows and tabs, including detached ones — different from the title bar RESET which only resets the current tab.

---

## Resetting Saved Variables

If you update VanillaMeter and want to apply new defaults cleanly, run this in-game:

```
/run VanillaMeterDB = nil; ReloadUI()
```

---

## Technical Notes

- **Parser:** Uses GlobalStrings-based pattern matching — locale-independent and compatible with all 1.12.1 clients
- **Segments:** `[0]` = overall session, `[1]` = current fight
- **Combat time:** Tracked per actor with a 3.5s gap threshold to handle out-of-combat periods accurately
- **Effective healing:** Calculated against target's missing health at the time of each heal event. Healing bars rank and rate by effective healing, not raw total — a healer who overheals ranks lower than one who lands the same raw numbers more efficiently. Bar value format: `effective / raw (HPS)`. Tooltip shows Total, Effective (%), and Overheal (%) with colour coding.

---

## Credits

- **[Details! Damage Meter](https://www.curseforge.com/wow/addons/details)** by Tercioo — visual design inspiration, layout concepts, and UX approach that shaped what VanillaMeter aims to feel like
- **[ShaguDPS](https://github.com/shagu/ShaguDPS)** by shagu — the GlobalStrings pattern-sanitization approach used in the combat log parser is directly based on ShaguDPS's proven method for locale-independent 1.12.1 parsing
- **[DPSMate](https://github.com/tdymel/DPSMate)** by tdymel — referenced for combat event handling patterns and segment management concepts in vanilla

All original work and credit belongs to their respective authors. VanillaMeter builds on these ideas with full respect for the community that made them possible.

---

## Author

**lakarpusky** — [@_akarpusky](https://x.com/_akarpusky)

Part of the [wow-vanilla-backports](https://github.com/lakarpusky/wow-vanilla-backports) collection.
