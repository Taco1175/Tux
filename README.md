# TUX

> *"The deep is calling."*

TUX is a 2D 8-bit dungeon crawler roguelike with online co-op for 1–4 players. Four penguin siblings descend through corrupted ocean ruins to rescue their missing parents — and discover the sin their colony has been hiding for a hundred years.

Built in **Godot 4** with GDScript.

---

## The Story

The invasion came without warning.

Sea creatures — crabs, eels, jellyfish, sharks — surged from the ocean and flooded the penguin colony's surface world. Corrupted by something ancient and unseen, they moved with purpose. They took things. They took *people*.

Among the missing: two colony elders. A mother and a father.

Their four children — siblings, each very different, each with their own reasons — gear up and dive in after them.

**What they expect:** a rescue mission.

**What they find:** the dungeon is full of the colony's history. Murals. Records. A cage built a century ago to hold something enormous and alive. The deeper they go, the more the story changes.

**What waits at the bottom:** their parents. Alive. Kneeling before a God that has been screaming in the dark for a hundred years.

And a choice none of them are ready to make.

---

## The Four Siblings

| Character | Class | Species | Personality |
|---|---|---|---|
| **Emperor** | Warrior | Emperor Penguin | The oldest. Overprotective. Secretly the most scared. High HP, shield bash, becomes a wall late-game. |
| **Gentoo** | Rogue | Gentoo Penguin | The chaotic middle sibling. "Fine, I'll do it myself." Fastest in the party, crits brutally, dies in two hits. |
| **Little Blue** | Support | Little Blue Penguin | The peacekeeper. Balanced. Heals allies. Snaps exactly once at low HP — and becomes something frightening. |
| **Macaroni** | Mage | Macaroni Penguin | The youngest. Treated like a baby. Unnerving calm. Glass cannon with devastating AoE. Gets *more* powerful the lower her HP. |

Each sibling has a **unique passive ability**, a **primary attack**, and a **secondary skill**. Stats and level-up gains differ meaningfully — Macaroni at level 15 is not the same game as Emperor at level 15.

---

## The World

The dungeon is **hybrid-structured**: floor-by-floor descent, but each zone is interconnected with shortcuts, locked doors, and optional paths. Find the shortcut before the long route. Or find the secret room that the long route hides.

| Zone | Theme | Boss |
|---|---|---|
| **Flooded Ruins** | Crumbling stone, rising water, crab patrols | — |
| **Coral Crypts** | Purple coral, bioluminescent traps, stinging swarms | The Crab Warlord |
| **Abyssal Trench** | Crushing dark, anglerfish lures, shark ambushes | The Leviathan |
| **The God's Sanctum** | Ancient, wrong, quiet | The Drowned God |

Each zone has **lore mural rooms** — optional rooms with no enemies and one stone wall covered in history. The colony's history. The real one.

---

## The Enemies

### Crustacean Knights
Armored, methodical, high defense. They don't chase you. They herd you.
- *Crab Grunt* — the cannon fodder
- *Crab Knight* — armored, hits harder
- *Lobster Warlord* — mini-boss, will not stop

### Deep Sea Predators
Fast, aggressive, built to punish mistakes.
- *Eel Scout* — zips through corridors, strikes and retreats
- *Anglerfish* — short aggro range, massive damage when it closes
- *Shark Brute* — charges in a straight line, high HP

### Stinging Swarms
Ranged, status-focused, annoying in the way that costs you the run.
- *Jellyfish Drifter* — slow, low damage, flees when hurt, poisons
- *Urchin Roller* — rolls at you, leaves a damage trail
- *Anemone Trap* — stationary, long range, high damage

### Bosses
- **The Crab Warlord** *(Zone 2)* — monologues at length. Drops guaranteed Rare+.
- **The Leviathan** *(Zone 3)* — multi-phase. The music changes.
- **The Drowned God** *(Final)* — does not want to fight you. Fights anyway. In pain.

---

## The Loot System

Inspired by Borderlands 2. Every item is procedurally generated:

