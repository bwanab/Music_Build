Mix.install([
  {:midifile, github: "bwanab/elixir-midifile"}
])

directory_path = Enum.at(System.argv(), 0)

if not File.dir?(directory_path) do
  IO.puts("Error: Directory '#{directory_path}' does not exist")
  :error
else
  # Find all .mid files in the directory
  midi_files =
    File.ls!(directory_path)
    |> Enum.filter(fn file -> String.ends_with?(file, ".mid") end)
    |> Enum.map(fn file -> Path.join(directory_path, file) end)

  if Enum.empty?(midi_files) do
    IO.puts("No MIDI files found in '#{directory_path}'")
  else
    IO.puts("Found #{length(midi_files)} MIDI file(s) in '#{directory_path}'")
    IO.puts("------------------------------------------------------")

    # Process each MIDI file
    all_event_types = Enum.reduce(midi_files, MapSet.new([]), fn file_path, top_acc ->
      filename = Path.basename(file_path)

      try do
        # Attempt to read the MIDI file
        sequence = Midifile.read(file_path)
        v = Enum.reduce(sequence.tracks, MapSet.new([]), fn track, mid_acc ->
          events = track.events
          MapSet.union(mid_acc, Enum.reduce(events, MapSet.new([]), fn e, acc -> MapSet.put(acc, e.symbol) end))
        end)
        MapSet.union(top_acc, v)
      rescue
        e in _ ->
          # Handle read errors
          error_message = case e do
            %File.Error{reason: reason} ->
              "file error: #{inspect(reason)}"
            %MatchError{} ->
              "format error: not a valid MIDI file or unsupported format"
            _ ->
              "read error: #{inspect(e)}"
          end

          IO.puts("✗ #{filename}: #{error_message}")
      end
    end)
      |> Enum.to_list
      |> Enum.map(fn a -> Atom.to_string(a) end)
      |> Enum.join(", ")
    IO.puts("#{all_event_types}")
    IO.puts("\n")

  end

  :ok
end
