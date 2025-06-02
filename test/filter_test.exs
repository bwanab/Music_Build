defmodule FilterTest do
  use ExUnit.Case

  test "process_notes works with Note struct predicates" do
    # Create a sequence with note pairs of varying durations
    sequence = %Midifile.Sequence{
      format: 1,
      # Standard MIDI ticks per quarter note
      time_basis: :metrical_time,  # :metrical_time or :smpte
      ticks_per_quarter_note: 480, # Used when time_basis is :metrical_time
      smpte_format: nil,           # 24, 25, 29, or 30 - used when time_basis is :smpte
      ticks_per_frame: nil,        # Used when time_basis is :smpte

      tracks: [
        %Midifile.Track{
          events: [
            # Long note - C4 with duration 480 ticks (quarter note)
            # C4 note_on
            %Midifile.Event{symbol: :on, delta_time: 0, bytes: [0x90, 60, 80]},
            # Short note - D4 with duration 120 ticks (1/16 note)
            # D4 note_on
            %Midifile.Event{symbol: :on, delta_time: 0, bytes: [0x90, 62, 100]},
            # D4 note_off
            %Midifile.Event{symbol: :off, delta_time: 120, bytes: [0x80, 62, 0]},
            # Medium note - E4 with duration 240 ticks (1/8 note)
            # E4 note_on
            %Midifile.Event{symbol: :on, delta_time: 0, bytes: [0x90, 64, 70]},
            # E4 note_off
            %Midifile.Event{symbol: :off, delta_time: 240, bytes: [0x80, 64, 0]},
            # C4 note_off
            %Midifile.Event{symbol: :off, delta_time: 120, bytes: [0x80, 60, 0]}
          ]
        }
      ]
    }

    # Filter out short notes (less than 200 ticks duration)
    filtered_sequence =
      Filter.process_notes(
        sequence,
        0,
        # Match notes shorter than eigth notes
        fn note -> note.duration < 0.5 end,
        # Remove these notes
        :remove
      )

    filtered_events = List.first(filtered_sequence.tracks).events

    # Should have 4 events left (C4 note_on/off and E4 note_on/off)
    assert length(filtered_events) == 4

    # Check that D4 is gone and C4/E4 remain
    remaining_notes =
      filtered_events
      |> Enum.filter(&(&1.symbol in [:on, :off]))
      |> Enum.map(&Midifile.Event.note(&1))
      |> Enum.uniq()
      |> Enum.sort()

    assert remaining_notes == [60, 64], "Only C4 and E4 should remain (D4 should be removed)"

    # Filter by velocity
    velocity_filtered =
      Filter.process_notes(
        sequence,
        0,
        # Match notes with low velocity (C4:80, E4:70) for removal
        fn note -> note.velocity < 90 end,
        # Remove these notes
        :remove
      )

    velocity_events = List.first(velocity_filtered.tracks).events

    # Should have removed C4 and E4 (low velocity), leaving only D4
    remaining_vel_notes =
      velocity_events
      |> Enum.filter(&(&1.symbol in [:on, :off]))
      |> Enum.map(&Midifile.Event.note(&1))
      |> Enum.uniq()

    assert remaining_vel_notes == [62], "Only D4 should remain (velocity 100)"
  end

  test "a midi file that illustrates a bug in filtering on duration" do
    seq = Midifile.Reader.read("test/shorter_filter_test.mid")
    sonorities = MapEvents.track_to_sonorities(seq, 0)
    filtered_seq = Filter.process_notes(seq, 0, fn note -> note.duration < 0.2 end, :remove)
    filtered_sonorities = MapEvents.track_to_sonorities(filtered_seq, 0)
    assert [] == Enum.filter(filtered_sonorities, fn s -> Sonority.type(s) == :note and Sonority.duration(s) < 0.2 end)
    original_seq_total_duration = Enum.map(sonorities, &(&1.duration)) |> Enum.sum
    filtered_seq_total_duration = Enum.map(filtered_sonorities, &(&1.duration)) |> Enum.sum
    assert original_seq_total_duration == filtered_seq_total_duration
  end

end
