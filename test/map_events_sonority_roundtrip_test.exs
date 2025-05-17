defmodule Midifile.MapEventsSonorityRoundtripTest do
  use ExUnit.Case
  alias MusicBuild.TrackBuilder
  alias MapEvents
  alias TrackBuilder
  alias Midifile.Track
  alias Midifile.Sequence
  alias Midifile.Writer


  test "sonorities round trip through MIDI conversion" do
    # 1) Read the midi file test/test_sonorities.mid
    sequence = Midifile.read("test/test_sonorities.mid")
    track = Enum.at(sequence.tracks, 0)

    # 2) Convert the only track to sonorities
    original_sonorities = MapEvents.track_to_sonorities(track, %{
      ticks_per_quarter_note: sequence.ticks_per_quarter_note
    })

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
    new_track = Enum.at(new_sequence.tracks, 0)
    new_sonorities = MapEvents.track_to_sonorities(new_track, %{
      ticks_per_quarter_note: new_sequence.ticks_per_quarter_note
    })

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
end
