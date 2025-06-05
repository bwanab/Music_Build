defmodule PatternTest do
  use ExUnit.Case
  alias MusicBuild.Examples.PatternEvaluator

  test "gather groups of notes into a map based on a pattern" do
    seq = Midifile.read("midi/quantized_blues_bass.mid")
    channel_tracks = MapEvents.track_to_sonorities(seq, 0)
    sonorities = channel_tracks[0].sonorities  # Get channel 0 sonorities
    assert length(sonorities) == 768
    pattern = [:I, :IV, :I, :I, :IV, :IV, :I, :I, :V, :IV, :I, :V]
    lines = Enum.chunk_every(sonorities, 12 * 8)
    assert length(lines) == 8
    mapped = Enum.map(lines, fn line -> PatternEvaluator.chunk_line(line, 8, pattern) end)
             |> PatternEvaluator.merge_maps_with_lists()
    assert Enum.sort(Map.keys(mapped)) == [:I, :IV, :V]
    assert length(mapped[:I]) == 48
  end

end
