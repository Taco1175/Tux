#!/usr/bin/env python3
"""
TUX Sprite Generator
Generates all placeholder 8-bit PNG sprites for TUX using stdlib only.
Run from the project root: python3 tools/generate_sprites.py
"""

import struct
import zlib
import os

# ---------------------------------------------------------------------------
# PNG writer (no dependencies)
# ---------------------------------------------------------------------------

def _png_chunk(tag: bytes, data: bytes) -> bytes:
    crc = zlib.crc32(tag + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

def write_png(path: str, width: int, height: int, pixels: list) -> None:
    """pixels: flat list of (R,G,B,A) tuples, row-major."""
    raw = b""
    for y in range(height):
        raw += b"\x00"  # filter None
        for x in range(width):
            r, g, b, a = pixels[y * width + x]
            raw += bytes([r, g, b, a])
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png  = b"\x89PNG\r\n\x1a\n"
    png += _png_chunk(b"IHDR", ihdr)
    png += _png_chunk(b"IDAT", zlib.compress(raw, 9))
    png += _png_chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)

# ---------------------------------------------------------------------------
# Colour palette
# ---------------------------------------------------------------------------

T  = (  0,   0,   0,   0)   # transparent
BK = ( 18,  18,  18, 255)   # black
WH = (240, 240, 240, 255)   # white
OR = (255, 140,   0, 255)   # orange (feet/beak)
YL = (255, 220,  50, 255)   # yellow
RD = (200,  40,  40, 255)   # red
GR = ( 40, 180,  60, 255)   # green
BL = ( 40, 100, 220, 255)   # blue
PU = (140,  60, 200, 255)   # purple
GY = (130, 130, 130, 255)   # gray
DG = ( 60,  60,  60, 255)   # dark gray
TL = ( 30, 160, 160, 255)   # teal
LB = (100, 180, 255, 255)   # light blue
PK = (240, 100, 160, 255)   # pink
GD = (220, 180,  40, 255)   # gold
DK = ( 20,  20,  40, 255)   # deep dark (abyss)
BR = (140,  80,  30, 255)   # brown

# ---------------------------------------------------------------------------
# Sprite data  (16×16 grids, 0 = transparent)
# ---------------------------------------------------------------------------

def px(grid, palette):
    """Convert a 16×16 list-of-strings to a flat pixel list."""
    pixels = []
    for row in grid:
        for ch in row:
            pixels.append(palette.get(ch, T))
    return pixels

# ---- Penguin base shape (shared) ------------------------------------------
# B=black  W=white  O=orange(feet)  A=accent(class colour)  .=transparent

PENGUIN_IDLE = [
    "................",
    "....BBBB........",
    "...BBWWBB.......",
    "..BBWWWWBB......",
    "..BWWWWWWB......",
    "..BWWWWWWB......",
    ".BBWWWWWWBB.....",
    ".BWWWWWWWWB.....",
    ".BWWWWWWWWB.....",
    ".BBBBBBBBBB.....",
    "..BBBBBBBB......",
    "....BB..BB......",
    "...OOOO.OO......",
    "...OO....OO.....",
    "................",
    "................",
]

PENGUIN_WALK_1 = [
    "................",
    "....BBBB........",
    "...BBWWBB.......",
    "..BBWWWWBB......",
    "..BWWWWWWB......",
    "..BWWWWWWB......",
    ".BBWWWWWWBB.....",
    ".BWWWWWWWWB.....",
    ".BWWWWWWWWB.....",
    ".BBBBBBBBBB.....",
    "..BBBBBBBB......",
    "...BBB..BB......",
    "..OOO....OO.....",
    "..OO......OO....",
    "................",
    "................",
]

PENGUIN_WALK_2 = [
    "................",
    "....BBBB........",
    "...BBWWBB.......",
    "..BBWWWWBB......",
    "..BWWWWWWB......",
    "..BWWWWWWB......",
    ".BBWWWWWWBB.....",
    ".BWWWWWWWWB.....",
    ".BWWWWWWWWB.....",
    ".BBBBBBBBBB.....",
    "..BBBBBBBB......",
    "....BB.BBB......",
    "...OO.OOO.......",
    "...OO..OO.......",
    "................",
    "................",
]

