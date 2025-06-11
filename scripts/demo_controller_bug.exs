Mix.install([
  {:music_prims, github: "bwanab/music_prims"},
  {:midifile, github: "bwanab/elixir-midifile"},
  {:music_build, path: Path.expand("~/src/music_build")},
  {:better_weighted_random, "~> 0.1.0"}
])
seq = Midifile.read("midi/Diana_Krall_-_The_Look_Of_Love.mid")
track = Enum.at(seq.tracks, 0)

if (Enum.map(track.events, fn e -> {e, MapEvents.get_channel(e)} end)   # add the channel to all channel type events
|> Enum.filter(fn {_e, channel} -> channel == 0 end)                # filter channel 0 events
|> Enum.take_while(fn {e, _channel} -> e.symbol != :on end)         # get all events before the first note on event
|> Enum.any?(fn {e, _c} -> e.symbol == :controller end))             # test to see if any controller events occur
do
  IO.puts("controller event occured before first note")
else
  IO.puts("first note occured before a controller event")
end
