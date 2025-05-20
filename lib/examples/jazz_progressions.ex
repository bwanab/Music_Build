defmodule MusicBuild.Examples.JazzProgressions do

  alias MusicBuild.Examples.MidiFromScratch


  @spec do_chord_progression([atom()], atom(), atom()) :: :ok
  def do_chord_progression(progression, key \\ :C, out_type \\ :lily) do
    # Get chord symbols (Roman numerals) from ChordPrims

    # Use the enhanced Chord API to create chords directly from Roman numerals
    chords = Enum.map(progression, fn roman_numeral ->
      # Create chord using the new from_roman_numeral function
      Chord.from_roman_numeral(roman_numeral, key, 4, 1)
    end)

    last = Enum.at(chords, 0)
    all_chords = chords ++ [Chord.copy(last, inversion: 2, octave: Chord.octave(last) - 1) ]

    raw_bass = Enum.map(all_chords,
      fn c ->
        [Arpeggio.new(Chord.copy(c, octave: Chord.octave(c)-2), :up_down, 8)]
         ++ [Rest.new(8)]
      end)

    bass = List.flatten(raw_bass)

    MidiFromScratch.write_file([all_chords, bass], "jazz_progression", out_type)
  end

end
