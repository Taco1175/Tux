#!/usr/bin/env python3
"""
generate_music.py — Stem generation pipeline for TUX adaptive music system.

Composes rich, multi-section MIDI arrangements per zone, renders through FluidSynth + SoundFont.
All stems within a zone share the same BPM and bar count for perfect loop alignment.

Dependencies:
    pip install midiutil
    FluidSynth installed (choco install fluidsynth / brew install fluidsynth)
    SoundFont at tools/soundfont.sf2 (e.g. FluidR3_GM.sf2)
"""

import os
import sys
import random
from pathlib import Path

try:
    from midiutil import MIDIFile
except ImportError:
    print("ERROR: midiutil not installed. Run: pip install midiutil")
    sys.exit(1)

import subprocess
import shutil

# -------------------------------------------------------
# Config
# -------------------------------------------------------
BPM = 140
BARS = 32
BEATS_PER_BAR = 4
TOTAL_BEATS = BARS * BEATS_PER_BAR
DURATION_SEC = TOTAL_BEATS * (60.0 / BPM)

SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
OUTPUT_DIR = PROJECT_DIR / "assets" / "music"
SOUNDFONT_PATH = SCRIPT_DIR / "soundfont.sf2"
TEMP_DIR = SCRIPT_DIR / "_music_temp"

# General MIDI programs (0-indexed)
GM_DISTORTION_GUITAR = 30
GM_OVERDRIVE_GUITAR = 29
GM_CLEAN_GUITAR = 27
GM_MUTED_GUITAR = 28
GM_ACOUSTIC_GUITAR = 25
GM_ELECTRIC_BASS = 33
GM_PICKED_BASS = 34
GM_SLAP_BASS = 36
GM_STRING_PAD = 48
GM_SYNTH_PAD = 88
GM_WARM_PAD = 89
GM_CHOIR = 52
GM_VOICE_OOHS = 53
GM_ORGAN = 19
GM_LEAD_SQUARE = 80
GM_LEAD_SAW = 81
GM_VIBRAPHONE = 11
GM_MARIMBA = 12
GM_PIANO = 0
GM_HARPSICHORD = 6
GM_CELESTA = 8
GM_FLUTE = 73
GM_TRUMPET = 56
GM_FRENCH_HORN = 60
GM_TUBA = 58
GM_TIMPANI = 47

# Note constants
C2, D2, E2, F2, Fs2, G2, Ab2, A2, Bb2, B2 = 36, 38, 40, 41, 42, 43, 44, 45, 46, 47
C3, Cs3, D3, Eb3, E3, F3, Fs3, G3, Ab3, A3, Bb3, B3 = 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59
C4, Cs4, D4, Eb4, E4, F4, Fs4, G4, Ab4, A4, Bb4, B4 = 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71
C5, D5, E5, F5, G5, A5, B5 = 72, 74, 76, 77, 79, 81, 83

# Drums
DRUM_CH = 9
KICK = 36
SNARE = 38
SIDESTICK = 37
CLAP = 39
CLOSED_HH = 42
OPEN_HH = 46
PEDAL_HH = 44
CRASH = 49
CRASH2 = 57
RIDE = 51
RIDE_BELL = 53
TOM_HIGH = 50
TOM_MID = 47
TOM_LOW = 45
TOM_FLOOR = 43
CHINA = 52
SPLASH = 55
COWBELL = 56
TAMBOURINE = 54


def ensure_dirs():
    zones = ["menu", "hub", "flooded_ruins", "coral_crypts",
             "abyssal_trench", "gods_sanctum", "boss", "stingers"]
    for zone in zones:
        (OUTPUT_DIR / zone).mkdir(parents=True, exist_ok=True)
    TEMP_DIR.mkdir(parents=True, exist_ok=True)


def create_midi(tracks=1, channel=0, program=0):
    midi = MIDIFile(tracks)
    midi.addTempo(0, 0, BPM)
    if channel != DRUM_CH:
        midi.addProgramChange(0, channel, 0, program)
    return midi


def create_multi_midi(channels):
    """Create MIDI with multiple channels/programs. channels = [(ch, program), ...]"""
    midi = MIDIFile(1)
    midi.addTempo(0, 0, BPM)
    for ch, prog in channels:
        if ch != DRUM_CH:
            midi.addProgramChange(0, ch, 0, prog)
    return midi


def n(midi, ch, pitch, start, dur, vel=100):
    """Shorthand: add a single note."""
    midi.addNote(0, ch, pitch, start, dur, vel)


def chord(midi, ch, pitches, start, dur, vel=90):
    """Add a chord (multiple simultaneous notes)."""
    for p in pitches:
        midi.addNote(0, ch, p, start, dur, vel)


def save_and_render(midi, name, zone):
    midi_path = TEMP_DIR / f"{zone}_{name}.mid"
    wav_path = TEMP_DIR / f"{zone}_{name}.wav"
    out_path = OUTPUT_DIR / zone / f"{name}.wav"

    print(f"    [{zone}] Rendering {name}...", flush=True)
    with open(midi_path, "wb") as f:
        midi.writeFile(f)

    sf_path = str(SOUNDFONT_PATH).replace("\\", "/")
    mid_path = str(midi_path).replace("\\", "/")
    wav_out = str(wav_path).replace("\\", "/")
    cmd = f'fluidsynth -F "{wav_out}" -r 44100 -n -i "{sf_path}" "{mid_path}"'
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=120)
    if result.returncode != 0:
        print(f"    [{zone}] ERROR: {result.stderr[:300] if result.stderr else 'unknown'}", flush=True)
        return
    if not wav_path.exists():
        print(f"    [{zone}] ERROR: WAV not created!", flush=True)
        return
    shutil.copy2(str(wav_path), str(out_path))
    print(f"    [{zone}] Done: {name}.wav", flush=True)