PENGUIN_ATTACK = [
    "................",
    "....BBBB........",
    "...BBWWBB.......",
    "..BBWWWWBB......",
    "..BWWWWWWB......",
    "..BWWWWWWBBBBB..",
    ".BBWWWWWWBBBBBB.",
    ".BWWWWWWWWBBBBB.",
    ".BWWWWWWWWB.....",
    ".BBBBBBBBBB.....",
    "..BBBBBBBB......",
    "....BB..BB......",
    "...OOOO.OO......",
    "...OO....OO.....",
    "................",
    "................",
]

PENGUIN_DEATH = [
    "................",
    "................",
    "................",
    "................",
    ".BBBB....BBBBB..",
    ".BWWB.BB.BWWWB..",
    ".BWWBBWWBBWWWB..",
    ".BWWWWWWWWWWWB..",
    ".BBBBBBBBBBBB...",
    "..BBBBBBBBBB....",
    "....BB....BB....",
    "...OOOOOOOO.....",
    "...OO....OO.....",
    "................",
    "................",
    "................",
]

def make_penguin_sheet(accent_char, accent_colour, filename):
    """Create a 64×64 sheet: idle/walk/attack/death (4 rows × 4 frames × 16px)"""
    palette = {"B": BK, "W": WH, "O": OR, ".": T, accent_char: accent_colour}
    frames = [
        PENGUIN_IDLE,    PENGUIN_IDLE,    PENGUIN_IDLE,    PENGUIN_WALK_2,  # idle (row 0)
        PENGUIN_WALK_1,  PENGUIN_WALK_2,  PENGUIN_WALK_1,  PENGUIN_IDLE,   # walk (row 1)
        PENGUIN_ATTACK,  PENGUIN_IDLE,    PENGUIN_ATTACK,  PENGUIN_IDLE,   # attack (row 2)
        PENGUIN_DEATH,   PENGUIN_DEATH,   PENGUIN_DEATH,   PENGUIN_DEATH,  # death (row 3)
    ]
    pixels = [T] * (64 * 64)
    for fi, frame_grid in enumerate(frames):
        row = fi // 4
        col = fi % 4
        frame_px = px(frame_grid, palette)
        for fy in range(16):
            for fx in range(16):
                dest = (row * 16 + fy) * 64 + (col * 16 + fx)
                pixels[dest] = frame_px[fy * 16 + fx]
    write_png(filename, 64, 64, pixels)

# ---- Emperor (gold crown stripe) ------------------------------------------
def make_emperor():
    # Add a gold stripe across the head
    base = [list(row) for row in PENGUIN_IDLE]
    # Crown pixels
    for x in [5, 6, 7, 8]:
        if x < 16:
            base[1][x] = "A"  # gold crown
    make_penguin_sheet("A", GD, "assets/sprites/players/emperor_sheet.png")

# ---- Gentoo (orange goggle stripe, smaller) --------------------------------
def make_gentoo():
    make_penguin_sheet("A", OR, "assets/sprites/players/gentoo_sheet.png")

# ---- Little Blue (blue tint accent) ----------------------------------------
def make_little_blue():
    make_penguin_sheet("A", LB, "assets/sprites/players/little_blue_sheet.png")

# ---- Macaroni (yellow crest) -----------------------------------------------
def make_macaroni():
    make_penguin_sheet("A", YL, "assets/sprites/players/macaroni_sheet.png")

# ---------------------------------------------------------------------------
# Enemy sprites (16×16 single frames → simple 32×16 sprite sheet: idle + walk)
# ---------------------------------------------------------------------------

CRAB_IDLE = [
    "................",
    "................",
    "..A.........A...",
    ".AA.........AA..",
    ".AAAAAAAAAAAA...",
    ".AAAWWWWWWWAA...",
    ".AAAWWWWWWWAA...",
    ".AAAAAAAAAAAA...",
    "..AAAAAAAAAA....",
    "..AA.AA.AA.A....",
    "..A..A...A.A....",
    "................",
    "................",
    "................",
    "................",
    "................",
]

