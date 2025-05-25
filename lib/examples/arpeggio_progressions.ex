defmodule MusicBuild.Examples.ArpeggioProgressions do

  alias MusicBuild.Examples.MidiFromScratch


  def build_chords(progression, key, octave, duration) do
    Enum.map(progression, fn roman_numeral ->
      # Create chord using the new from_roman_numeral function
      c = Chord.from_roman_numeral(roman_numeral, key, octave, duration)
      notes = Sonority.to_notes(c)
      all_notes = notes ++ Note.bump_octave(notes, :up)
      Chord.new(all_notes, duration)
    end)
  end

  # @spec do_arpeggio_progression([atom()], atom(), boolean(), String.t(), atom()) :: :ok
  def do_arpeggio_progression(progression, key \\ :C, name \\ "arpeggio_progression", out_type \\ :lily) do
    # Get chord symbols (Roman numerals) from ChordPrims

    chords = build_chords(progression, key, 4, 1)
    # Use the enhanced Chord API to create chords directly from Roman numerals

    patterns = [
      [4,1,2,3],
      [1,2,4,3],
      [2,3,4,2],
      [1,4,3,1],
      [1,2,3,4],
      [1,4,3,1],
      [1,2,3,2],
      [2,3,4,1]
    ]

    all_arpeggios = Enum.map(Enum.zip(chords, patterns), fn {c, p} -> Arpeggio.new(c, p, 0.5) end)

    bass = Enum.map(chords,
      fn a ->
        Enum.at(Sonority.to_notes(a), 0)
        |> Note.bump_octave(:down)
        |> Note.bump_octave(:down)
        |> Note.copy(duration: 2)
      end)

    MidiFromScratch.write_file([all_arpeggios, bass], name, out_type)
  end

  def pachelbels_canon() do
    do_arpeggio_progression([:I, :V, :vi, :iii, :IV, :I, :IV, :V],  :C, "pachelbel")
  end

end
