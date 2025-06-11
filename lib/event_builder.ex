defmodule MusicBuild.EventBuilder do
  @moduledoc """
  Provides functionality for building MIDI events from musical sonorities.

  This module handles the conversion of high-level musical sonorities (notes, chords, rests, controllers)
  into low-level MIDI events.
  """

  alias Midifile.Event
  alias Midifile.Defaults
  alias Note
  alias Chord
  alias Rest
  alias Arpeggio
  alias Controller
  alias PitchBend

  @doc """
  Creates MIDI events from a sonority.

  ## Parameters

    * `sonority_type` - The type of sonority (:note, :chord, :rest, :arpeggio, :controller, :pitch_bend)
    * `sonority` - The sonority to convert
    * `tpqn` - Ticks per quarter note (default: 960)

  ## Returns

    * A list of MIDI events representing the sonority
  """
  @spec new(atom(), Sonority.t(), integer()) :: [Event.t()]
  def new(sonority_type, sonority, tpqn \\ Defaults.default_ppqn)

  def new(:note, note, tpqn) do
    channel = Sonority.channel(note)
    midi_note = MidiNote.note_to_midi(note)
    [
      %Event{symbol: :on, delta_time: 0, bytes: [144 + channel, midi_note.note_number, midi_note.velocity]},
      %Event{symbol: :off, delta_time: round(tpqn * midi_note.duration), bytes: [128 + channel, midi_note.note_number, 0]}
    ]
  end

  def new(:rest, rest, tpqn) do
    channel = Sonority.channel(rest)
    midi_duration = Rest.to_midi(rest)
    [
      %Event{symbol: :off, delta_time: round(tpqn * midi_duration), bytes: [128 + channel, 0, 0]}
    ]
  end

  def new(:chord, chord, tpqn) do
    notes = Sonority.to_notes(chord)
    [first | others] = notes
    first_event = first_chord_note(first, chord.duration, tpqn)
    other_events = Enum.map(others, &(other_chord_notes(&1, tpqn)))
    raw = [first_event | other_events]
    # raw is now a list of :on :off pairs, we want to gather all the :on
    # events at the start and all the :off events at the end.
    Enum.map(raw, &(Enum.at(&1, 0))) ++ Enum.map(raw, &(Enum.at(&1, 1)))
  end

  def new(:arpeggio, arpeggio, tpqn) do
    notes = Sonority.to_notes(arpeggio)
    events = Enum.map(notes, &(new(:note, &1, tpqn)))
    List.flatten(events)
  end

  def new(:controller, controller, _tpqn) do
    channel = Sonority.channel(controller)
    [
      %Event{symbol: :controller, delta_time: 0, bytes: [176 + channel, controller.controller_number, controller.value]}
    ]
  end

  def new(:pitch_bend, pitch_bend, _tpqn) do
    channel = Sonority.channel(pitch_bend)
    # Convert 14-bit value to two 7-bit bytes (LSB, MSB)
    lsb = pitch_bend.value |> Bitwise.band(0x7F)
    msb = pitch_bend.value |> Bitwise.bsr(7) |> Bitwise.band(0x7F)
    [
      %Event{symbol: :pitch_bend, delta_time: 0, bytes: [224 + channel, lsb, msb]}
    ]
  end

  defp first_chord_note(%Note{note: n, octave: o, velocity: v, channel: channel}, duration, tpqn) do
    new(:note, Note.new(n, o, duration, v, channel), tpqn)
  end

  defp other_chord_notes(%Note{note: n, octave: o, velocity: velocity, channel: channel}, tpqn) do
    new(:note, Note.new(n, o, 0, velocity, channel), tpqn)
  end
end