EEL_IDLE = [
    "................",
    ".....AAAA.......",
    "....AAWWAA......",
    "...AAAWWAAA.....",
    "..AAAAWWAAAA....",
    "..AAAAAAAAAAA...",
    "..AAAAAAAAAA....",
    "...AAAAAAAAA....",
    "....AAAAAAA.....",
    ".....AAAAAAA....",
    "......AAAAAA....",
    "......AAAAA.....",
    ".......AAAA.....",
    "........AA......",
    "................",
    "................",
]

JELLYFISH_IDLE = [
    "................",
    "....AAAAAA......",
    "...AAAWWWAA.....",
    "..AAAWWWWWAA....",
    "..AAAWWWWWAA....",
    "..AAAAAAAAAA....",
    "...AAAAAAAAAA...",
    "....AAAAAAAAA...",
    ".....AAAAAAAA...",
    "....A..A..A..A..",
    "....A..A..A..A..",
    "...A...A..A...A.",
    "................",
    "................",
    "................",
    "................",
]

SHARK_IDLE = [
    "................",
    "................",
    "...........A....",
    "..........AA....",
    "..AAAAAAAAAA....",
    ".AAAWWWAAAAA....",
    "AAAWWWWWAAAAA...",
    ".AAAWWWAAAAA....",
    "..AAAAAAAAAA....",
    "..........AA....",
    "...........A....",
    "................",
    "................",
    "................",
    "................",
    "................",
]

ANGLERFISH_IDLE = [
    "................",
    "........A.......",
    ".......AA.......",
    "......AYA.......",
    ".....AAAAAA.....",
    "....AAAWWAAA....",
    "...AAAWWWWAAA...",
    "..AAABBBBBBAAA..",
    "..AAAAAAAAAAA...",
    "..AAAAAAAAAA....",
    "...AAAAAAAAAA...",
    "....A..A..A.....",
    "................",
    "................",
    "................",
    "................",
]

URCHIN_IDLE = [
    "................",
    "....A....A......",
    "....A....A......",
    "..AAAAAAAAAA....",
    ".AAAAAAAAAAAAA..",
    ".AAAAAAAAAAAAA..",
    "AAAAAAAAAAAAAA..",
    ".AAAAAAAAAAAAA..",
    ".AAAAAAAAAAAAA..",
    "..AAAAAAAAAA....",
    "....A....A......",
    "....A....A......",
    "................",
    "................",
    "................",
    "................",
]

ANEMONE_IDLE = [
    "................",
    "...A.A.A.A......",
    "..AAAAAAAA......",
    ".AAAAAAAAAA.....",
    ".AAAWWWWWAA.....",
    ".AAAWWWWWAA.....",
    ".AAAWWWWWAA.....",
    "..AAAAAAAAAA....",
    "...AAAAAAAAAA...",
    "....AAAAAAA.....",
    "....AAAA........",
    "....AAAA........",
    "....AAAA........",
    "...AAAAAA.......",
    "................",
    "................",
]

CRAB_WARLORD = [
    "..A...........A.",
    ".AA..A.....A..AA",
    "AAAGGGGGGGGGAAAA",
    "AAAGWWWWWWWGAAAA",
    "AAAGWWWWWWWGAAAA",
    "AAAGGGGGGGGGAAAA",
    "AAAAAAAAAAAAAA..",
    ".AAAAAAAAAAAAA..",
    "..AAAAAAAAAAAA..",
    "..AA.AA.AA.AA...",
    "..A..A...A..A...",
    "................",
    "................",
    "................",
    "................",
    "................",
]

LEVIATHAN_BASE = [
    "AAAAAAAAAAAAAAAA",
    "AAWWWWWWWWWWWWAA",
    "AWWWWWWWWWWWWWWA",
    "AWWWWBBBBWWWWWWA",
    "AWWWWBYYBBWWWWWA",
    "AWWWWBBBBWWWWWWA",
    "AWWWWWWWWWWWWWWA",
    "AAWWWWWWWWWWWWAA",
    "AAAAAAAAAAAAAAAA",
    ".AAAAAAAAAAAAA..",
    "..AA.AA..AA.AA..",
    "..A..A....A..A..",
    "..A..A....A..A..",
    "................",
    "................",
    "................",
]

