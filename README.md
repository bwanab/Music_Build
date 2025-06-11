# MusicBuild

MusicBuild is an Elixir library for creating, manipulating, and processing MIDI files. It provides high-level abstractions for musical concepts like notes, chords, scales, and progressions, while also offering low-level access to MIDI events and data structures.

## Key Features

- **High-level musical abstractions**: Work with notes, chords, scales, and progressions
- **MIDI file I/O**: Read and write MIDI files with full event support
- **Multi-track support**: Create complex arrangements with multiple instruments
- **Sonority-based processing**: Convert between MIDI events and musical sonorities
- **Comprehensive MIDI event support**: Notes, controllers, pitch bends, and more
- **Flexible output formats**: Generate MIDI files or LilyPond notation

## Installation

Add `music_build` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:music_build, github: "bwanab/Music_Build"}
  ]
end
```

## Quick Start Examples

### Creating a Simple MIDI File

```elixir
# Create a C major scale
import Scale
import MusicBuild.Util

c_major = major_scale(:C, 4)
write_file([c_major], "c_major_scale", :midi)
```

### Building Music with Notes, Chords, and Rests

```elixir
# Mix notes, chords, and rests in a musical sequence
sonorities = [
  Note.new(:C, 4, 1),           # C4 quarter note
  Rest.new(1),                  # Quarter rest
  Chord.new(:A, :major, 4, 1),  # A major chord
  Note.new(:E, 4, 1),           # E4 quarter note
  Note.new(:F, 4, 1),           # F4 quarter note  
  Note.new(:G, 4, 1.5),         # G4 dotted quarter note
  Note.new(:Gb, 4, 3)           # Gb4 dotted half note
]

write_file([sonorities], "mixed_music", :midi)
```

### Creating Multi-Track MIDI Files

```elixir
# Create a two-track arrangement with chords and bass line
import ChordPrims

# Generate chord progression
roman_numerals = ChordPrims.random_progression(20, 1)

# Track 1: Full chords
track1 = Enum.map(roman_numerals, fn roman_numeral ->
  Chord.from_roman_numeral(roman_numeral, :C, 4, 1)
end)

# Track 2: Bass line (root notes every 4th chord)
root_numerals = Enum.take_every(roman_numerals, 4)
bass_chords = Enum.map(root_numerals, fn roman_numeral ->
  Chord.from_roman_numeral(roman_numeral, :C, 2, 4)
end)
track2 = Enum.map(bass_chords, fn chord -> 
  Enum.at(Sonority.to_notes(chord), 0)  # Extract root note
end)

# Write multi-track MIDI file
write_file([track1, track2], "two_track_arrangement", :midi)
```

### Working with Arpeggios

```elixir
# Create an arpeggio from a chord
arpeggio = Arpeggio.new(Chord.new(:C, :major, 4, 4), :up, 1)
notes = Sonority.to_notes(arpeggio)
write_file([notes], "c_major_arpeggio", :midi)

# Create repeated arpeggio patterns
dur = 0.5
arpeggio_pattern = Arpeggio.repeat(
  Arpeggio.new(Chord.new(:C, :minor, 4, dur), :up, dur), 
  4
)
write_file([arpeggio_pattern], "repeated_arpeggio", :midi)
```

## Reading and Processing MIDI Files

### Basic MIDI File Reading

```elixir
# Read a MIDI file
sequence = Midifile.read("path/to/your/file.mid")

# Convert MIDI events to musical sonorities  
channel_tracks = MapEvents.one_track_to_sonorities(sequence, 0)

# Access sonorities for each channel
channel_0_track = channel_tracks[0]
sonorities = channel_0_track.sonorities

# Process sonorities
Enum.each(sonorities, fn sonority ->
  case Sonority.type(sonority) do
    :note -> IO.puts("Note: #{inspect(sonority.note)}")
    :chord -> IO.puts("Chord with #{length(sonority.notes)} notes")
    :rest -> IO.puts("Rest: #{Sonority.duration(sonority)} beats")
    :controller -> IO.puts("Controller #{sonority.controller_number}")
    :pitch_bend -> IO.puts("Pitch bend: #{sonority.value}")
  end
end)
```

### Processing Multi-Track MIDI Files

```elixir
# Read and process all tracks with synchronization
sequence = Midifile.read("multi_track_file.mid")
all_tracks = MapEvents.all_tracks_to_sonorities(sequence)

# Access different instruments/channels
piano_track = all_tracks[0]        # Channel 0
drums_track = all_tracks[9]        # Channel 9 (drums)
bass_track = all_tracks[1]         # Channel 1

