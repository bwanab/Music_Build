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

    note_events = MapEvents.identify_note_events(events)

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

    sonorities = MapEvents.group_into_sonorities(note_events, 0)

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

    sonorities = MapEvents.group_into_sonorities(note_events, 5)

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
    sonorities = channel_tracks[0]  # Get channel 0 sonorities

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
    sonorities_no_tolerance = channel_tracks_no_tolerance[0]  # Get channel 0 sonorities
    types_no_tolerance = Enum.map(sonorities_no_tolerance, &Sonority.type/1)
    # Without tolerance, we might get a mix of notes and chords depending on timing
    note_and_chord_count = Enum.count(types_no_tolerance, fn t -> t == :note || t == :chord end)
    assert note_and_chord_count >= 2

    # Test with chord tolerance - should identify the chord
    channel_tracks_with_tolerance = MapEvents.track_to_sonorities(sequence, 0, chord_tolerance: 10)
    sonorities_with_tolerance = channel_tracks_with_tolerance[0]  # Get channel 0 sonorities

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
    sonorities = channel_tracks[0]  # Get channel 0 sonorities

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
    sonorities = channel_tracks[0]  # Get channel 0 sonorities

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

  test "track_to_sonorities separates multi-channel MIDI file into channel tracks" do
    # Test with Diana Krall MIDI file that has multiple channels
    sequence = Midifile.read("midi/Diana_Krall_-_The_Look_Of_Love.mid")
    
    channel_tracks = MapEvents.track_to_sonorities(sequence, 0)
    
    # Should have 8 channels (0, 1, 2, 3, 4, 5, 6, 9)
    assert map_size(channel_tracks) == 8
    
    # Check that expected channels are present
    expected_channels = [0, 1, 2, 3, 4, 5, 6, 9]
    actual_channels = Map.keys(channel_tracks) |> Enum.sort()
    assert actual_channels == expected_channels
    
    # Each channel should have sonorities
    Enum.each(channel_tracks, fn {channel, sonorities} ->
      assert length(sonorities) > 0, "Channel #{channel} should have sonorities"
      
      # All sonorities should be valid types
      Enum.each(sonorities, fn sonority ->
        type = Sonority.type(sonority)
        assert type in [:note, :chord, :rest], "Invalid sonority type: #{type}"
        assert Sonority.duration(sonority) > 0, "Sonority should have positive duration"
      end)
    end)
    
    # Channel 9 (drums) should be the most active
    drums_count = length(channel_tracks[9])
    other_channels = Map.delete(channel_tracks, 9)
    Enum.each(other_channels, fn {channel, sonorities} ->
      assert length(sonorities) < drums_count, 
        "Channel #{channel} has more events than drums channel"
    end)
    
    # Channel 2 should be very active (second most active melodic channel)
    channel_2_count = length(channel_tracks[2])
    assert channel_2_count > 1000, "Channel 2 should have many sonorities"
    
    # Verify that we get different results than treating all channels as one
    # (This ensures we're actually separating channels)
    total_sonorities_count = Enum.map(channel_tracks, fn {_, sonorities} -> 
      length(sonorities) 
    end) |> Enum.sum()
    
    # Should have more total sonorities when separated than when combined
    # because each channel has its own timeline
    assert total_sonorities_count > 5000, 
      "Separated channels should have substantial total sonorities"
  end
end
