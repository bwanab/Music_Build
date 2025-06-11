# Claude Code Preferences

## Repository Information
- GitHub remote name: upstream
- Origin remote: git.sr.ht

## Commands
# Update these for your specific project type
- Run tests: `mix test`
- Compile: `mix compile`

## Project Dependencies and Architecture

### Key Dependencies
- **music_prims** - Core musical data structures and protocols (in active development)
  - Located at `../music_prims` (local path dependency)
  - Contains crucial modules: `Sonority` protocol, `Note`, `Chord`, `Rest`, `Controller`, `PitchBend`, etc.
  - All fundamental musical abstractions live here
- **elixir-midifile** - MIDI file I/O library (in active development)
  - Handles low-level MIDI file reading/writing
  - Provides `Midifile.Event`, `Midifile.Sequence` structures

### Project Architecture
- **Sonority-based design**: Everything implements the `Sonority` protocol from music_prims
- **Two-way conversion**: Musical sonorities ↔ MIDI events
- **Key modules in this project**:
  - `MapEvents` - Converts MIDI events to sonorities (reading MIDI files)
  - `MusicBuild.EventBuilder` - Converts sonorities to MIDI events (writing MIDI files)
  - `MusicBuild.Util` - File I/O utilities for both MIDI and LilyPond output
  - `STrack` - Track structure for organizing sonorities by channel/instrument

### Development Patterns
- **Adding new MIDI event types**: 
  1. Ensure corresponding module exists in music_prims (e.g., `PitchBend`)
  2. Add parsing in `MapEvents.identify_sonority_events/1`
  3. Add event building in `EventBuilder.new/3`
  4. Update events map structure throughout
- **Function signatures**: Recent refactoring uses events maps instead of separate parameters
  ```elixir
  # Preferred pattern
  events = %{note_events: [...], controller_events: [...], pitch_bend_events: [...]}
  group_into_sonorities(events, chord_tolerance, tpqn)
  ```
- **Output formats**: Support both `:midi` and `:lily` (LilyPond notation)
- **Examples**: Comprehensive examples in `lib/examples/` directory demonstrate usage patterns

### Testing Notes
- Tests in `test/` directory cover both unit tests and integration tests with real MIDI files
- `midi/` directory contains test MIDI files for various scenarios
- Multi-track synchronization and timing are important test areas

### Important Context
- This is a music composition and analysis library, not just MIDI file manipulation
- Supports both programmatic music generation and analysis of existing MIDI files
- High-level musical concepts (scales, chord progressions) are as important as low-level MIDI events