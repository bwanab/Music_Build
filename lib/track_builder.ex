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
        Note.new({:C, 4}, duration: 1.0),
        Note.new({:D, 4}, duration: 1.0),
        Note.new({:E, 4}, duration: 1.0),
        Note.new({:F, 4}, duration: 1.0),
        Note.new({:G, 4}, duration: 1.0),
        Note.new({:A, 4}, duration: 1.0),
        Note.new({:B, 4}, duration: 1.0),
        Note.new({:C, 5}, duration: 1.0)
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
              |> post_process_events()
    }
  end

  @spec new(STrack.t()) :: Track.t()
  def new(%STrack{name: name, sonorities: sonorities, ticks_per_quarter_note: tpqn, program_number: program_number}) do
    new(name, sonorities, tpqn, program_number)
  end

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
              new_event = %Midifile.Event{symbol: :pitch_bend, delta_time: off_ev.delta_time, bytes: [224, <<32, 0>>]}
              {Map.delete(on_off_map, {note, channel, abs_time}), delete_list ++ [off_event], [{new_event,abs_time}|all_list]}
          end
        _ -> {on_off_map, delete_list, [e |all_list]}
      end
    end)
    Enum.reduce(delete_list, all_list, fn e, acc -> List.delete(acc, e) end ) |> Enum.map(fn {e, _} -> e end)
    |> Enum.reverse()
  end

end
