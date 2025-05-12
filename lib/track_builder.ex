defmodule MusicBuild.TrackBuilder do
  @moduledoc """
  Provides functionality for building MIDI tracks from musical sonorities.

  This module handles the conversion of high-level musical sonorities (notes, chords, rests)
  into low-level MIDI events and assembles them into properly formatted tracks.
  """

  alias Midifile.Defaults
  alias Midifile.Event
  alias Midifile.Track
  alias MusicBuild.EventBuilder

  @doc """
  Creates a new track from a list of sonorities.

  This function converts high-level musical sonorities (notes, chords, rests)
  into low-level MIDI events and assembles them into a properly formatted track.
  The track will include a name event at the beginning and an end-of-track event.

  ## Parameters

    * `name` - String name for the track
    * `sonorities` - List of sonority protocol implementations (Note, Chord, Rest)
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
  @spec new(String.t(), [Sonority], integer()) :: Track.t()
  def new(name, sonorities, tpqn \\ Defaults.default_ppqn) do
    e1 = [%Event{symbol: :seq_name, delta_time: 0, bytes: name}]
    events = Enum.map(sonorities, &(EventBuilder.new(Sonority.type(&1), &1, tpqn)))
    e_last = [%Event{symbol: :track_end, delta_time: 0, bytes: []}]

    %Track{
      name: name,
      events: List.flatten(e1 ++ events ++ e_last)
    }
  end
end
