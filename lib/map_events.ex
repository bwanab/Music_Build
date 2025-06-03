defmodule MapEvents do
  @moduledoc """
  Functions for mapping MIDI track events to Sonority types.

  This module provides functionality to analyze a MIDI track and convert its
  events into a sequence of musical sonorities (Note, Chord, Rest). This higher-level
  representation makes it easier to work with musical concepts rather than raw MIDI events.

  The conversion process works in multiple steps:
  1. Identify all note events in the track and calculate their start/end times
  2. Group notes into chords based on timing overlap and tolerance settings
  3. Add rests between sound events
  4. Return chronologically ordered sonorities

  These sonorities can then be manipulated, analyzed, or converted back to MIDI events.

  ## Example

      # Convert MIDI track to sonorities
      sonorities = Midifile.MapEvents.track_to_sonorities(track, %{chord_tolerance: 10})

      # Process individual sonorities
      Enum.each(sonorities, fn sonority ->
        case Sonority.type(sonority) do
          :note -> IO.puts("Note: # {inspect(sonority.note)}")
          :chord -> IO.puts("Chord with # {length(sonority.notes)} notes")
          :rest -> IO.puts("Rest: # {Sonority.duration(sonority)} beats")
        end
      end)
  """

  alias Midifile.Event
  alias Midifile.Defaults

  @doc """
  Maps a track's MIDI events to separate channel tracks, each containing a sequence of Sonority types.

  This function analyzes a MIDI track and separates it by channel, creating individual
  tracks for each active channel. Each channel track contains sonorities that represent:
  - Notes: Single pitches with duration and velocity
  - Chords: Multiple notes sounding together with a common duration (within the same channel)
  - Rests: Periods of silence with a duration

  This approach preserves instrument separation since MIDI channels typically represent
  different instruments or parts.

  ## Parameters
    * `sequence` - A `Midifile.Sequence` struct containing the MIDI sequence
    * `track_number` - The index (0-based) of the track to process
    * `opts` - Options map with the following possible keys:
      * `:chord_tolerance` - Time in ticks within which notes are considered part of the same chord (default: 0)

  ## Returns
    * A map where keys are channel numbers (0-15) and values are lists of Sonority protocol implementations

  ## Examples

      # Basic usage with default options
      channel_tracks = Midifile.MapEvents.track_to_sonorities(sequence, 0)
      
      # Access individual channel tracks
      piano_track = channel_tracks[0]  # Channel 0 sonorities
      drums_track = channel_tracks[9]  # Channel 9 (drums) sonorities

      # With custom chord tolerance
      channel_tracks = Midifile.MapEvents.track_to_sonorities(sequence, 0, chord_tolerance: 10)
  """
  @spec track_to_sonorities(Midifile.Sequence, integer(), keyword()) :: %{integer() => [Sonority]}
  def track_to_sonorities(sequence, track_number, opts \\ []) do
    # Default options
    chord_tolerance = Keyword.get(opts, :chord_tolerance, 0)
    tpqn = sequence.ticks_per_quarter_note

    # Get the specified track
    track = Enum.at(sequence.tracks, track_number)

    # First, calculate absolute start and end times for all notes
    note_events = identify_note_events(track.events)

    # Group note events by channel
    notes_by_channel = Enum.group_by(note_events, fn note -> note.channel end)

    # Create sonorities for each channel
    Enum.into(notes_by_channel, %{}, fn {channel, channel_notes} ->
      sonorities = group_into_sonorities(channel_notes, chord_tolerance, tpqn)
      {channel, sonorities}
    end)
  end

  @doc """
  Identifies all note events in a track and calculates their absolute start/end times.

  This function pairs note-on and note-off events to create complete note objects
  with duration information. It handles both standard note-off events and note-on
  events with zero velocity (which are treated as note-offs according to the MIDI spec).

  The function also properly handles unmatched note-on events by assigning them
  an end time based on the last event in the track.

  ## Parameters
    * `events` - List of MIDI events from a track

  ## Returns
    * A list of note data maps with keys:
      * `:note` - The MIDI note number (0-127)
      * `:start_time` - Absolute start time in ticks from the beginning of the track
      * `:end_time` - Absolute end time in ticks
      * `:velocity` - The note's velocity (0-127)
      * `:channel` - The MIDI channel (0-15)

  ## Examples

      # Get all notes from a track with their timing information
      note_events = Midifile.MapEvents.identify_note_events(track.events)

      # Print information about each note
      Enum.each(note_events, fn note ->
        duration = note.end_time - note.start_time
        IO.puts("Note # {note.note} on channel # {note.channel}, " <>
                "duration: # {duration} ticks, velocity: # {note.velocity}")
      end)
  """
  def identify_note_events(events) do
    # Calculate absolute times for all events
    events_with_times = add_absolute_times(events)

    # Track note_on events to pair with note_offs
    # Format: %{{channel, note} => {abs_time, velocity}}
    {notes, note_on_events} =
      Enum.reduce(events_with_times, {[], %{}}, fn {event, abs_time}, {notes_acc, note_on_acc} ->
        case event do
          # Handle note_on events (velocity > 0)
          %{symbol: :on, bytes: [_status, note_num, velocity]} when velocity > 0 ->
            channel = Event.channel(event)
            key = {channel, note_num}
            # Store this note_on event with its start time and velocity
            new_note_on_acc = Map.put(note_on_acc, key, {abs_time, velocity})
            {notes_acc, new_note_on_acc}

          # Handle note_off events
          %{symbol: :off} = event ->
            channel = Event.channel(event)
            note_num = Event.note(event)
            key = {channel, note_num}

            # Check if we have a corresponding note_on event
            case Map.get(note_on_acc, key) do
              {start_time, velocity} ->
                # Create a note data structure
                note_data = %{
                  note: note_num,
                  start_time: start_time,
                  end_time: abs_time,
                  velocity: velocity,
                  channel: channel
                }

                # Add to notes list and remove from tracking
                {[note_data | notes_acc], Map.delete(note_on_acc, key)}

              nil ->
                # No corresponding note_on found, ignore
                {notes_acc, note_on_acc}
            end

          # Handle note_on with zero velocity (treated as note_off)
          %{symbol: :on, bytes: [_status, note_num, 0]} ->
            channel = Event.channel(event)
            key = {channel, note_num}

            # Check if we have a corresponding note_on event
            case Map.get(note_on_acc, key) do
              {start_time, velocity} ->
                # Create a note data structure
                note_data = %{
                  note: note_num,
                  start_time: start_time,
                  end_time: abs_time,
                  velocity: velocity,
                  channel: channel
                }

                # Add to notes list and remove from tracking
                {[note_data | notes_acc], Map.delete(note_on_acc, key)}

              nil ->
                # No corresponding note_on found, ignore
                {notes_acc, note_on_acc}
            end

          # Ignore all other event types
          _ ->
            {notes_acc, note_on_acc}
        end
      end)

    # For any note_on events without matching note_off events, assume they end at the track end
    # (this might happen in malformed MIDI files)
    unmatched_notes =
      Enum.map(note_on_events, fn {{channel, note_num}, {start_time, velocity}} ->
        # Use the last event's time as the end time or just a large value
        end_time =
          case List.last(events_with_times) do
            {_, time} -> time
            _ -> 999_999  # Just a large number for unmatched notes
          end

        %{
          note: note_num,
          start_time: start_time,
          end_time: end_time,
          velocity: velocity,
          channel: channel
        }
      end)

    Enum.concat(notes, unmatched_notes)
  end



  @doc """
  Groups identified notes into sonorities (Notes, Chords, Rests).

  This function analyzes the timing relationships between notes to determine when
  notes should be considered as individual notes, as parts of chords, or when
  rests should be inserted between sound events.

  The chord_tolerance parameter allows for some flexibility in chord detection.
  Notes that start within the tolerance window will be grouped into a chord,
  even if they don't start at exactly the same time. This is particularly useful
  for human performances or imperfectly quantized MIDI where chord notes might
  not be precisely aligned.

  ## Parameters
    * `note_events` - List of note data maps from identify_note_events/1
    * `chord_tolerance` - Time window (in ticks) for grouping notes into chords
    * `tpqn` - Ticks per quarter note value used to calculate durations in beats

  ## Returns
    * A list of Sonority protocol implementations (Note, Chord, Rest) in chronological order

  ## Examples

      # First identify notes
      note_events = Midifile.MapEvents.identify_note_events(track.events)

      # Then group them into sonorities with a tolerance of 10 ticks
      sonorities = Midifile.MapEvents.group_into_sonorities(note_events, 10, 960)

      # Count the different types of sonorities
      types = Enum.group_by(sonorities, &Sonority.type/1)
      IO.puts("Found # {length(types[:note] || [])} notes, " <>
              "# {length(types[:chord] || [])} chords, and " <>
              "# {length(types[:rest] || [])} rests")
  """
  def group_into_sonorities(note_events, chord_tolerance, tpqn \\ Defaults.default_ppqn) do
    # Find all unique start and end times
    all_times =
      note_events
      |> Enum.flat_map(fn note -> [note.start_time, note.end_time] end)
      |> Enum.uniq()
      |> Enum.sort()

    # For each time segment, determine what sonority is active
    {sonorities, _} =
      Enum.reduce(all_times, {[], nil}, fn current_time, {sonorities_acc, prev_time} ->
        # Skip the first time point (we need pairs of times)
        if prev_time == nil do
          {sonorities_acc, current_time}
        else
          # Find notes that are active during this time segment
          active_notes = Enum.filter(note_events, fn note ->
            note.start_time <= prev_time + chord_tolerance && note.end_time >= current_time
          end)

          #IO.inspect(current_time, label: "current time")
          #IO.inspect(prev_time, label: "prev time")
          num_quarter_notes = (current_time - prev_time) / tpqn
          #IO.inspect(number_of_quarter_notes, label: "number qn")
          #IO.inspect(duration, label: "duration")
          new_sonority = cond do
            # No notes active - create a Rest
            Enum.empty?(active_notes) ->
              Rest.new(num_quarter_notes)

            # One note active - create a Note
            length(active_notes) == 1 ->
              [note] = active_notes
              # Convert MIDI note to Note struct
              MidiNote.midi_to_note(note.note, num_quarter_notes, note.velocity)

            # Multiple notes active - create a Chord
            true ->
              # Convert each MIDI note to a Note struct
              notes = Enum.map(active_notes, fn note ->
                MidiNote.midi_to_note(note.note, num_quarter_notes, note.velocity)
              end)
              # Detect chord structure and create using enhanced API
              #IO.inspect(notes, label: "notes")
              create_enhanced_chord(notes, num_quarter_notes)
          end

          # Only add sonority if it has duration
          if Sonority.duration(new_sonority) != nil do
            {[new_sonority | sonorities_acc], current_time}
          else
            {sonorities_acc, current_time}
          end
        end
      end)

    Enum.reverse(sonorities)
  end

    @doc false
  # Creates a chord using the enhanced Chord API
  # Attempts to detect the chord structure (root, quality) from the given notes
  def create_enhanced_chord(notes, duration) do
    # Fallback to old API if detection fails
    fallback_fn = fn -> Chord.new(notes, duration) end

    try do
      {root, quality, octave} = detect_chord_from_notes(notes)

      # Create the basic chord
      basic_chord = Chord.new(root, quality, octave, duration)

      # Check if any notes aren't part of the basic chord
      # If found, add them as additions
      chord_notes = basic_chord
                    |> Sonority.to_notes()
                    |> Enum.map(fn n -> n.note end)
                    |> MapSet.new()

      note_pitches = notes
                     |> Enum.map(fn n -> n.note end)
                     |> MapSet.new()

      additions = MapSet.difference(note_pitches, chord_notes)
      omissions = MapSet.difference(chord_notes, note_pitches)

      # If there are additions, add them to the chord
      rval = if MapSet.size(additions) > 0 do
        addition_notes = Enum.filter(notes, fn n ->
          MapSet.member?(additions, n.note)
        end)

        Chord.with_additions(basic_chord, addition_notes)
      else
        basic_chord
      end

      # If there are omissions
      if MapSet.size(omissions) > 0 do
        omitted_notes = Enum.with_index(rval.notes)
          |> Enum.filter(fn {n, _} -> MapSet.member?(omissions, n.note) end)
          |> Enum.map(fn {_, i} -> i
        end)

        Chord.with_omissions(rval, omitted_notes)
      else
        rval
      end

    rescue
      _ -> fallback_fn.()
    end
  end

  @doc false
  # Calculate absolute time for each event based on delta times
  #
  # In MIDI files, event timing is stored as delta times (time since the previous event).
  # This function converts these relative timings to absolute times from the start of the track,
  # which makes it easier to analyze timing relationships between events.
  #
  # Returns a list of {event, absolute_time} tuples in the original event order.
  defp add_absolute_times(events) do
    {events_with_times, _} =
      Enum.reduce(events, {[], 0}, fn event, {acc, current_time} ->
        new_time = current_time + event.delta_time
        {[{event, new_time} | acc], new_time}
      end)

    Enum.reverse(events_with_times)
  end


  @doc false
  # Detects the root, quality and octave of a chord from a list of notes
  def detect_chord_from_notes(notes) do
    # Common chord structures with their root positions
    #IO.inspect(notes, label: "detect_chord_from_notes - notes")
    chord_structures = [
      # Major triads
      {0, :major, MapSet.new([0, 4, 7])},
      # Minor triads
      {0, :minor, MapSet.new([0, 3, 7])},
      # Dominant seventh
      {0, :dominant_seventh, MapSet.new([0, 4, 7, 10])},
      # Major seventh
      {0, :major_seventh, MapSet.new([0, 4, 7, 11])},
      # Minor seventh
      {0, :minor_seventh, MapSet.new([0, 3, 7, 10])},
      # Diminished
      {0, :diminished, MapSet.new([0, 3, 6])},
      # Augmented
      {0, :augmented, MapSet.new([0, 4, 8])},
      # Sus4
      {0, :sus4, MapSet.new([0, 5, 7])},
      # Sus2
      {0, :sus2, MapSet.new([0, 2, 7])}
    ]

    # Convert notes to MIDI note numbers
    midi_notes = Enum.map(notes, fn note ->
      MidiNote.note_to_midi(note).note_number
    end)

    # Find minimum MIDI note to use as reference
    min_midi = Enum.min(midi_notes)

    # Calculate semitone distances from lowest note
    semitones = Enum.map(midi_notes, fn midi ->
      rem(midi - min_midi, 12)
    end) |> MapSet.new()

    # Score each possible chord structure
    scored_matches = Enum.map(chord_structures, fn {root_offset, quality, intervals} ->
      # How many notes in the chord match this structure
      matching_notes = MapSet.intersection(semitones, intervals)
      match_score = MapSet.size(matching_notes)

      # Prefer structures where most/all notes are accounted for
      coverage = match_score / MapSet.size(semitones)

      # Prefer structures that have the root note
      has_root = MapSet.member?(semitones, root_offset)
      root_score = if has_root, do: 1, else: 0

      # Calculate total score - higher is better
      total_score = match_score + coverage + root_score

      # Determine the root note (based on the structure's root offset from lowest note)
      root_midi = min_midi + root_offset

      # Get the note and octave from the MIDI number
      note = MidiNote.midi_to_note(root_midi, 1, 64) # Default velocity of 64
      root_name = note.note
      root_octave = note.octave

      # IO.inspect({total_score, {root_name, quality, root_octave}}, label: "score")
      {total_score, {root_name, quality, root_octave}}
    end)

    # Select the highest scoring match
    {_score, best_match} = Enum.max_by(scored_matches, fn {score, _} -> score end)
    best_match
  end

  def get_program_changes(seq, track_num) do
    track = Enum.at(seq.tracks, track_num)
    events = track.events
    Enum.filter(events, fn e -> e.symbol == :on end)
    |> Enum.map(fn e ->
      Integer.to_string(Enum.at(e.bytes, 0), 2)
      |> String.slice(4..7)
      |> String.to_integer(2)
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end


end
