# TUX

> *"Play loud. Play hard. Come back alive."*

TUX is a 2D 8-bit dungeon crawler roguelike with online co-op for 1-4 players. Four penguin siblings form a metal band and descend into the deep venues beneath Antarctica to rescue their missing parents - and shred the Lobster Warlord who silenced every band before them.

Built in **Godot 4.6** with GDScript.

---

## The Story

Antarctica. The coldest place on Earth. But underneath the ice... the music never stopped.

For generations, penguin bands have descended into the deep venues beneath the glaciers - playing for something ancient, something hungry. The last band to go down was the best. Two parents. One tour. No return.

They left behind four kids. Four siblings. Four instruments. One band name: **TUX**.

The Lobster Warlord rules the deep venues. He silenced every band that came before. He took your parents.

Now it's your turn to play.

---

## The Band

| Character | Role | Instrument | Personality |
|---|---|---|---|
| **Emperor** | Lead Guitar | Battle Axe Guitar | The oldest. Overprotective. Heavy riffs, heavy armor. Slow but unstoppable. Secondary: Power Chord (AoE knockback). |
| **Gentoo** | Drums | Dual Drumsticks | The chaotic middle sibling. Fastest tempo, hardest crits. Glass jaw. Secondary: Paradiddle Dash (invincible dodge). |
| **Little Blue** | Vocals | Mic Stand | The peacekeeper. Heals with Power Ballads. Snaps into Death Metal mode at low HP - doubled damage, terrifying screams. |
| **Macaroni** | Bass | Bass Guitar | The youngest. Unnerving calm. Bass drops = AoE devastation. Gets *louder* the lower their HP ("Low End Theory" passive). |

Each sibling has a **unique passive ability**, a **primary attack** (instrument-themed), and a **secondary skill**. Stats scale differently - Macaroni at level 15 is not the same game as Emperor at level 15.

---

## The Venues

The dungeon is **hybrid-structured**: floor-by-floor descent through corrupted underground venues. Each zone has backstage murals with the true history of the music industry's darkest secret.

| Zone | Theme | Boss |
|---|---|---|
| **Flooded Ruins** | Crumbling stone, rising water, crab patrols | - |
| **Coral Crypts** | Bioluminescent traps, stinging swarms | The Crab Warlord |
| **Abyssal Trench** | Crushing dark, anglerfish lures, shark ambushes | The Leviathan |
| **The God's Sanctum** | Ancient, wrong, quiet | The Drowned God |

---

## Features

### Hades-style Hub World
Between runs, explore the backstage hub area. Talk to NPCs, build relationships, earn gifts:
- **Roadie Rick** - Grizzled combat mentor. Gives damage buffs and a legendary axe guitar.
- **Melody** - Merch girl. Runs the shop, gives discounts and gold-find bonuses.
- **DJ Scratch** - Sound engineer and lore keeper. XP buffs and secret room reveals.
- **Mama Krill** - Band mom. Sardine rolls heal, stew boosts max HP.
- **The Producer** - Mysterious figure who appears after deep runs. Knows too much.

### Borderlands-style Loot
Every item is procedurally generated with rarity tiers, random affixes, and procedural names.

| Tier | Color | Affixes |
|---|---|---|
| Common | White | 0-1 |
| Uncommon | Green | 1 |
| Rare | Blue | 1-2 |
| Epic | Purple | 2-3 |
| Legendary | Orange | 3 + unique |

Items drop on the ground - walk up and press **[E]** to pick up. A Borderlands-style loot card shows the item score, stats, affixes, and whether it's an upgrade over your current gear.

**Weapon types:** Axe Guitar, Keytar, Bass Guitar, Mic Stand, Drum Sticks

**Item naming:** procedurally generated from prefix/suffix pools.
> *"Distorted Axe Guitar of the Mosh Pit"*
> *"Overdriven Bass Guitar of Mild Tinnitus"*
> *"Cursed Demo Tape - Explodes into noise. Side B is worse."*

