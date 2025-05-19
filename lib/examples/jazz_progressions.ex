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

    _last = Enum.at(chords, -1)
    all_chords = chords # ++ [Chord.copy(last, inversion: 2, octave: Chord.octave(last) - 1) ]

    MidiFromScratch.write_file([all_chords], "jazz_progression", out_type)
  end

end