# Each track contains structured sonority data
IO.puts("Piano track: #{piano_track.track_name}")
IO.puts("Number of sonorities: #{length(piano_track.sonorities)}")
IO.puts("Instrument type: #{piano_track.track_type}")
```

### Round-Trip Processing: MIDI → Sonorities → MIDI

```elixir
# Read original MIDI file
original_sequence = Midifile.read("input.mid")

# Convert to sonorities
channel_tracks = MapEvents.one_track_to_sonorities(original_sequence, 0)

# Process/modify sonorities (example: transpose up an octave)
modified_tracks = Enum.map(channel_tracks, fn {channel, strack} ->
  modified_sonorities = Enum.map(strack.sonorities, fn sonority ->
    case Sonority.type(sonority) do
      :note -> Note.copy(sonority, octave: sonority.octave + 1)
      :chord -> Chord.copy(sonority, octave: sonority.octave + 1)  
      _ -> sonority  # Keep other types unchanged
    end
  end)
  
  {channel, STrack.copy(strack, sonorities: modified_sonorities)}
end) |> Map.new()

# Convert back to MIDI events and write
# (This would require implementing sonorities_to_midi - see EventBuilder for pattern)
```

### Working with Specific Event Types

```elixir
# Access specific event types from MIDI parsing
sequence = Midifile.read("expressive_performance.mid")
events = MapEvents.identify_sonority_events(sequence.tracks |> Enum.at(0) |> Map.get(:events))

# Extract different event types
note_events = events.note_events
controller_events = events.controller_events  
pitch_bend_events = events.pitch_bend_events

# Process pitch bend events
Enum.each(pitch_bend_events, fn pb ->
  bend_amount = pb.value - 8192  # 8192 is center (no bend)
  IO.puts("Channel #{pb.channel}: Bend #{bend_amount} at time #{pb.time}")
end)

# Process controller events (volume, pan, etc.)
Enum.each(controller_events, fn ctrl ->
  controller_name = case ctrl.controller_number do
    7 -> "Volume"
    10 -> "Pan"
    11 -> "Expression"
    64 -> "Sustain Pedal"
    _ -> "Controller #{ctrl.controller_number}"
  end
  IO.puts("#{controller_name}: #{ctrl.value} on channel #{ctrl.channel}")
end)
```

## Advanced Features

### Chord Analysis and Generation

```elixir
# Generate jazz chord progressions
progression = [:I, :vi, :ii, :V]  # Classic jazz progression
chords = Enum.map(progression, fn roman_numeral ->
  Chord.from_roman_numeral(roman_numeral, :C, 4, 4)
end)

# Analyze existing chord structures
notes = [Note.new(:C, 4, 1), Note.new(:E, 4, 1), Note.new(:G, 4, 1)]
chord = Chord.new(notes, 1)  # Detect as C major
```

### Scale and Mode Operations  

```elixir
# Work with different scales and modes
c_major = major_scale(:C, 4)
d_dorian = dorian_scale(:D, 4) 
a_minor = minor_scale(:A, 4)

# Combine scales in musical sequences
mixed_scales = c_major ++ d_dorian ++ a_minor
write_file([mixed_scales], "scale_medley", :midi)
```

### Custom Event Processing

```elixir
# Create custom sonorities with specific MIDI events
events = %{
  note_events: [...],
  controller_events: [...],
  pitch_bend_events: [...]
}

sonorities = MapEvents.group_into_sonorities(events, chord_tolerance: 10)
```

## Output Formats

MusicBuild supports multiple output formats:

- **`:midi`** - Standard MIDI files (.mid)
- **`:lily`** - LilyPond notation files (.ly) 

```elixir
# Generate both MIDI and notation
write_file([sonorities], "my_composition", :midi)
write_file([sonorities], "my_composition", :lily)
```

## API Documentation

For detailed API documentation, see the individual module documentation:

- `MapEvents` - MIDI file reading and event processing
- `MusicBuild.EventBuilder` - Converting sonorities to MIDI events  
- `MusicBuild.Util` - File I/O and utility functions
- `Scale` - Scale generation and manipulation
- `Note`, `Chord`, `Rest` - Core musical data structures

## Examples

Check out the `lib/examples/` directory for more comprehensive examples:

- `midi_from_scratch.ex` - Basic MIDI creation patterns
- `jazz_progressions.ex` - Jazz chord progressions
- `blues_12_bar.ex` - Blues patterns
- `arpeggio_progressions.ex` - Arpeggio techniques
- `bass_player.ex` - Bass line generation

