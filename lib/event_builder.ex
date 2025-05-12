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
  @spec new(atom(), Sonority.t(), integer()) :: [Event.t()]
  def new(sonority_type, sonority, tpqn \\ Defaults.default_ppqn)

  def new(:note, note, tpqn) do
    midi_note = Note.note_to_midi(note)
    [
      %Event{symbol: :on, delta_time: 0, bytes: [144, midi_note.note_number, midi_note.velocity]},
      %Event{symbol: :off, delta_time: round(tpqn * midi_note.duration), bytes: [128, midi_note.note_number, 0]}
    ]
  end

  def new(:rest, rest, tpqn) do
    [
      %Event{symbol: :off, delta_time: round(tpqn * rest.duration), bytes: [128, 0, 0]}
    ]
  end

  def new(:chord, chord, tpqn) do
    notes = Chord.to_notes(chord)
    [first | others] = notes
    first_event = first_chord_note(first, chord.duration, tpqn)
    other_events = Enum.map(others, &(other_chord_notes(&1)))
    raw = [first_event | other_events]
    # raw is now a list of :on :off pairs, we want to gather all the :on
    # events at the start and all the :off events at the end.
    Enum.map(raw, &(Enum.at(&1, 0))) ++ Enum.map(raw, &(Enum.at(&1, 1)))
  end

  def new(:arpeggio, arpeggio, tpqn) do
    notes = Arpeggio.to_notes(arpeggio)
    events = Enum.map(notes, &(new(:note, &1, tpqn)))
    List.flatten(events)
  end

  defp first_chord_note(%Note{note: n, velocity: v}, duration, tpqn) do
    new(:note, Note.new(n, duration: duration, velocity: v), tpqn)
  end

  defp other_chord_notes(%Note{note: n, velocity: v}) do
    new(:note, Note.new(n, duration: 0, velocity: v))
  end
end