# -------------------------------------------------------
# Music theory helpers
# -------------------------------------------------------

def scale_notes(root, scale_type, octave_start, octave_end):
    """Generate scale notes across octaves."""
    intervals = {
        "minor":     [0, 2, 3, 5, 7, 8, 10],
        "major":     [0, 2, 4, 5, 7, 9, 11],
        "dorian":    [0, 2, 3, 5, 7, 9, 10],
        "phrygian":  [0, 1, 3, 5, 7, 8, 10],
        "harmonic_minor": [0, 2, 3, 5, 7, 8, 11],
        "blues":     [0, 3, 5, 6, 7, 10],
        "pentatonic_minor": [0, 3, 5, 7, 10],
    }
    notes = []
    for oct in range(octave_start, octave_end + 1):
        base = root + oct * 12
        for iv in intervals[scale_type]:
            notes.append(base + iv)
    return notes


def make_progression(root_note, prog_numerals, bars_each=2):
    """
    Convert roman numeral-style progression to (root, quality, duration) list.
    Numerals: list of (semitone_offset, 'maj'|'min'|'dim'|'sus4'|'7') tuples.
    Returns list of (bar_start, chord_pitches_root_pos).
    """
    result = []
    bar = 0
    for offset, quality in prog_numerals:
        root = root_note + offset
        if quality == "maj":
            pitches = [root, root + 4, root + 7]
        elif quality == "min":
            pitches = [root, root + 3, root + 7]
        elif quality == "dim":
            pitches = [root, root + 3, root + 6]
        elif quality == "sus4":
            pitches = [root, root + 5, root + 7]
        elif quality == "7":
            pitches = [root, root + 4, root + 7, root + 10]
        elif quality == "min7":
            pitches = [root, root + 3, root + 7, root + 10]
        elif quality == "maj7":
            pitches = [root, root + 4, root + 7, root + 11]
        elif quality == "5":  # power chord
            pitches = [root, root + 7]
        else:
            pitches = [root, root + 4, root + 7]
        result.append((bar, pitches, bars_each))
        bar += bars_each
    return result


# -------------------------------------------------------
# Drum pattern builder
# -------------------------------------------------------

class DrumWriter:
    def __init__(self, midi):
        self.midi = midi
        self.notes = []

    def hit(self, drum, beat, vel=90, dur=0.25):
        self.notes.append((drum, beat, dur, vel))

    def pattern(self, bar_start, bars=1, style="rock"):
        """Write drum pattern for given bars."""
        for b in range(bars):
            t0 = (bar_start + b) * BEATS_PER_BAR
            if style == "rock":
                self._rock_bar(t0)
            elif style == "half":
                self._half_bar(t0)
            elif style == "double":
                self._double_bar(t0)
            elif style == "blast":
                self._blast_bar(t0)
            elif style == "groove":
                self._groove_bar(t0)
            elif style == "tribal":
                self._tribal_bar(t0)
            elif style == "light":
                self._light_bar(t0)

    def fill(self, bar_start, fill_type="basic"):
        """Write a 1-bar fill."""
        t0 = bar_start * BEATS_PER_BAR
        if fill_type == "basic":
            self._fill_basic(t0)
        elif fill_type == "tom_roll":
            self._fill_tom_roll(t0)
        elif fill_type == "crash_build":
            self._fill_crash_build(t0)
        elif fill_type == "snare_roll":
            self._fill_snare_roll(t0)

    def flush(self):
        for drum, beat, dur, vel in self.notes:
            n(self.midi, DRUM_CH, drum, beat, dur, vel)

    # --- Patterns ---
    def _rock_bar(self, t):
        for i in range(8):  # 8th notes
            bt = t + i * 0.5
            self.hit(CLOSED_HH, bt, 80 if i % 2 == 0 else 65)
        self.hit(KICK, t, 100)
        self.hit(KICK, t + 1.5, 90)
        self.hit(SNARE, t + 1.0, 95)
        self.hit(SNARE, t + 3.0, 95)

    def _half_bar(self, t):
        for i in range(4):
            self.hit(RIDE, t + i, 70)
        self.hit(KICK, t, 85)
        self.hit(SNARE, t + 2.0, 80)

    def _double_bar(self, t):
        for i in range(8):
            bt = t + i * 0.5
            self.hit(CLOSED_HH, bt, 85 if i % 2 == 0 else 70)
        # Double kick pattern
        self.hit(KICK, t, 100)
        self.hit(KICK, t + 0.5, 85)
        self.hit(KICK, t + 1.5, 90)
        self.hit(KICK, t + 2.0, 100)
        self.hit(KICK, t + 2.5, 85)
        self.hit(KICK, t + 3.5, 90)
        self.hit(SNARE, t + 1.0, 100)
        self.hit(SNARE, t + 3.0, 100)

    def _blast_bar(self, t):
        for i in range(16):  # 16th notes
            bt = t + i * 0.25
            self.hit(KICK, bt, 110)
            if i % 2 == 0:
                self.hit(SNARE, bt, 105)
            self.hit(CLOSED_HH, bt, 75)

    def _groove_bar(self, t):
        # Syncopated groove
        self.hit(KICK, t, 95)
        self.hit(CLOSED_HH, t, 80)
        self.hit(CLOSED_HH, t + 0.5, 60)
        self.hit(SNARE, t + 1.0, 90)
        self.hit(CLOSED_HH, t + 1.0, 75)
        self.hit(KICK, t + 1.75, 80)
        self.hit(CLOSED_HH, t + 1.5, 60)
        self.hit(CLOSED_HH, t + 2.0, 80)
        self.hit(KICK, t + 2.5, 90)
        self.hit(CLOSED_HH, t + 2.5, 65)
        self.hit(SNARE, t + 3.0, 95)
        self.hit(CLOSED_HH, t + 3.0, 75)
        self.hit(OPEN_HH, t + 3.5, 70)

    def _tribal_bar(self, t):
        # Floor tom heavy, sparse
        self.hit(TOM_FLOOR, t, 100)
        self.hit(TOM_FLOOR, t + 0.75, 80)
        self.hit(TOM_LOW, t + 1.5, 90)
        self.hit(TOM_MID, t + 2.0, 85)
        self.hit(TOM_HIGH, t + 2.5, 80)
        self.hit(TOM_FLOOR, t + 3.0, 100)
        self.hit(KICK, t, 90)
        self.hit(KICK, t + 3.0, 85)

    def _light_bar(self, t):
        for i in range(4):
            self.hit(CLOSED_HH, t + i, 55)
        self.hit(KICK, t, 70)
        self.hit(SIDESTICK, t + 2.0, 60)

    # --- Fills ---
    def _fill_basic(self, t):
        self.hit(KICK, t, 100)
        self.hit(SNARE, t + 0.5, 85)
        self.hit(SNARE, t + 1.0, 90)
        self.hit(TOM_HIGH, t + 1.5, 85)
        self.hit(TOM_MID, t + 2.0, 90)
        self.hit(TOM_LOW, t + 2.5, 95)
        self.hit(TOM_FLOOR, t + 3.0, 100)
        self.hit(CRASH, t + 3.5, 110)

    def _fill_tom_roll(self, t):
        toms = [TOM_HIGH, TOM_HIGH, TOM_MID, TOM_MID, TOM_LOW, TOM_LOW, TOM_FLOOR, TOM_FLOOR]
        for i, tom in enumerate(toms):
            self.hit(tom, t + i * 0.5, 80 + i * 4)
        self.hit(CRASH, t + 3.75, 110)

    def _fill_crash_build(self, t):
        for i in range(8):
            bt = t + i * 0.5
            self.hit(SNARE, bt, 70 + i * 6)
            self.hit(KICK, bt, 70 + i * 5)
        self.hit(CRASH, t + 3.5, 120)
        self.hit(CRASH2, t + 3.5, 110)

    def _fill_snare_roll(self, t):
        for i in range(16):
            self.hit(SNARE, t + i * 0.25, 65 + i * 3)
        self.hit(CRASH, t + 3.75, 115)


