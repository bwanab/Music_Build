defmodule MusicBuild.Examples.ArpeggioProgressions do

  import MusicBuild.Util


  def build_chords(progression, key, octave, duration, channel) do
    Enum.map(progression, fn roman_numeral ->
      # Create chord using the new from_roman_numeral function
      c = Chord.from_roman_numeral(roman_numeral, key, octave, duration, 0, channel)
      notes = Sonority.to_notes(c)
      all_notes = notes ++ Note.bump_octave(notes, :up)
      Chord.new(all_notes, duration)
    end)
  end

  # @spec do_arpeggio_progression([atom()], atom(), boolean(), String.t(), atom()) :: :ok
  def do_arpeggio_progression(progression, key \\ :C, name \\ "arpeggio_progression", repeats, out_type \\ :lily) do

    chord_channel = 0
    arpeggio_channel = 1
    bass_channel = 2
    chords = build_chords(progression, key, 4, 2, chord_channel)

    all_chords = List.duplicate(chords, repeats)
                |> List.flatten()

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

    all_arpeggios = Enum.map(Enum.zip(chords, patterns), fn {c, p} -> Arpeggio.new(c, p, 0.5, arpeggio_channel) end)
                    |> List.duplicate(repeats)
                    |> List.flatten()


    bass_patterns = [
      [1,4],
      [1,2],
      [1,3],
      [1,3],
      [1,2],
      [1,4],
      [1,2],
      [1,3]
    ]


    bass_chords = build_chords(progression, key, 2, 1, bass_channel)

    bass_arpeggios = Enum.map(Enum.zip(bass_chords, bass_patterns), fn {c, p} ->
      Arpeggio.new(c, p, 1, bass_channel)
    end)
                    |> List.duplicate(repeats)
                    |> List.flatten()



    stract_map = %{
      0 => STrack.new("piano chords", all_chords, 960, :instrument, 0, 100),
      1 => STrack.new("arpeggios", all_arpeggios, 960, :instrument, 73, 100),
      2 => STrack.new("bass", bass_arpeggios, 960, :instrument, 33, 100)
    }
    write_file(stract_map, name, out_type)
  end

  def pachelbels_canon(out_type \\ :lily) do
    #do_arpeggio_progression([:I, :V, :vi, :iii, :IV, :I, :IV, :V],  :C, "pachelbel", 10, out_type)
    do_arpeggio_progression([:I, :V, :vi, :iii, :IV, :I, :IV, :V],  :C, "midi/pachelbel.mid", 10, out_type)
  end

end
