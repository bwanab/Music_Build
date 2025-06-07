defmodule MusicBuild.Examples.JazzProgressions do

  import MusicBuild.Util


  @spec do_chord_progression([atom()], atom(), String.t(), boolean(), atom()) :: :ok
  def do_chord_progression(progression, key \\ :C, name \\ "jazz_progression", add_last \\ true, out_type \\ :lily) do
    # Get chord symbols (Roman numerals) from ChordPrims

    # Use the enhanced Chord API to create chords directly from Roman numerals
    chords = Enum.map(progression, fn roman_numeral ->
      # Create chord using the new from_roman_numeral function
      Chord.from_roman_numeral(roman_numeral, key, 4, 4)
    end)

    last = Enum.at(chords, 0)
    all_chords = if add_last do
      chords ++ [Chord.copy(last, inversion: 2, octave: Chord.octave(last) - 1) ]
    else
      chords
    end

    chord_progression(all_chords, name, out_type)
  end

  def chord_progression(all_chords, name \\ "jazz progression", out_type \\ :lily) do



    raw_bass = Enum.map(Enum.with_index(all_chords),
      fn {c, _i} ->

      chord_length = length(Sonority.to_notes(c))
      pattern = case chord_length do
                  4 -> [1,2,3,4,3,2,1,2]
                  3 -> [1,3,2,3,2,3,2,1]
                end

        # this code is somewhat of an abomination. I'm simply trying to find the note
        # to connect adjacent bass arpeggios. In particular, the midi note conversions
        # are problematic.

        # Create a MidiNote module that makes this more structured.

        # next_chord = Enum.at(all_chords, Integer.mod(i + 1, length(all_chords)))
        # #root_note = Note.copy(Chord.root_note(next_chord), octave: Chord.octave(next_chord) - 2)
        # root_note = Enum.at(Arpeggio.new(next_chord, :up_down , 8) |> Sonority.to_notes, 0)
        # %{note_number: note_number} = Note.note_to_midi(root_note)
        # %Note{note: note, octave: octave} = Note.midi_to_note(note_number - (2 * 12 + 2))
        # octave = if octave < 2, do: 2, else: octave
        # last_note = Note.new(note, octave, 8, root_note.velocity)
        # IO.inspect(last_note)
        #
        # last_note = Rest.new(8)

        [Arpeggio.new(Chord.copy(c, octave: Chord.octave(c)-2), pattern, 0.5)]
#         ++ [last_note]
      end)

    bass = List.flatten(raw_bass)

    write_file([all_chords, bass], name, out_type)

  end

  def basic_jazz() do
    do_chord_progression([:ii7, :V7, :I7], :E, "basic_jazz")
  end

  def pachelbels_canon(out_type \\ :lily) do
    do_chord_progression([:I7, :V7, :vi7, :iii7, :IV7, :I7, :IV7, :V7],  :E, "pachelbel", false, out_type)
  end

end