# -------------------------------------------------------
# Zone compositions
# -------------------------------------------------------

def compose_menu():
    """Menu: Warm, melodic, peaceful. Arpeggiated clean guitar with evolving harmony,
    gentle piano counter-melody, lush pad. Like sitting on a beach at sunset."""

    # -- Melody: Evolving arpeggios with harmonic movement --
    midi = create_multi_midi([(0, GM_CLEAN_GUITAR), (1, GM_VIBRAPHONE)])

    # 4 sections of 8 bars each, different progressions
    # Section A: C → Am → F → G
    # Section B: Am → Em → F → C
    # Section C: Dm → G → Em → Am
    # Section D: F → G → Am → C (resolve)
    sections = [
        [(C4,E4,G4), (A3,C4,E4), (F3,A3,C4), (G3,B3,D4)] * 2,
        [(A3,C4,E4), (E3,G3,B3), (F3,A3,C4), (C4,E4,G4)] * 2,
        [(D4,F4,A4), (G3,B3,D4), (E3,G3,B3), (A3,C4,E4)] * 2,
        [(F3,A3,C4), (G3,B3,D4), (A3,C4,E4), (C4,E4,G4)] * 2,
    ]

    bar = 0
    for section in sections:
        for chord_notes in section:
            t0 = bar * BEATS_PER_BAR
            # Arpeggio pattern varies per section
            arp = list(chord_notes) + [chord_notes[1] + 12]
            pattern_options = [
                [0, 1, 2, 3, 2, 1, 0, 1],  # up-down
                [0, 2, 1, 3, 0, 2, 1, 3],  # skip
                [3, 2, 1, 0, 1, 2, 3, 2],  # down-up
                [0, 1, 2, 3, 3, 2, 1, 0],  # up then down
            ]
            pat = pattern_options[bar // 8 % len(pattern_options)]
            for i, idx in enumerate(pat):
                pitch = arp[idx % len(arp)]
                vel = 75 + int(10 * (0.5 + 0.5 * (i % 4 == 0)))
                n(midi, 0, pitch, t0 + i * 0.5, 0.45, vel)

            # Vibraphone counter-melody — sparse, on beats 2 and 4
            if bar % 2 == 0:
                n(midi, 1, chord_notes[2] + 12, t0 + 1.0, 1.0, 55)
                n(midi, 1, chord_notes[0] + 12, t0 + 3.0, 0.75, 50)
            bar += 1

    save_and_render(midi, "melody", "menu")

    # -- Pad: Rich evolving chords, not just triads --
    midi = create_multi_midi([(0, GM_WARM_PAD), (1, GM_STRING_PAD)])

    pad_chords = [
        # Section A
        [(C3,E3,G3,B3), (A2,C3,E3,G3), (F2,A2,C3,E3), (G2,B2,D3,F3)] * 2,
        # Section B
        [(A2,C3,E3,G3), (E2,G2,B2,D3), (F2,A2,C3,E3), (C3,E3,G3,B3)] * 2,
        # Section C
        [(D3,F3,A3,C4), (G2,B2,D3,F3), (E2,G2,B2,D3), (A2,C3,E3,G3)] * 2,
        # Section D
        [(F2,A2,C3,E3), (G2,B2,D3,F3), (A2,C3,E3,G3), (C3,E3,G3,B3)] * 2,
    ]

    bar = 0
    for section in pad_chords:
        for ch_pitches in section:
            t0 = bar * BEATS_PER_BAR
            # Warm pad (lower, wider)
            for p in ch_pitches:
                n(midi, 0, p, t0, BEATS_PER_BAR - 0.1, 50)
            # String pad (higher octave, thinner)
            if bar % 2 == 0:
                for p in ch_pitches[1:3]:
                    n(midi, 1, p + 12, t0, BEATS_PER_BAR * 2 - 0.1, 35)
            bar += 1

    save_and_render(midi, "pad", "menu")


def compose_hub():
    """Hub: Backstage warmup — funky rhythm guitar, walking bass, groove drums,
    warm keys, with builds and breaks."""

    # -- Melody: Rhythm guitar with funk muting + melodic phrases --
    midi = create_multi_midi([(0, GM_CLEAN_GUITAR), (1, GM_PIANO)])

    # Progression: Em7 | Am7 | Cmaj7 | D7 × 4, then B section
    prog_A = [(E3,G3,B3,D4), (A3,C4,E4,G4), (C4,E4,G4,B4), (D4,Fs4,A4,C5)]
    prog_B = [(G3,B3,D4), (A3,C4,E4), (B3,D4,Fs4), (E3,G3,B3)]

    bar = 0
    for section_idx in range(4):
        prog = prog_A if section_idx < 3 else prog_B
        for rep in range(2):
            for ch_idx, ch_notes in enumerate(prog):
                t0 = bar * BEATS_PER_BAR
                # Funky strum pattern: hit-miss-hit-miss-hit with syncopation
                strum_times = [0, 0.75, 1.5, 2.0, 2.75, 3.5]
                strum_vels = [85, 65, 80, 90, 70, 75]
                for st, sv in zip(strum_times, strum_vels):
                    # Strum — quick succession of chord notes
                    for j, p in enumerate(ch_notes[:3]):
                        n(midi, 0, p, t0 + st + j * 0.03, 0.3, sv)

                # Piano fills on every other bar
                if bar % 2 == 1:
                    fill_notes = [ch_notes[0] + 12, ch_notes[2], ch_notes[1] + 12]
                    for j, fn in enumerate(fill_notes):
                        n(midi, 1, fn, t0 + 1.0 + j * 0.5, 0.4, 60)
                bar += 1

    save_and_render(midi, "melody", "hub")

    # -- Bass: Walking bass line with chromatic approach notes --
    midi = create_midi(channel=0, program=GM_ELECTRIC_BASS)

    bass_roots_A = [E2, A2, C3, D3]
    bass_roots_B = [G2, A2, B2, E2]

    bar = 0
    for section_idx in range(4):
        roots = bass_roots_A if section_idx < 3 else bass_roots_B
        for rep in range(2):
            for root in roots:
                t0 = bar * BEATS_PER_BAR
                # Walking pattern: root, 5th, approach, next root
                fifth = root + 7
                third = root + 4 if (bar % 3 != 0) else root + 3
                approach = root + 11  # leading tone
                walk = [
                    (root, 0, 0.9, 90),
                    (fifth, 1.0, 0.9, 80),
                    (third, 2.0, 0.9, 75),
                    (approach if bar % 4 != 3 else root + 5, 3.0, 0.8, 70),
                ]
                # Add ghost notes for groove
                if bar % 2 == 0:
                    walk.append((root, 0.5, 0.15, 45))  # ghost
                    walk.append((root + 7, 2.5, 0.15, 45))
                for pitch, off, dur, vel in walk:
                    n(midi, 0, pitch, t0 + off, dur, vel)
                bar += 1

    save_and_render(midi, "bass", "hub")

    # -- Drums: Groove with fills every 4 bars --
    midi = create_midi(channel=DRUM_CH)
    dw = DrumWriter(midi)

    for section in range(4):
        for b in range(8):
            bar_num = section * 8 + b
            if b == 7:  # fill on last bar of each section
                fills = ["basic", "tom_roll", "crash_build", "snare_roll"]
                dw.fill(bar_num, fills[section % len(fills)])
            elif b == 3:  # half fill
                dw.pattern(bar_num, 1, "groove")
                # Add a small fill at the end
                t0 = bar_num * BEATS_PER_BAR
                dw.hit(TOM_HIGH, t0 + 3.0, 80)
                dw.hit(TOM_MID, t0 + 3.25, 85)
                dw.hit(TOM_LOW, t0 + 3.5, 90)
            else:
                dw.pattern(bar_num, 1, "groove")
        # Crash on section starts
        dw.hit(CRASH, section * 8 * BEATS_PER_BAR, 100)

    dw.flush()
    save_and_render(midi, "drums", "hub")

    # -- Atmosphere: Warm organ pad with movement --
    midi = create_multi_midi([(0, GM_ORGAN), (1, GM_SYNTH_PAD)])

    bar = 0
    for section in range(4):
        for rep in range(2):
            chords = [(E3,G3,B3), (A3,C4,E4), (C3,E3,G3), (D3,Fs3,A3)]
            if section == 3:
                chords = [(G3,B3,D4), (A3,C4,E4), (B3,D4,Fs4), (E3,G3,B3)]
            for ch in chords:
                t0 = bar * BEATS_PER_BAR
                # Organ — sustained with swell
                for p in ch:
                    vel = 40 + int(15 * ((bar % 8) / 8.0))  # gradual swell
                    n(midi, 0, p, t0, BEATS_PER_BAR - 0.1, vel)
                # High synth pad — slower movement
                if bar % 4 == 0:
                    for p in ch:
                        n(midi, 1, p + 12, t0, BEATS_PER_BAR * 2, 30)
                bar += 1

    save_and_render(midi, "atmosphere", "hub")


def compose_dungeon(zone_name, key_root, scale, bpm_feel, prog_sections,
                    guitar_prog=GM_DISTORTION_GUITAR, intensity=2, mood="dark"):
    """
    Rich dungeon zone composer.
    prog_sections: list of 4 sections, each a list of (semitone, quality) chord tuples.
    """

    scale_pool = scale_notes(key_root % 12, scale, 3, 6)

    # -- Melody: Guitar riffs that develop across sections --
    midi = create_multi_midi([(0, guitar_prog), (1, GM_LEAD_SAW)])

    bar = 0
    for sec_idx, section_prog in enumerate(prog_sections):
        for rep in range(2):  # each section plays twice = 8 bars × 4 sections (but progs have 4 chords × 2 bars = 8)
            for ch_idx, (offset, quality) in enumerate(section_prog):
                root = key_root + offset
                t0 = bar * BEATS_PER_BAR

                # Generate riff based on chord and section
                if mood == "dark":
                    riff = _dark_riff(root, sec_idx, bar, scale_pool)
                elif mood == "epic":
                    riff = _epic_riff(root, sec_idx, bar, scale_pool)
                elif mood == "heavy":
                    riff = _heavy_riff(root, sec_idx, bar, scale_pool)
                else:
                    riff = _dark_riff(root, sec_idx, bar, scale_pool)

                for pitch, off, dur, vel in riff:
                    n(midi, 0, pitch, t0 + off, dur, vel)

                # Lead harmony on channel 1 — plays in sections 2-3 (builds)
                if sec_idx >= 2 and bar % 2 == 0:
                    harm = _lead_harmony(root, sec_idx, scale_pool)
                    for pitch, off, dur, vel in harm:
                        n(midi, 1, pitch, t0 + off, dur, vel)

                bar += 1

    save_and_render(midi, "melody", zone_name)

    # -- Bass: Driving bass with variation --
    midi = create_midi(channel=0, program=GM_ELECTRIC_BASS if intensity < 3 else GM_PICKED_BASS)

    bar = 0
    for sec_idx, section_prog in enumerate(prog_sections):
        for rep in range(2):
            for ch_idx, (offset, quality) in enumerate(section_prog):
                root = key_root + offset - 12  # bass octave
                t0 = bar * BEATS_PER_BAR
                fifth = root + 7
                octave = root + 12

                if intensity <= 1:
                    # Simple root notes
                    bass = [(root, 0, 1.8, 85), (root, 2.0, 1.8, 80)]
                elif intensity == 2:
                    # Root-fifth pattern with walks
                    bass = [
                        (root, 0, 0.9, 90), (fifth, 1.0, 0.9, 80),
                        (root, 2.0, 0.45, 85), (root, 2.5, 0.45, 75),
                        (fifth, 3.0, 0.9, 80),
                    ]
                else:
                    # Driving 8th notes
                    bass = []
                    pattern = [root, root, fifth, root, octave, fifth, root, root + 5]
                    for i, p in enumerate(pattern):
                        bass.append((p, i * 0.5, 0.4, 85 + (10 if i % 2 == 0 else 0)))

                for pitch, off, dur, vel in bass:
                    n(midi, 0, pitch, t0 + off, dur, vel)
                bar += 1

    save_and_render(midi, "bass", zone_name)

    # -- Drums: Style progresses across sections --
    midi = create_midi(channel=DRUM_CH)
    dw = DrumWriter(midi)

    drum_styles = {
        1: ["half", "half", "rock", "rock"],
        2: ["rock", "rock", "double", "double"],
        3: ["double", "double", "blast", "blast"],
    }
    styles = drum_styles.get(intensity, drum_styles[2])

    bar = 0
    for sec_idx in range(4):
        style = styles[sec_idx]
        for b in range(8):
            if b == 7:
                fills = ["basic", "tom_roll", "crash_build", "snare_roll"]
                dw.fill(bar, fills[sec_idx])
            elif b == 3:
                dw.pattern(bar, 1, style)
                t0 = bar * BEATS_PER_BAR
                dw.hit(TOM_HIGH, t0 + 3.0, 80)
                dw.hit(TOM_LOW, t0 + 3.5, 85)
            else:
                dw.pattern(bar, 1, style)
            bar += 1
        # Crash on section starts
        dw.hit(sec_idx * 8 * BEATS_PER_BAR, CRASH, 105)

    dw.flush()
    save_and_render(midi, "drums", zone_name)

    # -- Atmosphere: Evolving pad + choir/strings --
    midi = create_multi_midi([(0, GM_SYNTH_PAD), (1, GM_STRING_PAD if mood != "epic" else GM_CHOIR)])

    bar = 0
    for sec_idx, section_prog in enumerate(prog_sections):
        for rep in range(2):
            for ch_idx, (offset, quality) in enumerate(section_prog):
                root = key_root + offset
                t0 = bar * BEATS_PER_BAR

                # Build chord voicings
                if quality in ("min", "min7"):
                    pad_notes = [root, root + 3, root + 7]
                elif quality == "dim":
                    pad_notes = [root, root + 3, root + 6]
                elif quality == "sus4":
                    pad_notes = [root, root + 5, root + 7]
                else:
                    pad_notes = [root, root + 4, root + 7]

                # Pad with evolving dynamics
                pad_vel = 40 + sec_idx * 8
                for p in pad_notes:
                    n(midi, 0, p, t0, BEATS_PER_BAR - 0.1, pad_vel)

                # Choir/strings enter in later sections
                if sec_idx >= 1:
                    choir_vel = 25 + sec_idx * 10
                    for p in pad_notes[:2]:
                        n(midi, 1, p + 12, t0, BEATS_PER_BAR, choir_vel)

                bar += 1

    save_and_render(midi, "atmosphere", zone_name)

    # -- Combat: Aggressive lead + power chords that only play at high intensity --
    midi = create_multi_midi([(0, GM_DISTORTION_GUITAR), (1, GM_OVERDRIVE_GUITAR)])

    bar = 0
    for sec_idx, section_prog in enumerate(prog_sections):
        for rep in range(2):
            for ch_idx, (offset, quality) in enumerate(section_prog):
                root = key_root + offset
                t0 = bar * BEATS_PER_BAR

                # Aggressive lead — 16th note patterns
                lead_root = root + 24  # high octave
                lead_pattern = _combat_lead(lead_root, sec_idx, scale_pool)
                for pitch, off, dur, vel in lead_pattern:
                    n(midi, 0, pitch, t0 + off, dur, vel)

                # Power chord stabs on channel 1
                pc = [root, root + 7, root + 12]
                stab_times = [0, 1.5, 2.0, 3.0] if sec_idx < 2 else [0, 0.5, 1.5, 2.0, 2.5, 3.0, 3.5]
                for st in stab_times:
                    for p in pc:
                        n(midi, 1, p, t0 + st, 0.15, 110)

                bar += 1

    save_and_render(midi, "combat", zone_name)


def _dark_riff(root, section, bar, scale_pool):
    """Generate a dark, brooding guitar riff."""
    notes = []
    r = root + 12  # guitar register

    if section == 0:
        # Chugging palm mutes with melodic hits
        times = [0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5]
        for i, t in enumerate(times):
            if i in [0, 3, 6]:
                notes.append((r, t, 0.4, 95))
            elif i == 2:
                notes.append((r + 3, t, 0.4, 90))
            elif i == 5:
                notes.append((r + 7, t, 0.35, 85))
            else:
                notes.append((r, t, 0.2, 70))  # muted
    elif section == 1:
        # More melodic, wider intervals
        melody = [r, r+3, r+7, r+10, r+12, r+10, r+7, r+5]
        for i, p in enumerate(melody):
            notes.append((p, i * 0.5, 0.45, 85 + (10 if i % 3 == 0 else 0)))
    elif section == 2:
        # Aggressive tremolo picking
        for i in range(16):
            t = i * 0.25
            p = r if i % 4 < 2 else r + 5
            notes.append((p, t, 0.2, 100))
    else:
        # Climactic — big bends and sustains
        notes.append((r, 0, 1.5, 105))
        notes.append((r + 7, 1.5, 0.9, 100))
        notes.append((r + 12, 2.5, 1.4, 110))

    return notes


def _epic_riff(root, section, bar, scale_pool):
    """Generate an epic, soaring guitar riff."""
    notes = []
    r = root + 12

    if section <= 1:
        # Arpeggiated power chords
        pattern = [r, r+7, r+12, r+7, r, r+5, r+7, r+12]
        for i, p in enumerate(pattern):
            notes.append((p, i * 0.5, 0.45, 90))
    else:
        # Soaring melody
        melody = [r+12, r+10, r+12, r+15, r+12, r+10, r+7, r+12]
        for i, p in enumerate(melody):
            dur = 0.9 if i % 2 == 0 else 0.45
            notes.append((p, i * 0.5, dur, 95 + (15 if i == 3 else 0)))

    return notes


def _heavy_riff(root, section, bar, scale_pool):
    """Generate a heavy, chugging riff."""
    notes = []
    r = root + 12

    # Djent-style rhythmic chugging
    if section == 0:
        pattern = [1, 0, 1, 0, 0, 1, 1, 0, 1, 0, 1, 0, 1, 1, 0, 0]  # 1=hit, 0=rest
        for i, hit in enumerate(pattern):
            if hit:
                notes.append((r, i * 0.25, 0.15, 100))
    elif section == 1:
        # Low chugs with chromatic movement
        pitches = [r, r, r+1, r, r, r+1, r+3, r+1]
        for i, p in enumerate(pitches):
            notes.append((p, i * 0.5, 0.35, 105))
    elif section == 2:
        # Power chord gallop
        for i in range(8):
            t = i * 0.5
            for p in [r, r+7]:
                notes.append((p, t, 0.15, 110))
            notes.append((r, t + 0.25, 0.1, 80))
    else:
        # Breakdown — slow, heavy
        notes.append((r - 12, 0, 1.0, 120))
        notes.append((r - 12, 1.5, 0.5, 115))
        notes.append((r - 11, 2.0, 0.5, 115))
        notes.append((r - 12, 3.0, 0.8, 120))

    return notes


def _lead_harmony(root, section, scale_pool):
    """Generate a harmony lead part (plays over the riff in later sections)."""
    notes = []
    r = root + 24  # high octave
    if section == 2:
        # Sustained melodic notes
        notes.append((r + 7, 0, 2.0, 70))
        notes.append((r + 5, 2.0, 1.8, 65))
    else:
        # Quick ornamental runs
        run = [r, r+2, r+3, r+5, r+7]
        for i, p in enumerate(run):
            notes.append((p, 2.0 + i * 0.25, 0.2, 75))
    return notes


def _combat_lead(root, section, scale_pool):
    """Generate aggressive combat lead patterns."""
    notes = []
    r = root

    if section <= 1:
        # Fast alternate picking
        pattern = [r, r-1, r, r+2, r, r-1, r-3, r]
        for i, p in enumerate(pattern):
            notes.append((p, i * 0.5, 0.25, 110))
    else:
        # 16th note shred runs
        run_notes = [r, r+2, r+3, r+5, r+7, r+5, r+3, r+2,
                     r, r-1, r-3, r-5, r-3, r-1, r, r+2]
        for i, p in enumerate(run_notes):
            notes.append((p, i * 0.25, 0.2, 105 + (10 if i % 4 == 0 else 0)))

    return notes


# -------------------------------------------------------
# Individual zone compositions
# -------------------------------------------------------

def compose_flooded_ruins():
    """Flooded Ruins: Murky, mysterious. E minor, moderate intensity."""
    compose_dungeon(
        zone_name="flooded_ruins",
        key_root=E3,
        scale="minor",
        bpm_feel="moderate",
        intensity=1,
        mood="dark",
        prog_sections=[
            # Each section: 4 chords × 2 bars each = 8 bars. 4 sections × 2 reps = 32 bars total... wait
            # Actually each section prog has 4 chords, plays twice = 8 bars. 4 sections = 32.
            [(0, "min"), (3, "maj"), (5, "maj"), (0, "min")],       # Em, G, Am (actually i-III-iv-i)
            [(0, "min"), (7, "maj"), (5, "maj"), (3, "maj")],       # Em, B, Am, G
            [(5, "min"), (3, "maj"), (0, "min"), (7, "min")],       # Am, G, Em, Bm
            [(0, "min"), (3, "maj"), (7, "maj"), (0, "min")],       # Em, G, B, Em (resolve)
        ],
    )


def compose_coral_crypts():
    """Coral Crypts: Faster, tighter, mysterious. A minor / Phrygian feel."""
    compose_dungeon(
        zone_name="coral_crypts",
        key_root=A3,
        scale="phrygian",
        bpm_feel="fast",
        intensity=2,
        mood="dark",
        prog_sections=[
            [(0, "min"), (1, "maj"), (0, "min"), (5, "maj")],
            [(0, "min"), (3, "min"), (1, "maj"), (0, "min")],
            [(5, "maj"), (3, "min"), (1, "maj"), (0, "min")],
            [(0, "min"), (1, "maj"), (3, "min"), (0, "min")],
        ],
    )


def compose_abyssal_trench():
    """Abyssal Trench: Heavy, crushing. E minor, high intensity, djent-style."""
    compose_dungeon(
        zone_name="abyssal_trench",
        key_root=E3,
        scale="harmonic_minor",
        bpm_feel="heavy",
        intensity=3,
        mood="heavy",
        prog_sections=[
            [(0, "5"), (0, "5"), (1, "5"), (0, "5")],
            [(0, "5"), (3, "5"), (1, "5"), (0, "5")],
            [(5, "5"), (3, "5"), (1, "5"), (0, "5")],
            [(0, "5"), (1, "5"), (0, "5"), (0, "5")],
        ],
    )


def compose_gods_sanctum():
    """God's Sanctum: Epic, orchestral-metal hybrid. E minor, grand."""
    compose_dungeon(
        zone_name="gods_sanctum",
        key_root=E3,
        scale="harmonic_minor",
        bpm_feel="epic",
        intensity=2,
        mood="epic",
        guitar_prog=GM_DISTORTION_GUITAR,
        prog_sections=[
            [(0, "min"), (3, "maj"), (7, "maj"), (5, "min")],
            [(0, "min"), (8, "maj"), (7, "maj"), (3, "maj")],
            [(5, "min"), (3, "maj"), (0, "min"), (7, "maj")],
            [(0, "min"), (7, "maj"), (8, "maj"), (0, "min")],
        ],
    )


def compose_boss():
    """Boss: All-out assault. E minor, maximum intensity, every section escalates."""

    # -- Melody: Shredding lead with harmonic backing --
    midi = create_multi_midi([(0, GM_DISTORTION_GUITAR), (1, GM_LEAD_SAW)])

    scale = scale_notes(4, "harmonic_minor", 4, 6)  # E harmonic minor

    bar = 0
    for section in range(4):
        for b in range(8):
            t0 = bar * BEATS_PER_BAR

            if section == 0:
                # Galloping riff
                gallop = [E4, E4, E4, G4, E4, E4, F4, E4,
                          E4, E4, E4, Ab4, G4, F4, E4, E4]
                for i, p in enumerate(gallop):
                    n(midi, 0, p, t0 + i * 0.25, 0.2, 105)
            elif section == 1:
                # Melodic shred — scale runs
                run_start = scale.index(E4) if E4 in scale else 0
                direction = 1 if b % 2 == 0 else -1
                for i in range(16):
                    idx = (run_start + i * direction) % len(scale)
                    n(midi, 0, scale[idx], t0 + i * 0.25, 0.2, 100 + (i % 4) * 3)
            elif section == 2:
                # Call and response — guitar + synth lead
                phrase_a = [E5, D5, B4, G4, E5, D5, B4, A4]
                phrase_b = [E4, G4, A4, B4, E4, G4, B4, D5]
                phrase = phrase_a if b % 2 == 0 else phrase_b
                for i, p in enumerate(phrase):
                    ch = 0 if b % 2 == 0 else 1
                    n(midi, ch, p, t0 + i * 0.5, 0.45, 100)
                    # Harmony a third up on the other channel
                    if i % 2 == 0:
                        n(midi, 1 - ch, p + 3, t0 + i * 0.5, 0.45, 80)
            else:
                # Climax — unison power + high bends
                for p in [E4, B4, E5]:
                    n(midi, 0, p, t0, 0.15, 120)
                n(midi, 0, E5, t0 + 0.5, 1.0, 115)
                n(midi, 1, E5 + 3, t0 + 0.5, 1.0, 90)
                n(midi, 0, D5, t0 + 1.5, 0.4, 110)
                n(midi, 0, B4, t0 + 2.0, 0.9, 115)
                n(midi, 1, D5, t0 + 2.0, 0.9, 85)
                n(midi, 0, E5, t0 + 3.0, 0.9, 120)
                n(midi, 1, G5, t0 + 3.0, 0.9, 95)

            bar += 1

    save_and_render(midi, "melody", "boss")

    # -- Bass: Relentless driving bass --
    midi = create_midi(channel=0, program=GM_PICKED_BASS)

    bar = 0
    for section in range(4):
        bass_patterns = [
            # Section 0: galloping 8ths
            lambda t, b: [(E2, t+i*0.5, 0.4, 100) for i in range(8)],
            # Section 1: chromatic walks
            lambda t, b: [(E2+i if b%2==0 else E2+7-i, t+i*0.5, 0.4, 95) for i in range(8)],
            # Section 2: syncopated grooves
            lambda t, b: [(E2, t, 0.9, 100), (G2, t+1.0, 0.4, 90), (E2, t+1.5, 0.4, 85),
                          (B2, t+2.0, 0.9, 95), (A2, t+3.0, 0.4, 90), (E2, t+3.5, 0.4, 85)],
            # Section 3: pedal tone chugging
            lambda t, b: [(E2, t+i*0.25, 0.15, 110) for i in range(16)],
        ]

        for b in range(8):
            t0 = bar * BEATS_PER_BAR
            for pitch, start, dur, vel in bass_patterns[section](t0, b):
                n(midi, 0, pitch, start, dur, vel)
            bar += 1

    save_and_render(midi, "bass", "boss")

    # -- Drums: Escalating from double-kick to blast --
    midi = create_midi(channel=DRUM_CH)
    dw = DrumWriter(midi)

    styles_per_section = ["double", "double", "blast", "blast"]
    for sec in range(4):
        for b in range(8):
            bar_num = sec * 8 + b
            if b == 7:
                dw.fill(bar_num, ["tom_roll", "crash_build", "snare_roll", "crash_build"][sec])
            else:
                dw.pattern(bar_num, 1, styles_per_section[sec])
            # Extra crashes
            if b == 0:
                dw.hit(CRASH, bar_num * BEATS_PER_BAR, 115)
            if b == 4:
                dw.hit(CRASH2, bar_num * BEATS_PER_BAR, 100)

    dw.flush()
    save_and_render(midi, "drums", "boss")

    # -- Combat: Absolute chaos layer --
    midi = create_multi_midi([(0, GM_DISTORTION_GUITAR), (1, GM_ORGAN)])

    bar = 0
    for section in range(4):
        for b in range(8):
            t0 = bar * BEATS_PER_BAR
            # Tremolo power chords
            for i in range(16):
                t = t0 + i * 0.25
                root = E3 if i < 8 else (F3 if section % 2 == 0 else G3)
                for p in [root, root + 7, root + 12]:
                    n(midi, 0, p, t, 0.15, 115)
            # Organ — sustained dread
            if b % 2 == 0:
                for p in [E3, B3, E4, G4]:
                    n(midi, 1, p, t0, BEATS_PER_BAR * 2, 70 + section * 10)
            bar += 1

    save_and_render(midi, "combat", "boss")


def compose_stingers():
    """Short one-shot sounds for beat-reactive feedback."""

    # On-beat hit — quick harmonized guitar stab
    midi = create_multi_midi([(0, GM_DISTORTION_GUITAR), (1, GM_DISTORTION_GUITAR)])
    for p in [E4, B4, E5]:
        n(midi, 0, p, 0, 0.25, 120)
    for p in [G4, D5, G5]:  # harmony
        n(midi, 1, p, 0, 0.25, 100)
    save_and_render(midi, "on_beat_hit", "stingers")

    # On-beat block — percussive shield chord
    midi = create_multi_midi([(0, GM_DISTORTION_GUITAR), (1, GM_TIMPANI)])
    for p in [E3, B3, E4]:
        n(midi, 0, p, 0, 0.15, 100)
    n(midi, 1, E2, 0, 0.3, 90)  # timpani thud
    save_and_render(midi, "on_beat_block", "stingers")

    # Perfect hit — triumphant ascending chord burst
    midi = create_multi_midi([(0, GM_DISTORTION_GUITAR), (1, GM_TRUMPET)])
    for i, p in enumerate([E4, G4, B4, E5, G5]):
        n(midi, 0, p, i * 0.04, 0.3, 127)
    for p in [E5, G5]:
        n(midi, 1, p, 0, 0.4, 110)  # trumpet fanfare
    save_and_render(midi, "perfect_hit", "stingers")


# -------------------------------------------------------
# Main
# -------------------------------------------------------
def main():
    if not SOUNDFONT_PATH.exists():
        print(f"ERROR: SoundFont not found at {SOUNDFONT_PATH}")
        print(f"Place a .sf2 file at: {SOUNDFONT_PATH}")
        sys.exit(1)

    print(f"=== TUX Stem Generator ===")
    print(f"BPM: {BPM} | Bars: {BARS} | Duration: {DURATION_SEC:.1f}s per loop")
    print(f"SoundFont: {SOUNDFONT_PATH}")
    print(f"Output: {OUTPUT_DIR}")
    print()

    ensure_dirs()

    zones = [
        ("Menu", compose_menu),
        ("Hub", compose_hub),
        ("Flooded Ruins", compose_flooded_ruins),
        ("Coral Crypts", compose_coral_crypts),
        ("Abyssal Trench", compose_abyssal_trench),
        ("God's Sanctum", compose_gods_sanctum),
        ("Boss", compose_boss),
        ("Stingers", compose_stingers),
    ]
    total = len(zones)
    for i, (name, func) in enumerate(zones, 1):
        print(f"\n=== [{i}/{total}] {name} ===", flush=True)
        try:
            func()
            print(f"=== [{i}/{total}] {name} complete ===", flush=True)
        except Exception as e:
            import traceback
            print(f"=== [{i}/{total}] {name} FAILED: {e} ===", flush=True)
            traceback.print_exc()

    print(f"\n{'='*40}")
    print(f"All {total} zones complete!")
    print(f"\nDone! Generated stems in {OUTPUT_DIR}")
    print(f"Temp files in {TEMP_DIR} (safe to delete)")


if __name__ == "__main__":
    main()