DROWNED_GOD_BASE = [
    "AAAAAAAAAAAAAAAA",
    "AAGGGGGGGGGGGAAA",
    "AGGGWWWWWWWWGGGA",
    "AGGWWWWWWWWWWGGA",
    "AGGWWGGGGGWWWGGA",
    "AGGWWGYYYGWWWGGA",
    "AGGWWGGGGGWWWGGA",
    "AGGWWWWWWWWWWGGA",
    "AGGGWWWWWWWWGGGA",
    "AAGGGGGGGGGGGAAA",
    "AAAAAAAAAAAAAAAA",
    "..AA..AA..AA.AA.",
    "..AA..AA..AA.AA.",
    "...A..A....A..A.",
    "................",
    "................",
]

def make_enemy_sheet(grid_idle, grid_walk, accent, filename, size=16):
    """2-frame enemy sheet: idle | walk side by side."""
    palette_idle = {"A": accent, "W": WH, "B": BK, "G": GD, "Y": YL, ".": T}
    # walk = idle shifted slightly
    pi = px(grid_idle, palette_idle)
    pw = px(grid_walk if grid_walk else grid_idle, palette_idle)
    pixels = [T] * (size * 2 * size)
    for y in range(size):
        for x in range(size):
            pixels[y * (size * 2) + x] = pi[y * size + x]
            pixels[y * (size * 2) + size + x] = pw[y * size + x]
    write_png(filename, size * 2, size, pixels)

def shift_grid(grid, dy=0, dx=0):
    """Shift a sprite grid by (dy, dx) pixels, filling with '.'"""
    result = []
    for y in range(16):
        row = ""
        for x in range(16):
            sy, sx = y - dy, x - dx
            if 0 <= sy < 16 and 0 <= sx < 16:
                row += grid[sy][sx]
            else:
                row += "."
        result.append(row)
    return result

# ---------------------------------------------------------------------------
# Tileset  (96×32: 6 cols × 2 rows of 16×16 tiles)
# Floor + Wall for each of the 4 zones, plus stairs + chest
# ---------------------------------------------------------------------------

def solid(colour, w=16, h=16):
    return [colour] * (w * h)

def checkered(c1, c2, w=16, h=16):
    px = []
    for y in range(h):
        for x in range(w):
            px.append(c1 if (x + y) % 2 == 0 else c2)
    return px

