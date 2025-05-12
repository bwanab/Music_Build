defmodule MusicBuildTest do
  use ExUnit.Case
  doctest MusicBuild.TrackBuilder
  doctest MusicBuild.EventBuilder

  describe "TrackBuilder" do
    test "creates a track from a list of notes" do
      notes = [
        Note.new({:C, 4}, duration: 1.0),
        Note.new({:D, 4}, duration: 1.0),
        Note.new({:E, 4}, duration: 1.0)
      ]
      track = MusicBuild.TrackBuilder.new("Test Track", notes)

      assert track.name == "Test Track"
      assert length(track.events) > 0
      assert hd(track.events).symbol == :seq_name
      assert List.last(track.events).symbol == :track_end
    end

    test "creates a track from a list of chords" do
      chords = [
        Chord.new({{:C, 4}, :major}, 1.0),
        Chord.new({{:G, 4}, :major}, 1.0)
      ]
      track = MusicBuild.TrackBuilder.new("Chord Track", chords)

      assert track.name == "Chord Track"
      assert length(track.events) > 0
      assert hd(track.events).symbol == :seq_name
      assert List.last(track.events).symbol == :track_end
    end

    test "creates a track from a list of arpeggios" do
      chord = Chord.new({{:C, 4}, :major}, 1.0)
      arpeggios = [
        Arpeggio.new(chord, :up, 1.0),
        Arpeggio.new(chord, :down, 1.0)
      ]
      track = MusicBuild.TrackBuilder.new("Arpeggio Track", arpeggios)

      assert track.name == "Arpeggio Track"
      assert length(track.events) > 0
      assert hd(track.events).symbol == :seq_name
      assert List.last(track.events).symbol == :track_end
    end
  end

  describe "EventBuilder" do
    test "creates events from a note" do
      note = Note.new({:C, 4}, duration: 1.0)
      events = MusicBuild.EventBuilder.new(:note, note)

      assert length(events) == 2
      assert hd(events).symbol == :on
      assert List.last(events).symbol == :off
    end

    test "creates events from a rest" do
      rest = Rest.new(1.0)
      events = MusicBuild.EventBuilder.new(:rest, rest)

      assert length(events) == 1
      assert hd(events).symbol == :off
    end

    test "creates events from a chord" do
      chord = Chord.new({{:C, 4}, :major}, 1.0)
      events = MusicBuild.EventBuilder.new(:chord, chord)

      assert length(events) == 6  # 3 notes * 2 events each
      on_events = Enum.filter(events, &(&1.symbol == :on))
      off_events = Enum.filter(events, &(&1.symbol == :off))
      assert length(on_events) == 3
      assert length(off_events) == 3
    end

    test "creates events from an arpeggio" do
      chord = Chord.new({{:C, 4}, :major}, 1.0)
      arpeggio = Arpeggio.new(chord, :up, 1.0)
      events = MusicBuild.EventBuilder.new(:arpeggio, arpeggio)

      assert length(events) == 6  # 3 notes * 2 events each
      on_events = Enum.filter(events, &(&1.symbol == :on))
      off_events = Enum.filter(events, &(&1.symbol == :off))
      assert length(on_events) == 3
      assert length(off_events) == 3
    end
  end
end
