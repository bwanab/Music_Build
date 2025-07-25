defmodule MusicBuild.Util do

  alias Midifile.Sequence
  alias MusicBuild.TrackBuilder

#  @spec write_midi_file(%{any() => STrack.t()}) :: :ok
  def write_midi_file(n, o, opts \\ [])
  def write_midi_file(strack_map, outpath, opts) when is_map(strack_map) do
    name = Path.basename(outpath, Path.extname(outpath))
    bpm = Map.get(strack_map, Enum.at(Map.keys(strack_map), 0)).bpm
    tpqn = Keyword.get(opts, :ticks_per_quarter_note, 960)

    Midifile.write(build_sequence(strack_map, name, bpm, tpqn), outpath)
  end

 # @spec write_midi_file([Sonority.t()], binary, keyword()) :: :ok
  def write_midi_file(notes, outpath, opts) do
    tpqn = Keyword.get(opts, :ticks_per_quarter_note, 960)
    bpm = Keyword.get(opts, :bpm, 110)
    inst_names = Keyword.get(opts, :inst_names, Enum.map(notes, fn _ -> "UnNamed" end))
    program_numbers = Keyword.get(opts, :program_numbers, Enum.map(notes, fn _ -> 0 end))
    name = Path.basename(outpath, Path.extname(outpath))

    tracks = Enum.map(Enum.zip([notes, inst_names, program_numbers]), fn {track, inst_name, program_number} ->
      TrackBuilder.new(inst_name, track, tpqn, program_number)
    end)
    sfs = Sequence.new(name, bpm, tracks, tpqn)
    Midifile.write(sfs, outpath)
  end

  def build_sequence(strack_map, name, bpm, tpqn) do
    tracks = Enum.map(Map.values(strack_map), fn s -> TrackBuilder.new(s) end)
    Sequence.new(name, bpm, tracks, tpqn)

  end

  #@spec write_file([Sonority.t()], binary(), atom(), keyword()) :: :ok
  def write_file(strack_map, name, out_type \\ :midi, opts \\ [])
  def write_file(strack_map, name, out_type, opts) when is_map(strack_map) do
    case out_type do
      :play -> MidiPlayer.play(strack_map)
      :midi -> write_midi_file(strack_map, name, opts)
      :lily ->
        strack_list = Map.values(strack_map)
        tempo = Enum.at(strack_list, 0).bpm
        write_file(Enum.map(strack_list, fn s -> s.sonorities end), name, :lily, Keyword.put(opts, :bpm, tempo))
    end
  end

  def write_file(notes, name, out_type, opts) do
    case out_type do
      :midi ->
        out_path = if Path.extname(name) == "", do: Keyword.get(opts, :out_path, "./midi/#{name}.mid"), else: name
        write_midi_file(notes, out_path, opts)
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
      "Unnamed"
    end
  end

  @spec get_track_names(Midifile.Sequence.t()) :: [{Integer, binary()}]
  def get_track_names(seq) do
    Enum.with_index(seq.tracks)
    |> Enum.map(fn {t, i} -> {i, MusicBuild.Util.get_track_name(t)} end)
  end

  @doc """
  removes all notes that have a duration of less than a 16th note

  Note that this currently assumes a file with one track!
  """
  def filter_bad_notes(pathname) do
    seq = Midifile.Reader.read(pathname)
    filtered_seq = Filter.process_notes(seq, 0, fn note -> note.duration < 0.1 end, :remove)
    outpath = Path.join(Path.dirname(pathname), "filtered_" <> Path.basename(pathname))
    IO.inspect(outpath)
    Midifile.Writer.write(filtered_seq, outpath)
  end

  @doc """
  bumps a midi files notes up one octave.

  NOTE: this only works for tracks that contain no Arpeggios or Chords at present!
  TODO: there needs to be a Sonority function to change the pitch of a sonority
        by a given numer of semitones.
  """
  def bump_octave(seq, track_num) do
    strack_map = MapEvents.one_track_to_sonorities(seq, track_num)
    Enum.map(strack_map[0].sonorities, fn s ->
      case Sonority.type(s) do
        :note -> Note.bump_octave(s, :up)
      _ -> s
      end
    end)
  end

  def merge_maps_with_lists(maps) do
    Enum.reduce(maps, %{}, fn map, acc ->
      Map.merge(acc, map, fn _key, list1, list2 ->
        list1 ++ list2
      end)
    end)
  end

  def chunk_line(line, num_per_measure, pattern) do
    measures = Enum.chunk_every(line, num_per_measure)
    Enum.reduce(Enum.zip(pattern, measures), %{}, fn {p, notes}, acc ->
      Map.put(acc, p, Map.get(acc, p, []) ++ [notes])
    end)
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

  def unzip_n(tuples) do
    tuples
    |> Enum.map(&Tuple.to_list/1)
    |> Enum.zip()
    |> Enum.map(&Tuple.to_list/1)
  end


  def play_midi(path) do
    out_path = Path.expand(path)
    soundfont_path = Path.expand("~/Documents/music/soundfonts/PC51f.sf2")
    System.cmd("fluidsynth", ["-i", "#{soundfont_path}", "#{out_path}"])
  end

  def event_description(%Midifile.Event{symbol: symbol, delta_time: _delta, bytes: bytes} = event) do
    ControllerMap.start_link()
    InstrumentMap.start_link()
    case symbol do
      :seq_name ->
        "Name: #{bytes}"
      :program ->
        channel = Midifile.Event.channel(event)
        [_, inst_num] = bytes
        "Program channel: #{channel}, Instrument: #{InstrumentMap.get_instrument(inst_num)}"
      :pitch_bend ->
        channel = Midifile.Event.channel(event)
        [_, bin] = bytes
        [msb, lsb] = :binary.bin_to_list(bin)
        "Pitch Bend channel #{channel}, value: #{msb * 256 + lsb}"
      :on ->
        channel = Midifile.Event.channel(event)
        [_, note, velocity] = bytes
        "Note on channel: #{channel}, note: #{note}, velocity: #{velocity}"
      :off ->
        channel = Midifile.Event.channel(event)
        [_, note, _] = bytes
        "Note off channel: #{channel}, note: #{note}"
      :controller ->
        channel = Midifile.Event.channel(event)
        [_, controller_num, value] = bytes
        "Controller channel: #{channel}, : #{ControllerMap.get_controller(controller_num)}, value: #{value}"
      :track_end ->
        "Track end"
      :text ->
        "Text: #{bytes}"
      :lyric ->
        ""
      :marker ->
        ""
      :copyright ->
        "Copyright: #{:binary.bin_to_list(bytes) |> List.to_string }"
      :unknown_meta ->
        ""
      :sysex ->
        [bin] = bytes
        [man_id | l] = :binary.bin_to_list(bin)
        "Sysex: manufactor id: #{man_id}, message: #{Enum.join(l, ", ")}"
      _ ->
        "Other event: #{Atom.to_string(symbol)}"
    end
  end

  def event_description(l) when is_list(l) do
    Enum.map(l, fn e -> event_description(e) end)
  end
end