def bricked(c1, c2, w=16, h=16):
    """Simple brick pattern."""
    px = []
    for y in range(h):
        for x in range(w):
            if y % 4 == 0 or (x + (y // 4 % 2) * 8) % 8 == 0:
                px.append(c2)
            else:
                px.append(c1)
    return px

def make_tileset():
    """
    96×80 tileset (6 cols × 5 rows of 16×16):
    Row 0: Zone 1 wall, Zone 1 floor, Zone 2 wall, Zone 2 floor, Zone 3 wall, Zone 3 floor
    Row 1: Zone 4 wall, Zone 4 floor, stairs_down, stairs_up, chest, spawn_marker
    """
    W = 6 * 16   # 96
    H = 5 * 16   # 80
    pixels = [T] * (W * H)

    tiles = [
        # Row 0 — zones 1-3 floor/wall pairs
        bricked((40, 55, 80, 255), (25, 35, 55, 255)),          # Zone1 wall
        checkered((50, 50, 65, 255), (42, 42, 56, 255)),         # Zone1 floor
        bricked((80, 40, 90, 255), (55, 25, 65, 255)),           # Zone2 wall
        checkered((45, 35, 60, 255), (38, 28, 52, 255)),         # Zone2 floor
        bricked((20, 35, 70, 255), (12, 22, 50, 255)),           # Zone3 wall
        checkered((15, 20, 40, 255), (10, 14, 32, 255)),         # Zone3 floor
        # Row 1 — zone 4 + special tiles
        bricked((30, 22, 18, 255), (18, 12, 8, 255)),            # Zone4 wall
        checkered((22, 18, 14, 255), (16, 12, 8, 255)),          # Zone4 floor
        _make_stairs_down(),                                      # stairs down
        _make_stairs_up(),                                        # stairs up
        _make_chest(),                                            # chest
        checkered((60, 60, 90, 255), (50, 50, 75, 255)),         # spawn
        # Row 2 — secret wall, door (placeholder repeats)
        bricked((40, 55, 80, 255), (25, 35, 55, 255)),
        bricked((40, 55, 80, 255), (30, 40, 60, 255)),
        solid((200, 160, 60, 255)),
        solid((180, 140, 40, 255)),
        solid(T),
        solid(T),
        # Row 3-4: empty (for future expansion)
    ]

    for ti, tile_pixels in enumerate(tiles[:12]):
        row = ti // 6
        col = ti % 6
        ox = col * 16
        oy = row * 16
        for y in range(16):
            for x in range(16):
                dest = (oy + y) * W + (ox + x)
                if dest < len(pixels):
                    pixels[dest] = tile_pixels[y * 16 + x]

    write_png("assets/sprites/tiles/tileset.png", W, H, pixels)

def _make_stairs_down():
    c1 = (180, 140, 60, 255)
    c2 = (120, 90, 30, 255)
    c3 = (80, 55, 15, 255)
    px = []
    for y in range(16):
        for x in range(16):
            step = x // 4
            if y == 14 - step * 3 or (x % 4 == 0 and y > 14 - step * 3 - 3):
                px.append(c3)
            elif y > 14 - step * 3:
                px.append(c2)
            else:
                px.append(c1)
    return px

def _make_stairs_up():
    c1 = (180, 140, 60, 255)
    c2 = (120, 90, 30, 255)
    c3 = (80, 55, 15, 255)
    px = []
    for y in range(16):
        for x in range(16):
            step = (15 - x) // 4
            if y == 14 - step * 3 or (x % 4 == 3 and y > 14 - step * 3 - 3):
                px.append(c3)
            elif y > 14 - step * 3:
                px.append(c2)
            else:
                px.append(c1)
    return px

def _make_chest():
    CB = (120, 70, 20, 255)   # chest brown
    CL = (180, 120, 40, 255)  # chest light
    GD_c = (220, 180, 40, 255)
    px = []
    for y in range(16):
        for x in range(16):
            if y < 2 or y > 13 or x < 1 or x > 14:
                px.append(T)
            elif y == 2 or y == 13 or x == 1 or x == 14:
                px.append(CB)
            elif y == 7 or y == 8:
                px.append(GD_c)
            elif y < 8:
                px.append(CL)
            else:
                px.append(CB)
    return px

# ---------------------------------------------------------------------------
# Item icons  (16×16 each, arranged in a 48×32 sheet)
# Weapon, Armor, Potion, Throwable, Relic
# ---------------------------------------------------------------------------

def _sword():
    s = solid(T)
    blade = (200, 200, 220, 255)
    guard = GD
    for i in range(3, 14):
        s[i * 16 + i] = blade
        if i > 3: s[(i-1) * 16 + i] = blade
    for x in range(5, 12):
        s[7 * 16 + x] = guard
    return s

def _shield():
    s = solid(T)
    rim = (80, 80, 100, 255)
    fill = (100, 130, 180, 255)
    for y in range(3, 14):
        for x in range(3, 14):
            dist = abs(x - 8) + abs(y - 8)
            if y > 10 and abs(x - 8) > 14 - y:
                pass
            elif dist < 8:
                s[y * 16 + x] = fill
            elif dist < 10:
                s[y * 16 + x] = rim
    return s

def _potion():
    s = solid(T)
    bottle = (80, 160, 100, 255)
    liquid = (120, 220, 140, 255)
    cork   = BR
    for y in range(2, 5):
        for x in range(7, 10):
            s[y * 16 + x] = cork
    for y in range(5, 14):
        w = min(6, 1 + (y - 5))
        for x in range(8 - w, 8 + w):
            if 0 <= x < 16:
                s[y * 16 + x] = liquid if y > 8 else bottle
    return s

def _throwable():
    s = solid(T)
    body = (50, 100, 200, 255)
    shine = (180, 220, 255, 255)
    for y in range(3, 13):
        for x in range(3, 13):
            if (x-7)**2 + (y-8)**2 < 22:
                s[y * 16 + x] = body
            if (x-5)**2 + (y-5)**2 < 4:
                s[y * 16 + x] = shine
    return s

def make_item_sheet():
    frames = [_sword(), _shield(), _potion(), _throwable()]
    W = 4 * 16
    H = 16
    pixels = [T] * (W * H)
    for fi, fpx in enumerate(frames):
        for y in range(16):
            for x in range(16):
                pixels[y * W + fi * 16 + x] = fpx[y * 16 + x]
    write_png("assets/sprites/items/item_icons.png", W, H, pixels)

# ---------------------------------------------------------------------------
# UI elements  (health bar, mana bar, rarity stars, tide token icon)
# ---------------------------------------------------------------------------

def make_ui_elements():
    # 8×8 token icon
    token = solid(T, 8, 8)
    for y in range(8):
        for x in range(8):
            if (x-3)**2 + (y-3)**2 < 12:
                token[y * 8 + x] = GD
    write_png("assets/sprites/ui/tide_token.png", 8, 8, token)

    # 32×8 HP bar fill tile
    hp_bar = [(200, 40, 40, 255)] * (32 * 8)
    write_png("assets/sprites/ui/hp_bar.png", 32, 8, hp_bar)

    # 32×8 MP bar fill tile
    mp_bar = [(40, 100, 220, 255)] * (32 * 8)
    write_png("assets/sprites/ui/mp_bar.png", 32, 8, mp_bar)

    # 16×16 placeholder icon
    icon = solid(BK)
    for y in range(4, 12):
        for x in range(4, 12):
            icon[y * 16 + x] = WH
    write_png("assets/sprites/ui/icon.png", 16, 16, icon)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("Generating TUX sprites...")

    # Players
    make_emperor()
    make_gentoo()
    make_little_blue()
    make_macaroni()
    print("  ✓ Player sprites (4)")

    # Enemies
    make_enemy_sheet(CRAB_IDLE,      shift_grid(CRAB_IDLE, dx=1),      OR,  "assets/sprites/enemies/crab_grunt.png")
    make_enemy_sheet(CRAB_IDLE,      shift_grid(CRAB_IDLE, dx=1),      RD,  "assets/sprites/enemies/crab_knight.png")
    make_enemy_sheet(EEL_IDLE,       shift_grid(EEL_IDLE, dy=1),       GR,  "assets/sprites/enemies/eel_scout.png")
    make_enemy_sheet(ANGLERFISH_IDLE,shift_grid(ANGLERFISH_IDLE, dx=-1),DK,  "assets/sprites/enemies/anglerfish.png")
    make_enemy_sheet(SHARK_IDLE,     shift_grid(SHARK_IDLE, dy=1),      GY,  "assets/sprites/enemies/shark_brute.png")
    make_enemy_sheet(JELLYFISH_IDLE, shift_grid(JELLYFISH_IDLE, dy=1),  PU,  "assets/sprites/enemies/jellyfish.png")
    make_enemy_sheet(URCHIN_IDLE,    shift_grid(URCHIN_IDLE, dx=1),     DG,  "assets/sprites/enemies/urchin.png")
    make_enemy_sheet(ANEMONE_IDLE,   shift_grid(ANEMONE_IDLE, dx=-1),   PK,  "assets/sprites/enemies/anemone.png")
    make_enemy_sheet(CRAB_WARLORD,   shift_grid(CRAB_WARLORD, dx=1),    RD,  "assets/sprites/enemies/crab_warlord.png")
    make_enemy_sheet(LEVIATHAN_BASE, shift_grid(LEVIATHAN_BASE, dx=1),  BL,  "assets/sprites/enemies/leviathan.png")
    make_enemy_sheet(DROWNED_GOD_BASE,shift_grid(DROWNED_GOD_BASE,dy=1),PU,  "assets/sprites/enemies/drowned_god.png")
    print("  ✓ Enemy sprites (11)")

    # Tileset
    make_tileset()
    print("  ✓ Tileset (4 zones + special tiles)")

    # Items
    make_item_sheet()
    print("  ✓ Item icons")

    # UI
    make_ui_elements()
    print("  ✓ UI elements")

    print("\nAll sprites generated. Open the project in Godot 4 to wire them up.")

if __name__ == "__main__":
    main()
