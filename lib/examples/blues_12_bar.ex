defmodule MusicBuild.Examples.Blues12Bar do
  alias Chord
  alias MusicBuild.Util

  @pattern [:I, :IV, :I, :I, :IV, :IV, :I, :I, :V, :IV, :I, :V]

  @spec play_blues(atom()) :: any()
  def play_blues(key) do
    chords = Enum.map(@pattern, fn roman_numeral ->
      # Create chord using the new from_roman_numeral function
      Chord.from_roman_numeral(roman_numeral, key, 4, 4)
    end)
    Util.write_midi_file([chords], "midi/blues_12_bar_chords.mid")
  end
end
