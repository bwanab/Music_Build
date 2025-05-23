defmodule MusicBuild.LilyBuild do

  @bass_clef_cutoff 55
  @preamble "\\version \"2.24.4\" \n"
  @doc """
  Render a list of sonorities to a Lilypond string.
  """
  @spec show([Sonority.t()]) :: String.t()
  def show(sonorities) when is_list(sonorities) do
    Enum.map(sonorities, fn s -> Sonority.show(s) end) |> Enum.join(" ")
  end

  def render_track(sonorities, time_sig, tempo) do
    note_nums = Enum.flat_map(sonorities, fn s -> Sonority.to_notes(s) end)
                |> Enum.filter(fn n -> Sonority.type(n) == :note end)
                |> Enum.map(fn n -> MidiNote.note_to_midi(n).note_number  end)
    average_note = Enum.sum(note_nums) / length(note_nums)
    clef = if average_note < @bass_clef_cutoff do
      "\\clef bass"
    else
        ""
    end
    s = show(sonorities)
    "
    \\new Staff
    {
      \\time #{time_sig}
      \\tempo 4 = #{tempo}
      \\new Voice
      {
        #{clef} #{s}
      }
    }
    "
  end

  @doc """
  Render a list of sonorities to a Lilypond string.
  """
  @spec render([[Sonority.t()]], keyword()) :: String.t()
  def render(sonorities, opts \\ [])
  def render(sonorities, opts) when is_list(sonorities) do
    midi = Keyword.get(opts, :midi, false)
    title = Keyword.get(opts, :title, "No Name")
    tempo = Keyword.get(opts, :tempo, 90)
    time_sig = Keyword.get(opts, :time_sig, "4/4")
    midi_str = if midi, do: "\\midi { }", else: ""
    s = Enum.map(sonorities, fn track -> render_track(track, time_sig, tempo) end)
        |> Enum.join("\n")
    @preamble <> "
    \\book
    {
      \\header
        {
          title = \"#{title}\"
        }
      \\score
        {
        <<
          #{s}
        >>
        \\layout {
              \\context {
              \\Voice
              \\remove Note_heads_engraver
              \\consists Completion_heads_engraver
              \\remove Rest_engraver
              \\consists Completion_rest_engraver
           }

        }
        #{midi_str}
      }
    }"
  end

  @spec render(Sonority.t(), keyword()) :: String.t()
  def render(sonority, _opts) do
    @preamble <> "{
      #{Sonority.show(sonority)}
    }"
  end

  # write a lilypond file from the sonorities given. Note that this currently works for
  # one track.
  def write(sonorities, path, opts \\ []) do
    out_path = Keyword.get(opts, :out_path, ".")
    File.write(path, render(sonorities, opts))
    System.cmd("lilypond", ["-s", "--output=#{Path.expand(out_path)}", path])
  end

end
