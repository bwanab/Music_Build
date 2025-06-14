defmodule MusicBuildTest do
  use ExUnit.Case
  doctest MusicBuild.TrackBuilder
  doctest MusicBuild.EventBuilder

  describe "TrackBuilder" do
    test "creates a track from a list of notes" do
      notes = [
        Note.new(:C, octave: 4, duration: 1),
        Note.new(:D, octave: 4, duration: 1),
        Note.new(:E, octave: 4, duration: 1)
      ]
      track = MusicBuild.TrackBuilder.new("Test Track", notes)

      assert track.name == "Test Track"
      assert length(track.events) > 0
      assert hd(track.events).symbol == :seq_name
      assert List.last(track.events).symbol == :track_end
    end

    test "creates a track from a list of chords" do
      chords = [
        Chord.new(:C, :major, octave: 4, duration: 1.0),
        Chord.new(:G, :major, octave: 4, duration: 1.0)
      ]
      track = MusicBuild.TrackBuilder.new("Chord Track", chords)

      assert track.name == "Chord Track"
      assert length(track.events) > 0
      assert hd(track.events).symbol == :seq_name
      assert List.last(track.events).symbol == :track_end
    end

    test "creates a track from a list of arpeggios" do
      chord = Chord.new(:C, :major, octave: 4, duration: 1.0)
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
      note = Note.new(:C, octave: 4, duration: 1)
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
      chord = Chord.new(:C, :major, octave: 4, duration: 1.0)
      events = MusicBuild.EventBuilder.new(:chord, chord)

      assert length(events) == 6  # 3 notes * 2 events each
      on_events = Enum.filter(events, &(&1.symbol == :on))
      off_events = Enum.filter(events, &(&1.symbol == :off))
      assert length(on_events) == 3
      assert length(off_events) == 3
    end

    test "creates events from an arpeggio" do
      chord = Chord.new(:C, :major, octave: 4, duration: 1.0)
      arpeggio = Arpeggio.new(chord, :up, 1.0)
      events = MusicBuild.EventBuilder.new(:arpeggio, arpeggio)

      assert length(events) == 6  # 3 notes * 2 events each
      on_events = Enum.filter(events, &(&1.symbol == :on))
      off_events = Enum.filter(events, &(&1.symbol == :off))
      assert length(on_events) == 3
      assert length(off_events) == 3
    end

    test "creates events from a controller" do
      controller = Controller.new(7, 127, 0)  # Volume controller on channel 0
      events = MusicBuild.EventBuilder.new(:controller, controller)

      assert length(events) == 1
      assert hd(events).symbol == :controller
      assert hd(events).delta_time == 0
      # Check the bytes: [176 + channel, controller_number, value]
      assert hd(events).bytes == [176, 7, 127]  # 176 = 0xB0, channel 0, controller 7, value 127
    end
  end

  describe "TrackBuilder with Controllers" do
    test "creates a track with mixed sonorities including controllers" do
      sonorities = [
        Note.new(:C, octave: 4, duration: 1),
        Controller.new(7, 100, 0),  # Volume change
        Note.new(:D, octave: 4, duration: 1),
        Controller.new(10, 64, 0),  # Pan center
        Note.new(:E, octave: 4, duration: 1)
      ]
      track = MusicBuild.TrackBuilder.new("Mixed Track", sonorities)

      assert track.name == "Mixed Track"
      assert length(track.events) > 0

      # Check that controller events are present
      controller_events = Enum.filter(track.events, &(&1.symbol == :controller))
      assert length(controller_events) >= 2  # At least our 2 controller sonorities (plus potential percussion volume)

      # Verify the controller events have correct structure
      volume_event = Enum.find(controller_events, fn event ->
        event.bytes |> Enum.at(1) == 7  # Controller 7 (volume)
      end)
      assert volume_event != nil
      assert volume_event.bytes == [176, 7, 100]  # Channel 0, controller 7, value 100
    end
  end

  describe "Example arpeggio pattern" do
    test "gets arpeggio test data" do
      data = MusicBuild.Examples.ArpeggioProgressions.do_arpeggio_progression([:I, :vi, :iii],  :C, 1)
            |> Map.values
            |> Enum.flat_map(fn stm -> stm.sonorities end)
            |> Enum.flat_map(fn s -> Sonority.to_notes(s) end)
      assert data == [
        %Note{note: :C, octave: 4, duration: 2, velocity: 100, channel: 0},
        %Note{note: :E, octave: 4, duration: 2, velocity: 100, channel: 0},
        %Note{note: :G, octave: 4, duration: 2, velocity: 100, channel: 0},
        %Note{note: :C, octave: 5, duration: 2, velocity: 100, channel: 0},
        %Note{note: :E, octave: 5, duration: 2, velocity: 100, channel: 0},
        %Note{note: :G, octave: 5, duration: 2, velocity: 100, channel: 0},
        %Note{note: :A, octave: 4, duration: 2, velocity: 100, channel: 0},
        %Note{note: :C, octave: 5, duration: 2, velocity: 100, channel: 0},
        %Note{note: :E, octave: 5, duration: 2, velocity: 100, channel: 0},
        %Note{note: :A, octave: 5, duration: 2, velocity: 100, channel: 0},
        %Note{note: :C, octave: 6, duration: 2, velocity: 100, channel: 0},
        %Note{note: :E, octave: 6, duration: 2, velocity: 100, channel: 0},
        %Note{note: :E, octave: 4, duration: 2, velocity: 100, channel: 0},
        %Note{note: :G, octave: 4, duration: 2, velocity: 100, channel: 0},
        %Note{note: :B, octave: 4, duration: 2, velocity: 100, channel: 0},
        %Note{note: :E, octave: 5, duration: 2, velocity: 100, channel: 0},
        %Note{note: :G, octave: 5, duration: 2, velocity: 100, channel: 0},
        %Note{note: :B, octave: 5, duration: 2, velocity: 100, channel: 0},
        %Note{note: :C, octave: 5, duration: 0.5, velocity: 100, channel: 0},
        %Note{note: :C, octave: 4, duration: 0.5, velocity: 100, channel: 0},
        %Note{note: :E, octave: 4, duration: 0.5, velocity: 100, channel: 0},
        %Note{note: :G, octave: 4, duration: 0.5, velocity: 100, channel: 0},
        %Note{note: :A, octave: 4, duration: 0.5, velocity: 100, channel: 0},
        %Note{note: :C, octave: 5, duration: 0.5, velocity: 100, channel: 0},
        %Note{note: :A, octave: 5, duration: 0.5, velocity: 100, channel: 0},
        %Note{note: :E, octave: 5, duration: 0.5, velocity: 100, channel: 0},
        %Note{note: :G, octave: 4, duration: 0.5, velocity: 100, channel: 0},
        %Note{note: :B, octave: 4, duration: 0.5, velocity: 100, channel: 0},
        %Note{note: :E, octave: 5, duration: 0.5, velocity: 100, channel: 0},
        %Note{note: :G, octave: 4, duration: 0.5, velocity: 100, channel: 0},
        %Note{note: :C, octave: 2, duration: 1, velocity: 100, channel: 0},
        %Note{note: :C, octave: 3, duration: 1, velocity: 100, channel: 0},
        %Note{note: :A, octave: 2, duration: 1, velocity: 100, channel: 0},
        %Note{note: :C, octave: 3, duration: 1, velocity: 100, channel: 0},
        %Note{note: :E, octave: 2, duration: 1, velocity: 100, channel: 0},
        %Note{note: :B, octave: 2, duration: 1, velocity: 100, channel: 0}
      ]
    end
  end
end
