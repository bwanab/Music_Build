Mix.install([
  {:music_prims, github: "bwanab/music_prims"},
  {:midifile, github: "bwanab/elixir-midifile"},
  {:music_build, path: Path.expand("~/src/music_build")},
  {:better_weighted_random, "~> 0.1.0"}
])

# we need to add pitch_bend, poly_press and chan_press events.
# Let's start by doing pitch_bend. The file midi/mvoyage.mid has
# many pitch_bend events, so it's a good test case.

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
