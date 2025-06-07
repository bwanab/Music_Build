defmodule MusicBuild.EventBuilder do
  @moduledoc """
  Provides functionality for building MIDI events from musical sonorities.

  This module handles the conversion of high-level musical sonorities (notes, chords, rests)
  into low-level MIDI events.
  """

  alias Midifile.Event
  alias Midifile.Defaults
  alias Note
  alias Chord
  alias Rest
  alias Arpeggio

  @doc """
  Creates MIDI events from a sonority.

  ## Parameters

    * `sonority_type` - The type of sonority (:note, :chord, :rest, :arpeggio)
    * `sonority` - The sonority to convert
    * `tpqn` - Ticks per quarter note (default: 960)

  ## Returns

    * A list of MIDI events representing the sonority
  """
  @spec new(atom(), Sonority.t(), integer(), integer()) :: [Event.t()]
  def new(sonority_type, sonority, tpqn \\ Defaults.default_ppqn, channel \\ 0)

  def new(:note, note, tpqn, channel) do
    midi_note = MidiNote.note_to_midi(note)
    [
      %Event{symbol: :on, delta_time: 0, bytes: [144 + channel, midi_note.note_number, midi_note.velocity]},
      %Event{symbol: :off, delta_time: round(tpqn * midi_note.duration), bytes: [128 + channel, midi_note.note_number, 0]}
    ]
  end

  def new(:rest, rest, tpqn, channel) do
    midi_duration = Rest.to_midi(rest)
    [
      %Event{symbol: :off, delta_time: round(tpqn * midi_duration), bytes: [128 + channel, 0, 0]}
    ]
  end

  def new(:chord, chord, tpqn, channel) do
    notes = Sonority.to_notes(chord)
    [first | others] = notes
    first_event = first_chord_note(first, chord.duration, tpqn, channel)
    other_events = Enum.map(others, &(other_chord_notes(&1, tpqn, channel)))
    raw = [first_event | other_events]
    # raw is now a list of :on :off pairs, we want to gather all the :on
    # events at the start and all the :off events at the end.
    Enum.map(raw, &(Enum.at(&1, 0))) ++ Enum.map(raw, &(Enum.at(&1, 1)))
  end

  def new(:arpeggio, arpeggio, tpqn, channel) do
    notes = Sonority.to_notes(arpeggio)
    events = Enum.map(notes, &(new(:note, &1, tpqn, channel)))
    List.flatten(events)
  end

  defp first_chord_note(%Note{note: n, octave: o, velocity: v}, duration, tpqn, channel) do
    new(:note, Note.new(n, o, duration, v), tpqn, channel)
  end

  defp other_chord_notes(%Note{note: n, octave: o}, tpqn, channel) do
    new(:note, Note.new(n, o, 0), tpqn, channel)
  end
end
