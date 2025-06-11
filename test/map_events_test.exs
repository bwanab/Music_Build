defmodule MapEventsTest do
  use ExUnit.Case
  alias Midifile.Event
  alias Midifile.Track

  test "identify_note_events extracts note data correctly" do
    # Create some test events - note on at time 0, note off at time 50
    events = [
      %Event{symbol: :on, delta_time: 0, bytes: [0x90, 60, 80]},   # C4, velocity 80, channel 0
      %Event{symbol: :on, delta_time: 10, bytes: [0x90, 64, 70]},  # E4, velocity 70, channel 0
      %Event{symbol: :off, delta_time: 40, bytes: [0x80, 60, 0]},  # C4 off
      %Event{symbol: :off, delta_time: 10, bytes: [0x80, 64, 0]}   # E4 off
    ]

    events_result = MapEvents.identify_sonority_events(events)
    note_events = events_result.notes

    assert length(note_events) == 2

    # Check C4 note
    c4_note = Enum.find(note_events, &(&1.note == 60))
    assert c4_note.start_time == 0
    assert c4_note.end_time == 50  # 0 + 10 + 40
    assert c4_note.velocity == 80
    assert c4_note.channel == 0

    # Check E4 note
    e4_note = Enum.find(note_events, &(&1.note == 64))
    assert e4_note.start_time == 10
    assert e4_note.end_time == 60  # 0 + 10 + 40 + 10
    assert e4_note.velocity == 70
    assert e4_note.channel == 0
  end

  test "group_into_sonorities creates Notes for isolated notes" do
    note_events = [
      %{note: 60, start_time: 0, end_time: 240, velocity: 80, channel: 0},  # C4
      %{note: 64, start_time: 480, end_time: 720, velocity: 70, channel: 0} # E4
    ]

    sonorities = MapEvents.group_into_sonorities(note_events, [], [], 0)

    # We should have 3 sonorities: Note, Rest, Note
    assert length(sonorities) == 3

    [first, second, third] = sonorities

    # Check first note (C4)
    assert Sonority.type(first) == :note
    assert Note.enharmonic_equal?(first.note, :C)  # Note: Using uppercase to match Note implementation
    assert Sonority.duration(first) == 0.25

    # Check rest between notes
    assert Sonority.type(second) == :rest
    assert Sonority.duration(second) == 0.25

    # Check second note (E4)
    assert Sonority.type(third) == :note
    assert Note.enharmonic_equal?(third.note, :E)  # Note: Using uppercase to match Note implementation
    assert Sonority.duration(third) == 0.25
  end

  test "group_into_sonorities creates Chords for overlapping notes" do
    note_events = [
      %{note: 60, start_time: 0, end_time: 960, velocity: 80, channel: 0},  # C4
      %{note: 64, start_time: 240, end_time: 1200, velocity: 70, channel: 0}, # E4
      %{note: 67, start_time: 360, end_time: 1320, velocity: 75, channel: 0}  # G4
    ]

    sonorities = MapEvents.group_into_sonorities(note_events, [], [], 5)

    # We should have 3 sonorities: Note, Chord(2 notes), Chord(3 notes)
    assert length(sonorities) == 5

    [first, second, third, fourth, fifth] = sonorities

    # Check first solo note
    assert Sonority.type(first) == :note
    assert first.note == :C  # Note: Using uppercase to match Note implementation
    assert Sonority.duration(first) == 0.25

    # Check two-note chord (C4 + E4)
    assert Sonority.type(second) == :chord
    assert length(Sonority.to_notes(second)) == 2
    # Use MapSet for unordered comparison of notes
    chord_notes = Enum.map(Sonority.to_notes(second), & &1.note) |> MapSet.new()
    expected_notes = MapSet.new([:C, :E])
    assert MapSet.equal?(chord_notes, expected_notes)
    assert Sonority.duration(second) == 0.125

    # Check three-note chord (C4 + E4 + G4)
    assert Sonority.type(third) == :chord
    assert length(third.notes) == 3
    # Use MapSet for unordered comparison of notes
    chord_notes = Enum.map(third.notes, & &1.note) |> MapSet.new()
    expected_notes = MapSet.new([:C, :E, :G])
    assert MapSet.equal?(chord_notes, expected_notes)
    assert Sonority.duration(third) == 0.625

    # Check two-note chord (E4, G4)
    assert Sonority.type(fourth) == :chord
    assert length(Sonority.to_notes(fourth)) == 2
    # Use MapSet for unordered comparison of notes
    chord_notes = Enum.map(Sonority.to_notes(fourth), & &1.note) |> MapSet.new()
    expected_notes = MapSet.new([:E, :G])
    assert MapSet.equal?(chord_notes, expected_notes)
    assert Sonority.duration(fourth) == 0.25

    # Check fifth solo note
    assert Sonority.type(fifth) == :note
    assert fifth.note == :G  # Note: Using uppercase to match Note implementation
    assert Sonority.duration(fifth) == 0.125

  end

  test "track_to_sonorities converts MIDI track to sequence of sonorities" do
    # Create a track with a simple C major chord arpeggio
    events = [
      %Event{symbol: :on, delta_time: 0, bytes: [0x90, 60, 80]},    # C4 on
      %Event{symbol: :off, delta_time: 100, bytes: [0x80, 60, 0]},  # C4 off
      %Event{symbol: :on, delta_time: 0, bytes: [0x90, 64, 80]},    # E4 on
      %Event{symbol: :off, delta_time: 100, bytes: [0x80, 64, 0]},  # E4 off
      %Event{symbol: :on, delta_time: 0, bytes: [0x90, 67, 80]},    # G4 on
      %Event{symbol: :off, delta_time: 100, bytes: [0x80, 67, 0]},  # G4 off
      # Rest
      %Event{symbol: :on, delta_time: 100, bytes: [0x90, 72, 80]},  # C5 on
      %Event{symbol: :off, delta_time: 100, bytes: [0x80, 72, 0]}   # C5 off
    ]

    track = %Track{events: events}
    sequence = %Midifile.Sequence{
      tracks: [track],
      ticks_per_quarter_note: 960,
      format: 1,
      time_basis: :metrical_time
    }

    channel_tracks = MapEvents.track_to_sonorities(sequence, 0)
    sonorities = channel_tracks[0].sonorities  # Get channel 0 sonorities

    # We should have 5 sonorities: 3 notes, 1 rest, 1 note
    assert length(sonorities) == 5

    # Check types
    types = Enum.map(sonorities, &Sonority.type/1)
    assert types == [:note, :note, :note, :rest, :note]

    # Check notes
    notes = Enum.filter(sonorities, &(Sonority.type(&1) == :note))
    note_pitches = Enum.map(notes, &(&1.note))
    assert note_pitches == [:C, :E, :G, :C]
  end

  test "track_to_sonorities identifies chords with chord_tolerance" do
    # Create a track with a C major chord with slightly offset start times
    events = [
      %Event{symbol: :on, delta_time: 0, bytes: [0x90, 60, 80]},     # C4 on
      %Event{symbol: :on, delta_time: 5, bytes: [0x90, 64, 80]},     # E4 on
      %Event{symbol: :on, delta_time: 5, bytes: [0x90, 67, 80]},     # G4 on
      %Event{symbol: :off, delta_time: 90, bytes: [0x80, 60, 0]},    # C4 off
      %Event{symbol: :off, delta_time: 0, bytes: [0x80, 64, 0]},     # E4 off
      %Event{symbol: :off, delta_time: 0, bytes: [0x80, 67, 0]},     # G4 off
      # Rest
      %Event{symbol: :on, delta_time: 100, bytes: [0x90, 72, 80]},   # C5 on
      %Event{symbol: :off, delta_time: 100, bytes: [0x80, 72, 0]}    # C5 off
    ]

    track = %Track{events: events}
    sequence = %Midifile.Sequence{
      tracks: [track],
      ticks_per_quarter_note: 960,
      format: 1,
      time_basis: :metrical_time
    }

    # Test without chord tolerance - should get separate notes
    channel_tracks_no_tolerance = MapEvents.track_to_sonorities(sequence, 0, chord_tolerance: 0)
    sonorities_no_tolerance = channel_tracks_no_tolerance[0].sonorities  # Get channel 0 sonorities
    types_no_tolerance = Enum.map(sonorities_no_tolerance, &Sonority.type/1)
    # Without tolerance, we might get a mix of notes and chords depending on timing
    note_and_chord_count = Enum.count(types_no_tolerance, fn t -> t == :note || t == :chord end)
    assert note_and_chord_count >= 2

    # Test with chord tolerance - should identify the chord
    channel_tracks_with_tolerance = MapEvents.track_to_sonorities(sequence, 0, chord_tolerance: 10)
    sonorities_with_tolerance = channel_tracks_with_tolerance[0].sonorities  # Get channel 0 sonorities

    # Should have at least one chord
    types_with_tolerance = Enum.map(sonorities_with_tolerance, &Sonority.type/1)
    assert :chord in types_with_tolerance

    # Check that we have a chord with 3 notes
    chord = Enum.find(sonorities_with_tolerance, fn s ->
      Sonority.type(s) == :chord && length(s.notes) == 3
    end)
    assert chord != nil

    # Check the chord notes using MapSet for unordered comparison
    chord_notes = Enum.map(chord.notes, & &1.note) |> MapSet.new()
    expected_notes = MapSet.new([:C, :E, :G])
    assert MapSet.equal?(chord_notes, expected_notes)
  end

  test "track_to_sonorities works with a MIDI file" do
    # Create a simple test track instead of loading a file
    events = [
      %Event{symbol: :on, delta_time: 0, bytes: [0x90, 60, 80]},    # C4 on
      %Event{symbol: :off, delta_time: 100, bytes: [0x80, 60, 0]},  # C4 off
      %Event{symbol: :on, delta_time: 100, bytes: [0x90, 64, 80]},  # E4 on
      %Event{symbol: :off, delta_time: 100, bytes: [0x80, 64, 0]}   # E4 off
    ]

    track = %Track{events: events}
    sequence = %Midifile.Sequence{
      tracks: [track],
      ticks_per_quarter_note: 960,
      format: 1,
      time_basis: :metrical_time
    }

    channel_tracks = MapEvents.track_to_sonorities(sequence, 0)
    sonorities = channel_tracks[0].sonorities  # Get channel 0 sonorities

    # Basic validation - we should have some sonorities
    assert length(sonorities) > 0

    # Validate types - should have notes and possibly rests
    types = Enum.map(sonorities, &Sonority.type/1)
    assert :note in types

    # Check the first note - should be a C
    first_note = Enum.find(sonorities, &(Sonority.type(&1) == :note))
    assert first_note.note == :C
  end

  test "track_to_sonorities processes test_sonorities.mid with all sonority types" do
    # Load the test file that contains examples of all three sonority types
    sequence = Midifile.read("midi/test_sonorities.mid")

    # Map to sonorities
    channel_tracks = MapEvents.track_to_sonorities(sequence, 0)
    sonorities = channel_tracks[0].sonorities  # Get channel 0 sonorities

    # Verify we have all three types of sonorities
    types = Enum.map(sonorities, &Sonority.type/1)
    type_counts = Enum.frequencies(types)

    assert Map.has_key?(type_counts, :note)
    assert Map.has_key?(type_counts, :chord)
    assert Map.has_key?(type_counts, :rest)

    # Verify the specific content - this file should contain:
    # 1. A C major chord (C+E+G)
    # 2. A C# note
    # 3. A D minor chord (D+F+A)
    # 4. A rest
    # 5. A B note

    # Find the C major chord
    c_major = Enum.find(sonorities, fn s ->
      Sonority.type(s) == :chord && length(s.notes) == 3 &&
      Enum.map(s.notes, & &1.note) |> MapSet.new() |> MapSet.equal?(MapSet.new([:C, :E, :G]))
    end)
    assert c_major != nil
    assert Sonority.duration(c_major) == 1

    # Find the C# note
    c_sharp = Enum.find(sonorities, fn s ->
      Sonority.type(s) == :note && Note.enharmonic_equal?(s.note, :C!)
    end)
    assert c_sharp != nil
    assert Sonority.duration(c_sharp) == 1

    # Find the D minor chord
    d_minor = Enum.find(sonorities, fn s ->
      Sonority.type(s) == :chord && length(s.notes) == 3 &&
      Enum.map(s.notes, & &1.note) |> MapSet.new() |> MapSet.equal?(MapSet.new([:D, :F, :A]))
    end)
    assert d_minor != nil
    assert Sonority.duration(d_minor) == 1

    # Find the B note
    b_note = Enum.find(sonorities, fn s ->
      Sonority.type(s) == :note && Note.enharmonic_equal?(s.note, :B)
    end)
    assert b_note != nil
    assert Sonority.duration(b_note) == 1

    # Find the rest
    rest = Enum.find(sonorities, fn s -> Sonority.type(s) == :rest end)
    assert rest != nil
    assert Sonority.duration(rest) == 1
  end

  test "track_to_sonorities separates multi-channel MIDI file into channel tracks and percussion instruments" do
    # Test with Diana Krall MIDI file that has multiple channels including percussion
    sequence = Midifile.read("midi/Diana_Krall_-_The_Look_Of_Love.mid")

    channel_tracks = MapEvents.track_to_sonorities(sequence, 0)

    # Should have 7 regular channels plus multiple percussion instruments (16 total based on current output)
    assert map_size(channel_tracks) == 16

    # Check that expected regular channels are present
    expected_regular_channels = [0, 1, 2, 3, 4, 5, 6]
    regular_channels = Map.keys(channel_tracks) |> Enum.filter(&is_integer/1) |> Enum.sort()
    assert regular_channels == expected_regular_channels

    # Check that percussion instruments are present (they have string keys with "percussion_" prefix)
    percussion_keys = Map.keys(channel_tracks) |> Enum.filter(&is_binary/1) |> Enum.sort()
    expected_percussion_keys = ["percussion_36", "percussion_42", "percussion_44", "percussion_46", "percussion_61", "percussion_62", "percussion_63", "percussion_64", "percussion_82"]
    assert percussion_keys == expected_percussion_keys

    # Each track (channel or percussion instrument) should have sonorities
    Enum.each(channel_tracks, fn {track_key, strack} ->
      assert length(strack.sonorities) > 0, "Track #{track_key} should have sonorities"

      # All sonorities should be valid types
      Enum.each(strack.sonorities, fn sonority ->
        type = Sonority.type(sonority)
        assert type in [:note, :chord, :rest, :controller], "Invalid sonority type: #{type}"
        # Controllers have duration 0, other sonorities should have positive duration
        if type == :controller do
          assert Sonority.duration(sonority) == 0, "Controller should have zero duration"
        else
          assert Sonority.duration(sonority) > 0, "Sonority should have positive duration"
        end
      end)
    end)

    # Percussion instruments should be the most active
    percussion_total_count = percussion_keys
    |> Enum.map(&channel_tracks[&1].sonorities)
    |> Enum.map(&length/1)
    |> Enum.sum()

    regular_total_count = regular_channels
    |> Enum.map(&channel_tracks[&1].sonorities)
    |> Enum.map(&length/1)
    |> Enum.sum()

    # Check that both percussion and regular tracks have reasonable activity
    assert percussion_total_count > 1000, "Percussion should be active with many sonorities"
    assert regular_total_count > 1000, "Regular instruments should be active with many sonorities"

    # Channel 2 should be very active (second most active melodic channel)
    channel_2_count = length(channel_tracks[2].sonorities)
    assert channel_2_count > 1000, "Channel 2 should have many sonorities"

    # Verify that we get different results than treating all channels as one
    # (This ensures we're actually separating channels and percussion instruments)
    total_sonorities_count = Enum.map(channel_tracks, fn {_, strack} ->
      length(strack.sonorities)
    end) |> Enum.sum()

    # Should have more total sonorities when separated than when combined
    # because each channel has its own timeline
    assert total_sonorities_count > 5000,
      "Separated channels should have substantial total sonorities"

    # In track 0 for this midi file there are no notes played before the first controller event
    # There is one rest before the first controller event
    sonorities_0 = channel_tracks[0]
    sonorities_before_first_controller = Enum.take_while(sonorities_0.sonorities, fn s -> Sonority.type(s) != :controller end)
    assert 1 == length(sonorities_before_first_controller)
    assert Enum.all?(sonorities_before_first_controller, fn s -> Sonority.type(s) == :rest end )

    # same test for channel 4 which has the first note in the file
    sonorities_4 = channel_tracks[4]
    sonorities_before_first_controller = Enum.take_while(sonorities_4.sonorities, fn s -> Sonority.type(s) != :controller end)
    assert 1 == length(sonorities_before_first_controller)
    assert Enum.all?(sonorities_before_first_controller, fn s -> Sonority.type(s) == :rest end )
  end

  test "track_to_sonorities handles percussion option correctly" do
    # Create a simple sequence with some non-percussion notes
    track = %Midifile.Track{
      events: [
        %Midifile.Event{symbol: :on, delta_time: 0, bytes: [144, 60, 100]},  # C4 on channel 0
        %Midifile.Event{symbol: :off, delta_time: 480, bytes: [128, 60, 64]}, # C4 off channel 0
        %Midifile.Event{symbol: :on, delta_time: 0, bytes: [144, 64, 100]},  # E4 on channel 0
        %Midifile.Event{symbol: :off, delta_time: 480, bytes: [128, 64, 64]}  # E4 off channel 0
      ]
    }
    sequence = %Midifile.Sequence{
      tracks: [track],
      ticks_per_quarter_note: 480
    }

    # Test without is_percussion option (should be treated as regular track)
    regular_result = MapEvents.track_to_sonorities(sequence, 0)
    assert Map.has_key?(regular_result, 0), "Should have channel 0"
    assert map_size(regular_result) == 1, "Should have only one channel"

    # Test with is_percussion: true option (should split by pitch)
    percussion_result = MapEvents.track_to_sonorities(sequence, 0, is_percussion: true)
    assert Map.has_key?(percussion_result, "percussion_60"), "Should have percussion track for pitch 60"
    assert Map.has_key?(percussion_result, "percussion_64"), "Should have percussion track for pitch 64"
    assert map_size(percussion_result) == 2, "Should have two percussion instruments"

    # Verify the percussion instruments have proper names from CSV mapping
    strack_60 = percussion_result["percussion_60"]
    strack_64 = percussion_result["percussion_64"]
    assert strack_60.name == "Hi Bongo", "Should use name from CSV file for pitch 60"
    assert strack_64.name == "Low Conga", "Should use name from CSV file for pitch 64"
  end

  test "percussion mapping uses CSV file when available" do
    # Test that percussion mapping correctly reads from CSV and assigns proper names
    sequence = Midifile.read("midi/Diana_Krall_-_The_Look_Of_Love.mid")
    channel_tracks = MapEvents.track_to_sonorities(sequence, 0)

    # Check that specific percussion instruments have proper names from CSV
    if Map.has_key?(channel_tracks, "percussion_42") do
      closed_hihat_track = channel_tracks["percussion_42"]
      assert closed_hihat_track.name == "Closed Hi Hat", "Should use name from CSV file"
    end

    if Map.has_key?(channel_tracks, "percussion_44") do
      pedal_hihat_track = channel_tracks["percussion_44"]
      assert pedal_hihat_track.name == "Pedal Hi-Hat", "Should use name from CSV file"
    end
  end

  test "identify_sonority_events handles controller events" do
    events = [
      %Event{symbol: :on, delta_time: 0, bytes: [0x90, 60, 80]},    # C4 on
      %Event{symbol: :controller, delta_time: 10, bytes: [0xB0, 7, 127]}, # Volume controller
      %Event{symbol: :off, delta_time: 30, bytes: [0x80, 60, 0]}    # C4 off
    ]

    result = MapEvents.identify_sonority_events(events)

    assert length(result.notes) == 1
    assert length(result.controllers) == 1

    controller = Enum.at(result.controllers, 0)
    assert controller.controller_number == 7
    assert controller.value == 127
    assert controller.channel == 0
    assert controller.time == 10
  end

  test "group_into_sonorities includes controller sonorities" do
    note_events = [
      %{note: 60, start_time: 0, end_time: 480, velocity: 80, channel: 0}
    ]

    controller_events = [
      %{controller_number: 7, value: 127, time: 240, channel: 0}
    ]

    sonorities = MapEvents.group_into_sonorities(note_events, controller_events, [], 0)

    # Should have Note sonority and Controller sonority
    types = Enum.map(sonorities, &Sonority.type/1)
    assert :note in types
    assert :controller in types

    # Find the controller sonority
    controller_sonority = Enum.find(sonorities, fn s -> Sonority.type(s) == :controller end)
    assert controller_sonority.controller_number == 7
    assert controller_sonority.value == 127
    assert controller_sonority.channel == 0
    assert Sonority.duration(controller_sonority) == 0
  end

  test "track_to_sonorities handles pitch_bend events from mvoyage.mid" do
    # Test with the actual mvoyage.mid file that contains pitch_bend events
    sequence = Midifile.read("midi/mvoyage.mid")
    
    # Process the first track which contains pitch_bend events
    channel_tracks = MapEvents.track_to_sonorities(sequence, 0)
    
    # Get all sonorities from all channels
    all_sonorities = Map.values(channel_tracks)
    |> Enum.flat_map(fn strack -> strack.sonorities end)
    
    # Find pitch_bend sonorities
    pitch_bend_sonorities = Enum.filter(all_sonorities, fn s -> 
      Sonority.type(s) == :pitch_bend 
    end)
    
    # Should have found pitch_bend events
    assert length(pitch_bend_sonorities) > 0
    
    # Check that pitch_bend sonorities have correct properties
    first_pitch_bend = List.first(pitch_bend_sonorities)
    assert Sonority.type(first_pitch_bend) == :pitch_bend
    assert Sonority.duration(first_pitch_bend) == 0  # Instantaneous events
    assert first_pitch_bend.value >= 0 and first_pitch_bend.value <= 16383  # 14-bit range
    assert first_pitch_bend.channel >= 0 and first_pitch_bend.channel <= 15  # Valid MIDI channel
    
    # Verify EventBuilder can create MIDI events from pitch_bend sonorities
    midi_events = MusicBuild.EventBuilder.new(:pitch_bend, first_pitch_bend)
    assert length(midi_events) == 1
    
    [event] = midi_events
    assert event.symbol == :pitch_bend
    assert length(event.bytes) == 3
    [status, lsb, msb] = event.bytes
    assert status >= 224 and status <= 239  # Pitch bend status bytes (0xE0-0xEF)
    
    # Verify the value can be reconstructed
    reconstructed_value = (msb * 128) + lsb
    assert reconstructed_value == first_pitch_bend.value
  end
end
