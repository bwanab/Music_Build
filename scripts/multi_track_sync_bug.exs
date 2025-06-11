Mix.install([
  {:music_prims, github: "bwanab/music_prims"},
  {:midifile, github: "bwanab/elixir-midifile"},
  {:music_build, path: Path.expand("~/src/music_build")},
  {:better_weighted_random, "~> 0.1.0"}
])

seq = Midifile.read("midi/01Duet_1.mid")

length(seq.tracks)   # results in 2 for this track.

# my first naive reading of this file was: stm = Enum.reduce(0..length(seq.tracks) - 1, %{}, fn idx, acc -> Map.merge(acc, MapEvents.track_to_sonorities(seq, idx)) end)
# But, given the following, that produces an unsynchronized map of STracks.

# the two tracks have identical starting times after identify_sonority_events
IO.inspect(Enum.map(seq.tracks, fn track -> MapEvents.identify_sonority_events(track.events)[:notes] end) |> Enum.map(fn s -> Enum.take(s, 1) |> Enum.at(0) end))

IO.puts("=============")
# But, looking at the data from the midi file as read, program is the first event that has a delta_time > 0, but it is 128 for track 1, but 0 for track 0.
IO.inspect(Enum.map(seq.tracks, fn track -> Enum.drop_while(track.events, fn e -> e.symbol != :program end) |> Enum.take(1) end))

# Thus, when the midi file has more than one track, we need a way to synchronize the starting points for all the tracks similarly to how it is done for multiple
# channels when the midi file has one track but several channel. One way to handle this would be to create a prepocessing step that reads through the tracks to
# discover their relative starting points in ticks_per_quarter_note, or in number of quarter notes, whichever makes more sense, for each track in a list,then pass that
# list into track to sonorities to specify an additional rest at the start of the sonorities.

# A caution: we can't count on the first > 0 delta_time being a :program event or any other specific event.

# Also, a question: is it possible that multiple channels exist per track in a multi-track midi file? If so, that would have to be handled.