### Drag-and-Drop Inventory
Full inventory with drag-and-drop item management, equipment slots, and hotbar for consumables.

### Procedural 8-Bit Metal Soundtrack
Runtime-generated chiptune metal music using AudioStreamGenerator:
- Square wave riffs with power chord harmonics
- Triangle wave bass lines
- Procedural drum patterns (kick/snare/hi-hat)
- Different tracks for menu, hub, dungeon, and boss fights
- Class-specific attack SFX (guitar crunch, drum hits, vocal screeches, bass thumps)

### Throwable Items with Animations
Grenades, smoke machines, and cursed demo tapes throw with parabolic arcs, landing pauses, and AoE explosions with particle bursts.

### Intro Cutscene
Cinematic intro establishing the metal band backstory with character portraits and dialogue. Plays on first launch, skippable with ESC.

---

## The Endings

There are **four paths** at the bottom of the dungeon. All four require a choice the siblings aren't ready for.

Two endings are available on your first run. The other two unlock after you've seen what the sacrifice really costs.

---

## Multiplayer

- **Online co-op, 1-4 players**
- **Room codes** - host generates a 6-character code, share it with friends
- No port forwarding required (relay server architecture)
- Server-authoritative: the host runs game logic
- Classes are unique per player

---

## Meta-Progression

Earn **Tide Tokens** during runs. Spend them in the **Unlock Shop** to:
- Unlock Gentoo (Drums) and Little Blue (Vocals)
- Add additional Relic slots
- Expand the loot pool with new item types
- Unlock the two hidden ending paths

### Save-1-Item Mechanic
After each run (death or victory), save exactly one item to keep permanently. Equip saved items from the hub Vault before your next gig.

---

## Controls

| Action | Keyboard | Mouse |
|---|---|---|
| Move | WASD / Arrow keys | - |
| Primary ability | Z | Left click |
| Secondary ability | X | Right click |
| Interact / Pick up | E / Space | - |
| Inventory | I | - |
| Pause / Close menus | Escape | - |

---

## Tech Stack

| Layer | Technology |
|---|---|
| Engine | Godot 4.6 |
| Language | GDScript |
| Networking | ENet (LAN) / WebSocket relay (online) |
| Dungeon gen | BSP room subdivision + corridor carving |
| Audio | Procedural 8-bit via AudioStreamGenerator |
| Sprites | Custom 8-bit pixel art (generated, placeholder) |
| Persistence | Godot FileAccess (local save) |

---

## Running the Project

1. Install [Godot 4.6](https://godotengine.org) (free)
2. Clone this repo
3. Open `project.godot` in Godot
4. Hit **Play**

For online multiplayer, see [`tools/relay_server.py`](tools/relay_server.py).

---

## Project Structure

```
TUX/
├── assets/sprites/          # 8-bit PNG sprite sheets
│   ├── players/             # Emperor, Gentoo, Little Blue, Macaroni
│   ├── enemies/             # Enemy types
│   ├── tiles/               # Zone tilesets
│   └── ui/                  # HUD elements
├── scenes/
│   ├── intro/               # Intro cutscene
│   ├── player/              # Player base + 4 class scripts
│   │   └── classes/         # Emperor, Gentoo, LittleBlue, Macaroni
│   ├── enemies/             # Enemy base + AI
│   ├── items/               # Item drop + generator + affix pool
│   ├── game/                # Main game scene + dungeon orchestration
│   ├── hub/                 # Backstage hub world
│   ├── lobby/               # Multiplayer lobby + character select
│   ├── main_menu/           # Main menu + unlock shop
│   └── ui/                  # HUD, inventory, item save screen
├── scripts/
│   ├── globals/             # Autoloads: GameManager, NetworkManager,
│   │                        # ItemDatabase, UnlockManager, DialogueManager,
│   │                        # AudioManager
│   └── utils/               # BSP dungeon generator
└── tools/                   # Sprite generator, relay server
```

---

*TUX is in active development. Sprite art is placeholder. Contributions welcome.*
