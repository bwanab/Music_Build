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
    }
  end

  @spec new(STrack.t()) :: Track.t()
  def new(%STrack{name: name, sonorities: sonorities, ticks_per_quarter_note: tpqn, program_number: program_number}) do
    new(name, sonorities, tpqn, program_number)
  end
end
