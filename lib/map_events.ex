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
  @spec track_to_sonorities(Midifile.Sequence, integer(), keyword()) :: %{integer() => STrack}
  def track_to_sonorities(sequence, track_number, opts \\ []) do
    # Default options
    chord_tolerance = Keyword.get(opts, :chord_tolerance, 0)
    is_percussion = Keyword.get(opts, :is_percussion, false)
    tpqn = sequence.ticks_per_quarter_note

    # Get the specified track
    track = Enum.at(sequence.tracks, track_number)
    track_name = MusicBuild.Util.get_track_name(track)
    track_name = if String.length(track_name) == 0 do
      Keyword.get(opts, :track_name, "UnNamed")
    end

    # First, calculate absolute start and end times for all notes and controllers
    sonority_events = identify_sonority_events(track.events)
    note_events = sonority_events.notes
    controller_events = sonority_events.controllers

    # Check if this track contains percussion (channel 9, which is channel 10 in 1-based numbering)
    has_percussion = Enum.any?(note_events, fn note -> note.channel == 9 end)

    # Determine if we should use percussion processing
    use_percussion_processing = has_percussion or is_percussion

    if use_percussion_processing do
      # Process percussion tracks by splitting on pitch rather than channel
      process_percussion_track(note_events, controller_events, track_name, chord_tolerance, tpqn, sequence, track_number)
    else
      # Original channel-based processing for non-percussion tracks
      process_regular_track(note_events, controller_events, track_name, chord_tolerance, tpqn, sequence, track_number)
    end
  end

  @doc false
  # Process regular (non-percussion) tracks by grouping events by channel
  defp process_regular_track(note_events, controller_events, track_name, chord_tolerance, tpqn, sequence, track_number) do
    # Group note events and controller events by channel
    notes_by_channel = Enum.group_by(note_events, fn note -> note.channel end)
    controllers_by_channel = Enum.group_by(controller_events, fn controller -> controller.channel end)

    # Get program changes for each channel (which already includes instrument mapping)
    program_changes = get_program_changes(sequence, track_number)

    # Calculate channel delays using significant event timing (on, off, controller)
    significant_events = read_significant_events(sequence, track_number)
    channel_delays = calculate_channel_delays_from_significant_events(significant_events, tpqn)

    # Create sonorities for each channel with proper timing
    Enum.into(notes_by_channel, %{}, fn {channel, channel_notes} ->
      channel_controllers = Map.get(controllers_by_channel, channel, [])
      sonorities = group_into_sonorities(channel_notes, channel_controllers, chord_tolerance, tpqn)

      # Get the delay for this channel based on note-on events
      delay_quarter_notes = Map.get(channel_delays, channel, 0)

      # If this channel starts later, prepend a rest sonority
      final_sonorities = if delay_quarter_notes > 0 do
        initial_rest = Rest.new(delay_quarter_notes, channel)
        [initial_rest | sonorities]
      else
        sonorities
      end

      # Determine instrument name from program change mapping
      {program, program_number} = case Map.get(program_changes, channel) do
        nil -> {0, 0}
        {program, program_number} -> {program, program_number}
      end
      channel_instrument_name = case program do
        nil -> "#{track_name} Ch#{channel}"  # Fallback to channel number
        instrument_name -> instrument_name
      end

      {channel, STrack.new(channel_instrument_name, final_sonorities, tpqn, :instrument, program_number)}
    end)
  end

  @doc false
  # Process percussion tracks by grouping events by pitch (instrument)
  defp process_percussion_track(note_events, controller_events, base_track_name, chord_tolerance, tpqn, sequence, track_number) do
    # Load percussion instrument mapping
    percussion_map = read_percussion_mapping()

    # Check if we have mixed percussion (channel 9) and non-percussion events
    has_channel_9 = Enum.any?(note_events, fn note -> note.channel == 9 end)
    has_other_channels = Enum.any?(note_events, fn note -> note.channel != 9 end)

    percussion_events = if has_channel_9 and has_other_channels do
      # Mixed track - separate percussion and non-percussion
      {perc_events, non_perc_events} = Enum.split_with(note_events, fn note -> note.channel == 9 end)
      {perc_controllers, non_perc_controllers} = Enum.split_with(controller_events, fn controller -> controller.channel == 9 end)

      # Process non-percussion events using regular processing
      non_perc_result = if length(non_perc_events) > 0 do
        process_regular_track(non_perc_events, non_perc_controllers, base_track_name, chord_tolerance, tpqn, sequence, track_number)
      else
        %{}
      end

      # Continue with percussion events and merge results later
      {{perc_events, perc_controllers}, non_perc_result}
    else
      # Either pure channel 9 percussion OR is_percussion: true was set for all events
      # EXPERIMENTAL: The is_percussion option allows treating any track as percussion,
      # splitting events by pitch rather than channel even for non-percussion instruments
      {{note_events, controller_events}, %{}}
    end

    {{percussion_note_events, percussion_controller_events}, non_percussion_result} = percussion_events

    # Group percussion events by pitch (instrument)
    notes_by_pitch = Enum.group_by(percussion_note_events, fn note -> note.note end)

    # Calculate timing delays for percussion instruments
    significant_events = read_significant_events(sequence, track_number)
    channel_delays = calculate_channel_delays_from_significant_events(significant_events, tpqn)

    # Create tracks for each percussion instrument
    percussion_result = Enum.into(notes_by_pitch, %{}, fn {pitch, pitch_notes} ->
      # Get instrument name from mapping, fallback to generic name
      instrument_name = Map.get(percussion_map, pitch, "Percussion #{pitch}")

      # For percussion, all controllers go to each pitch-based track since they affect the whole channel
      # Convert to sonorities (but these will be individual notes, not chords)
      sonorities = group_into_sonorities(pitch_notes, percussion_controller_events, chord_tolerance, tpqn)

      # For percussion, use the delay of channel 9 (if any)
      delay_quarter_notes = Map.get(channel_delays, 9, 0)

      # If this instrument starts later, prepend a rest sonority
      final_sonorities = if delay_quarter_notes > 0 do
        initial_rest = Rest.new(delay_quarter_notes, 9)
        [initial_rest | sonorities]
      else
        sonorities
      end

      # Use pitch as the key instead of channel, with a prefix to distinguish from channels
      {"percussion_#{pitch}", STrack.new(instrument_name, final_sonorities, tpqn, :percussion, 9)}
    end)

    # Merge non-percussion and percussion results
    Map.merge(non_percussion_result, percussion_result)
  end

  @doc false
  # Read the percussion instrument mapping from CSV file
  def read_percussion_mapping() do
    case File.exists?("midi_percussion_mapping.csv") do
      true ->
        File.stream!("midi_percussion_mapping.csv")
        |> CSV.decode(headers: true)
        |> Enum.reduce(%{}, fn
          {:ok, %{"Key#" => key_str, "Drum Sound" => drum_sound}}, acc ->
            case Integer.parse(key_str) do
              {key, ""} -> Map.put(acc, key, drum_sound)
              _ -> acc
            end
          _, acc -> acc
        end)
      false ->
        %{}  # Return empty map if file doesn't exist
    end
  end

  @doc false
  # Read the instrument mapping from CSV file for channel-based naming
  def read_instrument_mapping() do
    case File.exists?("midi_instrument_map.csv") do
      true ->
        File.stream!("midi_instrument_map.csv")
        |> CSV.decode(headers: true)
        |> Enum.reduce(%{}, fn
          {:ok, %{"PC" => pc_str, "Instrument" => instrument}}, acc ->
            case Integer.parse(pc_str) do
              {pc, ""} -> Map.put(acc, pc, instrument)
              _ -> acc
            end
          _, acc -> acc
        end)
      false ->
        %{}  # Return empty map if file doesn't exist
    end
  end


  @doc """
  Identifies all sonority events (notes and controllers) in a track and calculates their absolute times.

  This function pairs note-on and note-off events to create complete note objects
  with duration information, and also collects controller events as instantaneous events.
  It handles both standard note-off events and note-on events with zero velocity 
  (which are treated as note-offs according to the MIDI spec).

  The function also properly handles unmatched note-on events by assigning them
  an end time based on the last event in the track.

  ## Parameters
    * `events` - List of MIDI events from a track

  ## Returns
    * A map with keys:
      * `:notes` - List of note data maps with keys:
        * `:note` - The MIDI note number (0-127)
        * `:start_time` - Absolute start time in ticks from the beginning of the track
        * `:end_time` - Absolute end time in ticks
        * `:velocity` - The note's velocity (0-127)
        * `:channel` - The MIDI channel (0-15)
      * `:controllers` - List of controller data maps with keys:
        * `:controller_number` - The MIDI controller number (0-127)
        * `:value` - The controller value (0-127)
        * `:time` - Absolute time in ticks
        * `:channel` - The MIDI channel (0-15)

  ## Examples

      # Get all sonority events from a track
      events = Midifile.MapEvents.identify_sonority_events(track.events)
      note_events = events.notes
      controller_events = events.controllers

      # Print information about each note
      Enum.each(note_events, fn note ->
        duration = note.end_time - note.start_time
        IO.puts("Note # {note.note} on channel # {note.channel}, " <>
                "duration: # {duration} ticks, velocity: # {note.velocity}")
      end)
  """
  def identify_sonority_events(events) do
    # Calculate absolute times for all events
    events_with_times = add_absolute_times(events)

    # Track note_on events to pair with note_offs and collect controller events
    # Format: %{{channel, note} => {abs_time, velocity}}
    {notes, controllers, note_on_events} =
      Enum.reduce(events_with_times, {[], [], %{}}, fn {event, abs_time}, {notes_acc, controllers_acc, note_on_acc} ->
        case event do
          # Handle note_on events (velocity > 0)
          %{symbol: :on, bytes: [_status, note_num, velocity]} when velocity > 0 ->
            channel = Event.channel(event)
            key = {channel, note_num}
            # Store this note_on event with its start time and velocity
            new_note_on_acc = Map.put(note_on_acc, key, {abs_time, velocity})
            {notes_acc, controllers_acc, new_note_on_acc}

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
                {[note_data | notes_acc], controllers_acc, Map.delete(note_on_acc, key)}

              nil ->
                # No corresponding note_on found, ignore
                {notes_acc, controllers_acc, note_on_acc}
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
                {[note_data | notes_acc], controllers_acc, Map.delete(note_on_acc, key)}

              nil ->
                # No corresponding note_on found, ignore
                {notes_acc, controllers_acc, note_on_acc}
            end

          # Handle controller events
          %{symbol: :controller, bytes: [_status, controller_number, value]} ->
            channel = Event.channel(event)
            controller_data = %{
              controller_number: controller_number,
              value: value,
              time: abs_time,
              channel: channel
            }
            {notes_acc, [controller_data | controllers_acc], note_on_acc}

          # Ignore all other event types
          _ ->
            {notes_acc, controllers_acc, note_on_acc}
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

    all_notes = Enum.concat(notes, unmatched_notes)
    
    %{
      notes: all_notes,
      controllers: Enum.reverse(controllers)
    }
  end



  @doc """
  Groups identified notes and controllers into sonorities (Notes, Chords, Rests, Controllers).

  This function analyzes the timing relationships between notes to determine when
  notes should be considered as individual notes, as parts of chords, or when
  rests should be inserted between sound events. Controller events are inserted
  at their exact timing positions as instantaneous Controller sonorities.

  The chord_tolerance parameter allows for some flexibility in chord detection.
  Notes that start within the tolerance window will be grouped into a chord,
  even if they don't start at exactly the same time. This is particularly useful
  for human performances or imperfectly quantized MIDI where chord notes might
  not be precisely aligned.

  ## Parameters
    * `note_events` - List of note data maps from identify_sonority_events/1
    * `controller_events` - List of controller data maps from identify_sonority_events/1
    * `chord_tolerance` - Time window (in ticks) for grouping notes into chords
    * `tpqn` - Ticks per quarter note value used to calculate durations in beats

  ## Returns
    * A list of Sonority protocol implementations (Note, Chord, Rest, Controller) in chronological order

  ## Examples

      # First identify notes and controllers
      events = Midifile.MapEvents.identify_sonority_events(track.events)
      note_events = events.notes
      controller_events = events.controllers

      # Then group them into sonorities with a tolerance of 10 ticks
      sonorities = Midifile.MapEvents.group_into_sonorities(note_events, controller_events, 10, 960)

      # Count the different types of sonorities
      types = Enum.group_by(sonorities, &Sonority.type/1)
      IO.puts("Found # {length(types[:note] || [])} notes, " <>
              "# {length(types[:chord] || [])} chords, and " <>
              "# {length(types[:rest] || [])} rests")
  """
  def group_into_sonorities(note_events, controller_events, chord_tolerance, tpqn \\ Defaults.default_ppqn) do
    # First, create sonorities from note events using the original logic
    note_sonorities = create_note_sonorities(note_events, chord_tolerance, tpqn)
    
    # Convert controller events to Controller sonorities
    controller_sonorities = Enum.map(controller_events, fn controller ->
      Controller.new(controller.controller_number, controller.value, controller.channel)
    end)
    
    # Merge and sort all sonorities by their timing
    # Note: Controllers have duration 0, so they should appear at their exact time
    all_sonorities = merge_sonorities_by_timing(note_sonorities, controller_sonorities, controller_events, tpqn)
    
    all_sonorities
  end
  
  @doc false
  # Create note-based sonorities using the original logic
  defp create_note_sonorities(note_events, chord_tolerance, tpqn) do
    # Find all unique start and end times for notes only
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

          num_quarter_notes = (current_time - prev_time) / tpqn
          new_sonority = cond do
            # No notes active - create a Rest
            Enum.empty?(active_notes) ->
              Rest.new(num_quarter_notes, Enum.at(note_events, 0).channel)

            # One note active - create a Note
            length(active_notes) == 1 ->
              [note] = active_notes
              # Convert MIDI note to Note struct
              MidiNote.midi_to_note(note.note, num_quarter_notes, note.velocity, note.channel)

            # Multiple notes active - create a Chord
            true ->
              # Convert each MIDI note to a Note struct
              notes = Enum.map(active_notes, fn note ->
                MidiNote.midi_to_note(note.note, num_quarter_notes, note.velocity, note.channel)
              end)
              # Detect chord structure and create using enhanced API
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
  # Merge note sonorities and controller sonorities by timing
  defp merge_sonorities_by_timing(note_sonorities, controller_sonorities, controller_events, tpqn) do
    # Calculate cumulative time for note sonorities to determine insertion points
    {note_sonorities_with_times, _} = Enum.reduce(note_sonorities, {[], 0}, fn sonority, {acc, cumulative_time} ->
      duration_ticks = Sonority.duration(sonority) * tpqn
      end_time = cumulative_time + duration_ticks
      {[{sonority, cumulative_time, end_time} | acc], end_time}
    end)
    note_sonorities_with_times = Enum.reverse(note_sonorities_with_times)
    
    # Create a list of all events (note sonorities and controllers) with their timing
    controller_events_with_sonorities = Enum.zip(controller_events, controller_sonorities)
    |> Enum.map(fn {controller_event, controller_sonority} ->
      {:controller, controller_sonority, controller_event.time}
    end)
    
    note_events_with_sonorities = Enum.map(note_sonorities_with_times, fn {sonority, start_time, _end_time} ->
      {:note, sonority, start_time}
    end)
    
    # Merge and sort by time
    all_events = (controller_events_with_sonorities ++ note_events_with_sonorities)
    |> Enum.sort_by(fn {_type, _sonority, time} -> time end)
    
    # Extract just the sonorities in the correct order
    Enum.map(all_events, fn {_type, sonority, _time} -> sonority end)
  end

    @doc false
  # Creates a chord using the enhanced Chord API
  # Attempts to detect the chord structure (root, quality) from the given notes
  def create_enhanced_chord(notes, duration) do
    # Fallback to old API if detection fails
    fallback_fn = fn -> Chord.new(notes, duration) end
    velocity = floor(Enum.sum(Enum.map(notes, fn n -> n.velocity end)) / length(notes))
    channel = Sonority.channel(Enum.at(notes, 0))

    try do
      {root, quality, octave} = detect_chord_from_notes(notes)

      # Create the basic chord
      basic_chord = Chord.new(root, quality, octave, duration, 0, velocity, channel)

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

  @doc """
  returns a map off all program change events in a channel where
  the key is the channel and the value is {instrument_name, program_number}
  """
  def get_program_changes(seq, track_num) do
    mim = read_midi_instrument_map()
    track = Enum.at(seq.tracks, track_num)
    events = track.events
    Enum.filter(events, fn e -> e.symbol == :program end)
    |> Enum.map(fn %Midifile.Event{bytes: [high, low]} ->
      {Integer.to_string(high, 2)
      |> String.slice(4..7)
      |> String.to_integer(2), {Map.get(mim, low), low}}
    end)
    |> Enum.uniq()
    |> Enum.sort()
    |> Map.new
  end

  def get_channel(%Midifile.Event{symbol: :on, bytes: bytes}) do
    get_channel_from_bytes(bytes)
  end
  def get_channel(%Midifile.Event{symbol: :off, bytes: bytes}) do
    get_channel_from_bytes(bytes)
  end
  def get_channel(%Midifile.Event{symbol: :controller, bytes: bytes}) do
    get_channel_from_bytes(bytes)
  end
  def get_channel(_), do: -1

  def get_channel_from_bytes([b1, _, _]) do
    Integer.to_string(b1, 2)
    |> String.slice(4..7)
    |> String.to_integer(2)
  end

  def read_midi_instrument_map() do
    File.stream!("midi_instrument_map.csv")
    |> CSV.decode(headers: true)
    |> Enum.map(fn {_, %{"Instrument" => inst, "PC" => pc}} ->
        {String.to_integer(pc), inst}
       end)
    |> Map.new
  end

  def read_significant_events(seq, track_num) do
    track = Enum.at(seq.tracks, track_num)
    events = track.events
    Enum.filter(events, fn e -> e.symbol == :on or e.symbol == :off or e.symbol == :controller end)
    |> Enum.map(fn %Midifile.Event{symbol: symbol, delta_time: delta, bytes: [status, _high, _low]} ->
      {Integer.to_string(status, 2)
      |> String.slice(4..7)
      |> String.to_integer(2), delta, symbol}
    end)
  end

  def quarter_notes_until_first_flute(seq, track_num) do
    (read_significant_events(seq, track_num)
    |> Enum.take_while(fn {channel, _, symbol} -> not (channel == 3 and symbol == :on) end)
    |> Enum.reduce(0, fn {_, delta, _}, acc -> acc + delta end)) / seq.ticks_per_quarter_note
  end

  @doc false
  # Calculate delays for each channel based on significant events (on, off, controller)
  # Returns a map of channel -> delay_in_quarter_notes
  # Considers delta times for all Event.symbol in [:on, :off, :controller] for proper alignment
  defp calculate_channel_delays_from_significant_events(significant_events, tpqn) do
    # Group consecutive events by channel to find first appearance of each channel
    {delays, _, _} = Enum.reduce(significant_events, {%{}, 0, MapSet.new()}, fn {channel, delta, symbol}, {delays_acc, cumulative_time, seen_channels} ->
      new_cumulative_time = cumulative_time + delta

      # If this is the first time we see this channel, record its delay
      if symbol == :on and not MapSet.member?(seen_channels, channel) do
        delay_quarter_notes = cumulative_time / tpqn
        new_delays = Map.put(delays_acc, channel, delay_quarter_notes)
        new_seen = MapSet.put(seen_channels, channel)
        {new_delays, new_cumulative_time, new_seen}
      else
        {delays_acc, new_cumulative_time, seen_channels}
      end
    end)

    delays
  end
end
