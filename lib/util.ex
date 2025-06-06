defmodule MusicBuild.Util do

  alias Midifile.Sequence
  alias MusicBuild.TrackBuilder

#  @spec write_midi_file(%{any() => STrack.t()}) :: :ok
  def write_midi_file(n, o, opts \\ [])
  def write_midi_file(strack_map, outpath, opts) when is_map(strack_map) do

    {tracks, names} = Map.values(strack_map)
      |> Enum.map(fn %STrack{name: name, sonorities: sonorities} ->
        use_name = if is_nil(name), do: "Unnamed", else: name
        {sonorities, use_name}
      end)
      |> Enum.unzip()
    write_midi_file(tracks, outpath, Keyword.put(opts, :inst_names, names))
  end

 # @spec write_midi_file([Sonority.t()], binary, keyword()) :: :ok
  def write_midi_file(notes, outpath, opts) do
    tpqn = Keyword.get(opts, :ticks_per_quarter_note, 960)
    bpm = Keyword.get(opts, :bpm, 110)
    inst_names = Keyword.get(opts, :inst_names, Enum.map(notes, fn _ -> "UnNamed" end))
    name = Path.basename(outpath, Path.extname(outpath))

    tracks = Enum.map(Enum.zip(notes, inst_names), fn {track, inst_name} -> TrackBuilder.new(inst_name, track, 960) end)
    sfs = Sequence.new(name, bpm, tracks, tpqn)
    Midifile.write(sfs, outpath)
  end

  @spec write_file([Sonority.t()], binary(), atom(), keyword()) :: :ok
  def write_file(notes, name, out_type \\ :midi, opts \\ []) do
    case out_type do
      :midi -> write_midi_file(notes, name, opts)
      :lily ->
        midi? = Keyword.get(opts, :midi, true)
        out_path = Keyword.get(opts, :out_path, "./midi")
        tempo = Keyword.get(opts, :bpm, 110)
        time_sig = Keyword.get(opts, :time_sig, "4/4")
        MusicBuild.LilyBuild.write(notes, "#{out_path}/#{name}.ly",
                midi: midi?,
                title: name,
                out_path: out_path,
                tempo: tempo,
                time_sig: time_sig
        )
    end
  end

  @spec get_track_name(Midifile.Sequence.t(), Integer) :: binary()
  def get_track_name(seq, track_num) do
    get_track_name(Enum.at(seq.tracks, track_num))
  end

  @spec get_track_name(Midifile.Track.t()) :: binary()
  def get_track_name(track) do
    events = track.events
    name_events = Enum.filter(events, fn %Midifile.Event{symbol: symbol} -> symbol == :seq_name end)
    if length(name_events) > 0 do
      Enum.at(name_events, 0).bytes
    else
      ""
    end
  end

  @spec get_track_names(Midifile.Sequence.t()) :: [{Integer, binary()}]
  def get_track_names(seq) do
    Enum.with_index(seq.tracks)
    |> Enum.map(fn {t, i} -> {i, MusicBuild.Util.get_track_name(t)} end)
  end

  @doc """
  Recursively scans a directory for MIDI files (.mid and .midi) and prints information about each file.
  """
  def scan_midi_files(directory_path, opts \\ []) do
    min_tracks = Keyword.get(opts, :min_tracks, 2)
    name_only = Keyword.get(opts, :name_only, true)
    Path.wildcard(Path.join(directory_path, "**/*.{mid,midi}"))
    |> Enum.each(fn file_path ->
      try do
        seq = Midifile.read(file_path)
        track_count = length(seq.tracks)
        if track_count >= min_tracks do
          track_names =
            seq.tracks
            |> Enum.with_index()
            |> Enum.map(fn {track, index} ->
              name = track.name || "Track #{index + 1}"
              "  Track #{index + 1}: #{name}, Event # #{length(track.events)}"
            end)

          if name_only do
            IO.puts("File: #{file_path}")
          else
            IO.puts("File: #{file_path}")
            IO.puts("  Tracks: #{track_count}")
            if track_count > 0 do
              Enum.each(track_names, &IO.puts/1)
            end
            IO.puts("")
          end
        end
      rescue
        error ->
          IO.puts("Error reading #{file_path}: #{inspect(error)}")
          IO.puts("")
      end
    end)
  end

end
