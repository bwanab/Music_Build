defmodule Midifile.MapEventsSonorityRoundtripTest do
  use ExUnit.Case
  alias MusicBuild.TrackBuilder
  alias MapEvents
  alias TrackBuilder
  alias Midifile.Sequence
  alias Midifile.Writer


  test "sonorities round trip through MIDI conversion" do
    # 1) Read the midi file test/test_sonorities.mid
    sequence = Midifile.read("midi/test_sonorities.mid")

    # 2) Convert the only track to sonorities
    original_channel_tracks = MapEvents.track_to_sonorities(sequence, 0)
    original_sonorities = original_channel_tracks[0].sonorities  # Get channel 0 sonorities

    # 3) Write those sonorities out as a test/temp.mid file
    temp_track = TrackBuilder.new("Sonorities", original_sonorities, sequence.ticks_per_quarter_note)
    temp_sequence = Sequence.new(
      "Sonorities Roundtrip",
      Midifile.Sequence.bpm(sequence),
      [temp_track],
      sequence.ticks_per_quarter_note
    )
    Writer.write(temp_sequence, "test/temp.mid")

    # 4) Read test/temp.mid in as a new sequence and convert its only track to sonorities
    new_sequence = Midifile.read("test/temp.mid")
    new_channel_tracks = MapEvents.track_to_sonorities(new_sequence, 0)
    new_sonorities = new_channel_tracks[0].sonorities  # Get channel 0 sonorities

    # 5) The sonorities from step 2 should be identical to those from step 4

    # Compare the number of sonorities
    assert length(original_sonorities) == length(new_sonorities)

    # Compare each sonority
    Enum.zip(original_sonorities, new_sonorities)
    |> Enum.each(fn {original, new} ->
      # Check the type
      assert Sonority.type(original) == Sonority.type(new)

      # Check duration
      assert Sonority.duration(original) == Sonority.duration(new)

      # Check details based on type
      case Sonority.type(original) do
        :note ->
          # For notes, check pitch and velocity
          assert Note.enharmonic_equal?(original.note, new.note)
          assert original.velocity == new.velocity

        :chord ->
          # For chords, check that they have the same notes
          # Use MapSet for unordered comparison
          original_notes = Enum.map(original.notes, & &1.note) |> MapSet.new()
          new_notes = Enum.map(new.notes, & &1.note) |> MapSet.new()
          assert MapSet.equal?(original_notes, new_notes)

          # Also check velocities for each note
          original_velocities = Enum.map(original.notes, & &1.velocity) |> Enum.sort()
          new_velocities = Enum.map(new.notes, & &1.velocity) |> Enum.sort()
          assert original_velocities == new_velocities

        :rest ->
          # For rests, duration check is sufficient (already done above)
          :ok
      end
    end)

    # Clean up the temporary file
    File.rm("test/temp.mid")
  end

  test "sonorities round trip with lilypond and dotted note durations" do
    sonorities = [
      Note.new(:C, 4, 1),
      Rest.new(1),
      Chord.new(:A, :major, 4, 1),
      Note.new(:E, 4, 1),
      Note.new(:F, 4, 1),
      Note.new(:G, 4, 1.5),     # dotted quarternote
      Note.new(:Gb, 4, 3)     # dotted halfnote
    ]
    MusicBuild.LilyBuild.write([sonorities], "midi/round_trip_dotted.ly", midi: true, out_path: "./midi")
    seq = Midifile.Reader.read("midi/round_trip_dotted.midi")
    derived_channel_tracks = MapEvents.track_to_sonorities(seq, 0, chord_tolerance: 10)
    derived_sonorities = derived_channel_tracks[0].sonorities  # Get channel 0 sonorities
    assert length(sonorities) == length(derived_sonorities)
    Enum.map(Enum.zip(sonorities, derived_sonorities), fn {s1, s2} ->
      assert Sonority.type(s1) == Sonority.type(s2)
      case Sonority.type(s1) do
        :note -> assert Note.enharmonic_equal?(s1.note, s2.note)
        :chord -> assert Note.enharmonic_equal?(s1.root, s2.root)
        _ -> true
      end
      assert Sonority.duration(s1) == Sonority.duration(s2)
    end)

  end

end
