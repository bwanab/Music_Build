# There is a problem in the computation of begining rest times for channels. All the channels line up in sync except for channel 4 in this
# midi file. Channel 4 starts 2 quarter notes too early which I've verified by ear and demonstrate in this script.

Mix.install([
  {:music_prims, github: "bwanab/music_prims"},
  {:midifile, github: "bwanab/elixir-midifile"},
  {:music_build, path: Path.expand("~/src/music_build")},
  {:better_weighted_random, "~> 0.1.0"}
])

seq = Midifile.read("midi/Diana_Krall_-_The_Look_Of_Love.mid")
events = Enum.at(seq.tracks, 0).events

# identify all the events, their channels, and start times
s_events = MapEvents.identify_sonority_events(events)

# get the ticks per quarter note of the file
tpqn = Midifile.Sequence.ppqn(seq)

# compute the number of quarter notes of rest that the file has for each channel.
# note that all channels except 4 have a non-zero rest, but specifically most channels have 2 quarter notes of rest at start
channel_start_times = Enum.map(0..6, fn idx -> Enum.filter(s_events[:notes], fn s -> s.channel == idx end) |> Enum.reverse |> Enum.take(1) |> Enum.at(0) end)
min_start_time = Enum.map(channel_start_times, fn %{channel: _c, start_time: s} -> s end) |> Enum.min
IO.inspect(Enum.map(channel_start_times, fn %{channel: c, start_time: s} -> %{channel: c, n_quarter_notes: round((s - min_start_time) / tpqn)} end), label: "quarter_notes of rest at start")

# now, we compute the sonorities
strack_map = MapEvents.one_track_to_sonorities(seq, 0)

# compute the number of quarter notes at the state based on sonorities.
# Note that all channels except channel 4 start with a rest of 4 or more quarter notes:
IO.inspect(Enum.map(0..6, fn idx -> strack_map[idx].sonorities |> Enum.take_while(fn s -> Sonority.type(s) != :controller end) end), label: "computed quarter_notes of rest at start")

# we look at the first 4 sonorites for channel 4 and see that it starts at 0
IO.inspect(strack_map[4].sonorities |> Enum.take(4), label: "first note of channel 4 starts at 0")

# the conclusion is that either 1) channel 4 should have had a 2 quarter note rest computed or, 2) all the other channels should have had a rest that is 2 quarter notes less
# than was actually computed. I would prefer option 1 since that has the benefit of lining up the measures properly until we deal with partial measures at the start.
