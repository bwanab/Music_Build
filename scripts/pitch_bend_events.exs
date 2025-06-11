Mix.install([
  {:music_prims, github: "bwanab/music_prims"},
  {:midifile, github: "bwanab/elixir-midifile"},
  {:music_build, path: Path.expand("~/src/music_build")},
  {:better_weighted_random, "~> 0.1.0"}
])

#

"""
 Objective:  We need to add pitch_bend, poly_press and chan_press events.

 Prerequisite:

 Based on the analysis of the MusicPrims codebase, I strongly recommend creating separate PitchBend, PolyPress, and ChanPress modules, each implementing the Sonority protocol.

  Key reasons:

  1. Architectural Consistency - The codebase follows a clear pattern where each distinct musical concept (Note, Chord, Rest, Controller) gets its own module implementing Sonority
  2. Type Safety - Separate modules provide compile-time type safety and clear APIs with specific validation (e.g., PitchBend's 14-bit values)
  3. Event-Specific APIs - Each can have tailored constructors:
    - PitchBend.new(channel, value)
    - PolyPress.new(channel, note, pressure)
    - ChanPress.new(channel, pressure)
  4. Pattern Matching Clarity - EventBuilder can cleanly handle each type without inspecting internal fields

  The code duplication is minimal (just Sonority protocol boilerplate), and this approach maintains consistency with the established architecture while providing clear, extensible interfaces
  for each MIDI event type.

  1. Examine the existing Controller module structure
  2. Create the three new modules (PitchBend, PolyPress, ChanPress) following the same pattern
  3. Ensure they properly implement the Sonority protocol

"""

# Let's start by doing pitch_bend. The file midi/mvoyage.mid has
# many pitch_bend events, so it's a good test case for this feature.

# pitch_bend events work like controller events in that they are instantaneous
# events, but where controllers have a channel, controller number and a value, pitch_bend
# events only have a channel and a value.

seq = Midifile.read("midi/mvoyage.mid")
# we know this is a 1 track file
events = Enum.at(seq.tracks, 0).events

# this demonstrates how to unpack the integer value of the pitch_bend event.
pbs = Enum.filter(events, fn e -> e.symbol == :pitch_bend end)
|> Enum.map(fn e ->
  [_, b] = e.bytes
  pitch_bend_value = b |> :binary.decode_unsigned(:big)
  {e, pitch_bend_value}
end)
Enum.each(pbs, fn e -> IO.inspect(e) end)
