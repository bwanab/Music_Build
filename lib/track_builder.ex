defmodule MusicBuild.TrackBuilder do
  @moduledoc """
  Provides functionality for building MIDI tracks from musical sonorities.

  This module handles the conversion of high-level musical sonorities (notes, chords, rests, controllers)
  into low-level MIDI events and assembles them into properly formatted tracks.
  """

  alias Midifile.Defaults
  alias Midifile.Event
  alias Midifile.Track
  alias MusicBuild.EventBuilder

  @doc """
  Creates a new track from a list of sonorities.

  This function converts high-level musical sonorities (notes, chords, rests, controllers)
  into low-level MIDI events and assembles them into a properly formatted track.
  The track will include a name event at the beginning and an end-of-track event.

  ## Parameters

    * `name` - String name for the track
    * `sonorities` - List of sonority protocol implementations (Note, Chord, Rest, Controller)
    * `tpqn` - Ticks per quarter note, defines the time resolution (default: 960)

  ## Returns

    * A new `Midifile.Track` struct containing the converted events

  ## Examples

      # Create a track with a C major scale
      notes = [
        Note.new(:C, octave: 4, duration: 1.0),
        Note.new(:D, octave: 4, duration: 1.0),
        Note.new(:E, octave: 4, duration: 1.0),
        Note.new(:F, octave: 4, duration: 1.0),
        Note.new(:G, octave: 4, duration: 1.0),
        Note.new(:A, octave: 4, duration: 1.0),
        Note.new(:B, octave: 4, duration: 1.0),
        Note.new(:C, octave: 5, duration: 1.0)
      ]

      track = MusicBuild.TrackBuilder.new("C Major Scale", notes, 960)
  """
  @spec new(String.t(), [Sonority], integer(), integer()) :: Track.t()
  def new(name, sonorities, tpqn \\ Defaults.default_ppqn, program_number \\ 0) do
    channel_number = Sonority.channel(Enum.at(sonorities, 0))
    prog_event = if channel_number == 9 do
       [%Event{symbol: :controller, delta_time: 0, bytes: [185, 7, 127]}]
    else
       [%Event{symbol: :program, delta_time: 0, bytes: [192 + channel_number, program_number]}]
    end
    e1 = [%Event{symbol: :seq_name, delta_time: 0, bytes: name}]
    events = Enum.map(sonorities, &(EventBuilder.new(Sonority.type(&1), &1, tpqn)))
    e_last = [%Event{symbol: :track_end, delta_time: 0, bytes: []}]

    %Track{
      name: name,
      events: List.flatten(e1 ++ prog_event ++ events ++ e_last)
             # |> post_process_events()
    }
  end

  @spec new(STrack.t()) :: Track.t()
  def new(%STrack{name: name, sonorities: sonorities, ticks_per_quarter_note: tpqn, program_number: program_number}) do
    new(name, sonorities, tpqn, program_number)
  end

  @doc false
  # Introduction of intent:
  #
  # This function deserves an explanation. It is here as a result of the way that Sonorities operate. Specifically,
  # given the circumstance in which a chord sounds for a given period and a subset of those notes continues to sound,
  # or vice-versa the way Sonorities are built is to take those as two Sonority events. While this provides clarity
  # from the point of view of analyzing the musical structure the side effect is that when translating these sonorities
  # to midi events it creates a discontinuity in sound. Imagine a piano playing a C chord for two beats in which the
  # pianist removes the E and G notes while keeping the C note sounding. As Sonorities this is stored as a C chord followed
  # by a C note. If it is written to midi in that fashion, what one would hear is the C chord being played for two beats,
  # then a C note being struck. Given that piano is a very percussive instrument it creates a different musical feel than
  # was intended in the original performance.
  #
  # How it works:
  #
  # The effect in the generated midi events is that one would have C-on, E-on, G-on events, with a C-off event that has
  # a time delay equivalent to two beats and E-off, G-off events, then a C-on event with a 0 delay. What this function
  # does, then is search for off-on combinations on a given channel and note that occur with 0 delay. It removes both
  # of those events and adds a (hopefully) musical no-op with whatever delay the off event that was removed had thus
  # allowing the note to continue for its intended duration.
  def post_process_events(events) do
    events_with_times = MapEvents.add_absolute_times(events)
    {_, delete_list, all_list} = Enum.reduce(events_with_times, {%{}, [], []}, fn e, {on_off_map, delete_list, all_list} ->
      {event, abs_time} = e
      case {event.symbol, event.delta_time} do
        {:off, _} ->
          %Midifile.Event{bytes: [_, note, _]} = event
          channel = Midifile.Event.channel(event)
          {Map.put(on_off_map, {note, channel, abs_time}, e), delete_list, [e|all_list]}
        {:on, 0} ->
          %Midifile.Event{bytes: [_, note, _]} = event
          channel = Midifile.Event.channel(event)
          case Map.get(on_off_map, {note, channel, abs_time}, :not_found) do
            :not_found -> {on_off_map, delete_list, [e|all_list]}
            off_event ->
              {off_ev, _} = off_event
              # create a noop  that maintains timing.
              new_event = %Midifile.Event{symbol: :sysex, delta_time: off_ev.delta_time, bytes: [<<240, 0, 0, 247>>]}
              {Map.delete(on_off_map, {note, channel, abs_time}), delete_list ++ [off_event], [{new_event,abs_time}|all_list]}
          end
        _ -> {on_off_map, delete_list, [e |all_list]}
      end
    end)
    Enum.reduce(delete_list, all_list, fn e, acc -> List.delete(acc, e) end )
    |> Enum.map(fn {e, _} -> e end)
    |> Enum.reverse()
  end

end
