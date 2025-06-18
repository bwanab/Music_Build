defmodule MusicBuild.Examples.ArpeggioProgressions do

  import MusicBuild.Util


  def build_chords(progression, key, octave, duration, channel) do
    Enum.map(progression, fn roman_numeral ->
      # Create chord using the new from_roman_numeral function
      c = Chord.from_roman_numeral(roman_numeral, key, octave: octave, duration: duration, inversion: 0, channel: channel)
      notes = Sonority.to_notes(c)
      all_notes = notes ++ Note.bump_octave(notes, :up)
      Chord.new(all_notes, duration)
    end)
  end

  # @spec do_arpeggio_progression([atom()], atom(), boolean(), String.t(), atom()) :: :ok
  def do_arpeggio_progression(progression, key \\ :C, repeats, assignments \\ %{chord: {0, 0}, arpeggio: {0,0}, bass: {0,0}}) do

    {chord_channel, chord_instrument} = assignments[:chord]
    {arpeggio_channel, arpeggio_instrument} = assignments[:arpeggio]
    {bass_channel, bass_instrument} = assignments[:bass]
    chords = build_chords(progression, key, 4, 2, chord_channel)

    #
    # here's an example of putting a volume control into the mix of sonorities.
    #
    all_chords = [Controller.new(7, 70, 0)] ++ List.duplicate(chords, repeats)
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

  %{
     0 => STrack.new(all_chords, name: "piano chords", tpqn: 960, type: :instrument, program_number: chord_instrument, bpm: 100),
     1 => STrack.new(all_arpeggios, name: "arpeggios", tpqn: 960, type: :instrument, program_number: arpeggio_instrument, bpm: 100),
     2 => STrack.new(bass_arpeggios, name: "bass", tpqn: 960, type: :instrument, program_number: bass_instrument, bpm: 100)
   }
  end

  def pachelbels_canon(out_type \\ :lily) do
    #do_arpeggio_progression([:I, :V, :vi, :iii, :IV, :I, :IV, :V],  :C, "pachelbel", 10, out_type)
    assignments = %{chord: {0, 19}, arpeggio: {1,73}, bass: {2,32}}
    do_arpeggio_progression([:I, :V, :vi, :iii, :IV, :I, :IV, :V],  :C, 10, assignments)
    |> write_file("midi/pachelbel.mid", out_type)

  end

  def test_one(track \\ 0) do
    assignments = %{chord: {0, 19}, arpeggio: {1,73}, bass: {2,32}}
    stm = do_arpeggio_progression([:I, :V, :vi, :iii, :IV, :I, :IV, :V],  :C, 10, assignments)
    stm0 = %{0 => stm[track]}
    write_file(stm0, "", :play)
  end


end
