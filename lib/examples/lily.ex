

defmodule MusicBuild.Examples.Lily do

  @preamble "\\version \"2.24.4\" \n"
  @doc """
  Render a list of sonorities to a Lilypond string.
  """
  @spec show([Sonority.t()]) :: String.t()
  def show(sonorities) when is_list(sonorities) do
    Enum.map(sonorities, fn s -> Sonority.show(s) end) |> Enum.join(" ")
  end
  @doc """
  Render a list of sonorities to a Lilypond string.
  """
  @spec render([Sonority.t()], keyword()) :: String.t()
  def render(sonorities, opts \\ [])
  def render(sonorities, opts) when is_list(sonorities) do
    midi = Keyword.get(opts, :midi, false)
    title = Keyword.get(opts, :title, "No Name")
    midi_str = if midi, do: "\\midi { }", else: ""
    s = Lily.show(sonorities)
    @preamble <> "
    \\book
    {
      \\header
        {
          title = \"#{title}\"
        }
      \\score
        {
          {
          #{s}
          }
        \\layout { }
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

  def write(sonorities, path, opts \\ []) do
    out_path = Keyword.get(opts, :out_path, ".")
    File.write(path, render(sonorities, opts))
    System.cmd("lilypond", ["-s", "--output=#{Path.expand(out_path)}", path])
  end

end