**Rarity tiers:**
| Tier | Color | Affixes | Drop rate |
|---|---|---|---|
| Common | White | 0–1 | ~50% |
| Uncommon | Green | 1 | ~25% |
| Rare | Blue | 1–2 | ~15% |
| Epic | Purple | 2–3 | ~8% |
| Legendary | Orange | 3 + unique | ~2% |

**Item categories:** Weapons · Armor · Potions · Throwables

**Affix examples:**
- `+7 Damage`, `+15% Crit Chance`, `Tide Burn: 9 fire damage`
- `3% Lifesteal`, `Reflect 6 damage to attackers`, `+20 Max HP`
- `+8% Tide Token Find`, `+12% XP Gained`

**Smart loot:** 70% chance a dropped item's stats favor the class that killed the enemy. The Crab Warlord drops something useful for *your* build.

**Item naming:** procedurally generated from prefix/suffix pools.
> *"Barnacle-Encrusted Iron Sword of the Last Dive"*
> *"The Femur of Slightly Above Average Power"*
> *"Cursed Mackerel — Explodes. Also curses. Also smells."*

---

## The Endings

There are **four paths** at the bottom of the dungeon. All four require a choice the siblings aren't ready for.

Two endings are available on your first run. The other two unlock after you've seen what the sacrifice really costs.

*No spoilers beyond: there is no clean answer. The game doesn't pretend otherwise.*

---

## Multiplayer

- **Online co-op, 1–4 players**
- **Room codes** — host generates a 6-character code, share it with friends
- No port forwarding required (relay server architecture)
- Server-authoritative: the host runs game logic, clients are display layers
- Classes are unique per player — no two siblings the same

The story is designed around co-op. Siblings bicker in dialogue. The ending choice can fracture a party.

---

## Meta-Progression

Earn **Tide Tokens** during runs — awarded for kills, floor depth, and leveling. Spend them in the **Unlock Shop** between runs to:
- Unlock Gentoo (Rogue) and Little Blue (Support)
- Add additional Relic slots
- Expand the loot pool with new item types
- Unlock the two hidden ending paths

---

## Controls

| Action | Keyboard | Mouse |
|---|---|---|
| Move | WASD / Arrow keys | — |
| Primary ability | Z | Left click |
| Secondary ability | X | Right click |
| Interact | E / Space | — |
| Inventory | I | — |
| Pause | Escape | — |

---

## Tech Stack

| Layer | Technology |
|---|---|
| Engine | Godot 4.3 |
| Language | GDScript |
| Networking | ENet (LAN) / WebSocket relay (online) |
| Dungeon gen | BSP room subdivision + corridor carving |
| Sprites | Custom 8-bit pixel art (generated, placeholder) |
| Persistence | Godot FileAccess (local save) |

---

## Running the Project

1. Install [Godot 4.3](https://godotengine.org) (free)
2. Clone this repo
3. Open `project.godot` in Godot
4. Hit **Play**

For online multiplayer, see [`tools/relay_server.py`](tools/relay_server.py) — deployable on any $4/month VPS.

---

## Project Structure

```
TUX/
├── assets/sprites/          # 8-bit PNG sprite sheets
│   ├── players/             # Emperor, Gentoo, Little Blue, Macaroni (64×64)
│   ├── enemies/             # 11 enemy types (32×16 each)
│   ├── tiles/               # 4-zone tileset (96×32)
│   ├── items/               # Item icons
│   └── ui/                  # HUD elements
├── scenes/
│   ├── player/              # Player base + 4 class scripts
│   ├── enemies/             # Enemy base + AI
│   ├── items/               # Item drop + generator + affix pool
│   ├── game/                # Main game scene + orchestration
│   ├── lobby/               # Multiplayer lobby
│   ├── main_menu/           # Main menu + unlock shop
│   └── ui/                  # HUD, inventory
├── scripts/globals/         # Autoloads: GameManager, NetworkManager,
│                            # ItemDatabase, UnlockManager
├── scripts/utils/           # BSP dungeon generator
└── tools/                   # Sprite generator, relay server
```

---

*TUX is in active development. Sprite art is placeholder — contributions welcome.*
