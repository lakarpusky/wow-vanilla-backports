# SpellReplay

Backport of [Oldsalt's SpellReplay](https://github.com/Oldsalt0/SpellReplay) from TBC/WotLK to vanilla 1.12.1.

Displays your casted spells as scrolling icons in real time — speeds up when spells pile up, making it easy to review your rotation.

Originally made for [Sbkzor](https://www.youtube.com/user/mopalol) as a backport of the retail addon TrufiGCD.

<!-- ![SpellReplay in action](screenshots/demo.gif) -->

## Features

- Scrolling spell icon strip with configurable speed and direction
- Damage / heal number overlays (all or crits only)
- Resist / miss / dodge / parry / block / immune overlays with red cross
- Mana and energy gain display
- Auto Shot and ranged auto-attacks with weapon icon
- Melee auto-attacks with weapon icon and druid form support
- Pet spell tracking with PET label
- Spell rank display (all ranks or rank 1 only)
- Icon border cropping
- Frame scaling, locking, and dragging
- All settings saved across sessions

## No dependencies

Pure Lua 5.0. No libraries, no SuperWoW, no nothing.

## Install

Copy the `SpellReplay` folder into `Interface\AddOns\` so the path is:

```
Interface\AddOns\SpellReplay
```

## Commands

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

Right-click the frame to toggle lock.

## Technical notes

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

## Credits

- **[Oldsalt](https://github.com/Oldsalt0)** — original addon
- **[Gabo Montero](https://github.com/lakarpusky)** — vanilla backport
