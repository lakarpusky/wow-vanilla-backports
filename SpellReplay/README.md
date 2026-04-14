# SpellReplay

A scrolling spell history display for **World of Warcraft 1.12.1 (Vanilla)**, backported from Oldsalt's TBC/WotLK addon. See every spell you cast in real time — icons scroll across the screen and speed up when spells pile up, making it easy to review your rotation at a glance.

---

## About

SpellReplay is a 1.12.1 backport of [Oldsalt's SpellReplay](https://github.com/Oldsalt0/SpellReplay), originally written for Smolderforge (TBC/WotLK). The original was itself inspired by the retail addon TrufiGCD, made for [Sbkzor](https://www.youtube.com/user/mopalol).

The backport replaces every WotLK-only API with vanilla-compatible equivalents — no SuperWoW, no libraries, no dependencies of any kind. Pure Lua 5.0 running on the base 1.12.1 client.

---

## Features

- **Scrolling spell icon strip** — icons appear as you cast and scroll across the frame in configurable direction and speed
- **Push speed** — the strip accelerates when spells stack up so nothing gets lost
- **Damage and heal overlays** — optional numbers on each icon showing hit, crit, or heal amount
- **Resist / miss / dodge / parry / block / immune overlays** — red cross and label on failed casts
- **Mana and energy gain display** — shows resource gains from spells like Life Tap or Thistle Tea
- **Auto-attack tracking** — melee and ranged auto-attacks shown with your equipped weapon icon
- **Druid form support** — bear and cat form auto-attacks use the correct form icon
- **Channeled spells** — tracked correctly including spells with no damage output (Mind Control, Drain Mana, Hypnotize, etc.)
- **Pet spell tracking** — pet casts shown with a PET label
- **Spell rank display** — show all ranks, rank 1 only, or hide ranks entirely
- **Icon border cropping** — removes the default icon border for a cleaner look
- **Frame scaling, locking, and dragging** — resize, lock position, or drag anywhere on screen
- **All settings saved across sessions**

---

## Installation

1. Download the latest release or clone this repository
2. Copy the `SpellReplay` folder into your addons directory:
   ```
   World of Warcraft/Interface/AddOns/SpellReplay/
   ```
3. Make sure the folder structure looks like this:
   ```
   SpellReplay/
   ├── SpellReplay.lua
   ├── SpellReplay.toc
   └── RedCross.tga
   ```
4. Log in and the addon loads automatically — type `/sr` to see all commands

---

## Slash Commands

Configure with `/sr` or `/spellreplay`:

| Command | Description |
|---|---|
| `/sr` | Show all commands |
| `/sr enable` | Toggle on/off |
| `/sr lock` | Toggle position lock |
| `/sr bg` | Toggle background visibility |
| `/sr dir` | Toggle scroll direction |
| `/sr scale <0.8-1.5>` | Frame scale |
| `/sr push <30-150>` | Push speed |
| `/sr base <0-100>` | Base scroll speed |
| `/sr cast <0-100>` | Casting scroll speed |
| `/sr spells <2-6>` | Number of spells shown |
| `/sr crop` | Toggle icon border crop |
| `/sr resists` | Toggle resist display |
| `/sr damage <off\|all\|crit>` | Damage numbers |
| `/sr heals <off\|all\|crit>` | Heal numbers |
| `/sr mana` | Toggle mana/energy gains |
| `/sr pet` | Toggle pet spells |
| `/sr ranks <off\|all\|r1>` | Spell rank display |
| `/sr white <off\|melee\|ranged\|both>` | Auto-attack display |
| `/sr reset` | Reset to defaults |
| `/sr status` | Show current settings |

---

## Usage

### Frame interaction
- **Drag** the frame to reposition it anywhere on screen
- **Right-click** the frame to toggle position lock
- Use `/sr lock` to lock or unlock via command

### Speed tuning
Three speed values control how the strip behaves:
- **Base speed** — how fast icons scroll when you are not casting
- **Cast speed** — scroll speed while a cast is in progress
- **Push speed** — burst speed applied when new icons enter behind existing ones

### Damage and heal numbers
Each overlay mode has three states: `off`, `all` (every hit), or `crit` (critical hits and heals only). Set them independently for damage and healing with `/sr damage` and `/sr heals`.

### Auto-attacks
Use `/sr white` to control which auto-attacks appear: `off`, `melee`, `ranged`, or `both`. Ranged auto-attacks (Auto Shot, Shoot, Wand) show your equipped ranged weapon icon. Melee auto-attacks show your main hand weapon icon, or the appropriate druid form icon in bear or cat form.

---

## Technical Notes

The original addon used WotLK APIs that don't exist in 1.12.1. Here's how each was replaced:

| WotLK API | Vanilla Replacement |
|---|---|
| `UNIT_SPELLCAST_SUCCEEDED` | Hooks on `UseAction`, `CastSpellByName`, `CastSpell` |
| `GetSpellInfo(spellID)` | Spellbook scanning (`GetSpellName` + `GetSpellTexture`) |
| `COMBAT_LOG_EVENT_UNFILTERED` | `CHAT_MSG_SPELL_*` / `CHAT_MSG_COMBAT_*` string parsing |
| `UnitGUID()` | `UnitName()` |
| `UnitCastingInfo()` / `UnitChannelInfo()` | `SPELLCAST_START/STOP/CHANNEL_START/STOP` events |
| `InterfaceOptions` panel | `/sr` slash commands |
| `select()`, `...`, `table.maxn` | Manual implementations for Lua 5.0 |

---

## Credits

- **[Oldsalt](https://github.com/Oldsalt0)** — original TBC/WotLK addon that this backport is based on
- **[Sbkzor](https://www.youtube.com/user/mopalol)** — the addon was originally made for him as a backport of the retail TrufiGCD

---

## Author

**lakarpusky** — [@_akarpusky](https://x.com/_akarpusky)

Part of the [wow-vanilla-backports](https://github.com/lakarpusky/wow-vanilla-backports) collection.
