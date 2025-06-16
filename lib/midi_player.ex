defmodule MidiPlayer do
  require Logger

  @spec play_file(String.t()) :: :ok
  def play_file(name) do
    seq = Midifile.read(name)
    play_seq(seq)
  end

  def play_strack_map(stm, bpm \\ 100, tpqn \\ 960) do
    seq = MusicBuild.Util.build_sequence(stm, "dork", bpm, tpqn)
    play_seq(seq)
  end

  def play_seq(seq) do
     play(seq, initial_state(seq))
  end


  @doc """
  In type 1 files, the first track contains the timing data for all the tracks.
  """
  #@spec play(map, map) :: :ok
  def play(seq, state) do
    # message_worker(List.first(tracks).midi_messages, state) # for testing
    Enum.map(seq.tracks, fn x -> x.events end)
    |> process_messages(state)
  end

  @spec play_type2(map) :: :ok
  def play_type2(_midi) do
    throw("Don't know how to play type 2")
  end

  @spec initial_state(map) :: map
  def initial_state(seq, _trys \\ 0) do
    # if trys > 5 do
    #   exit("fluidsynth won't start")
    # end

    out_ports = Midiex.ports(~r/FluidSynth/, :output)
    if length(out_ports) < 1 do
      exit("fluid synth isn't running")
      # port = Port.open({:spawn, "fluidsynth -a coreaudio -m coremidi"}, [
      #                   :binary,
      #                   :exit_status,
      #                   {:line, 1024}
      #                 ])
      # receive do
      #   {^port, {:data, {:eol, line}}} ->
      #     IO.puts("FluidSynth output: #{line}")
      #   {^port, {:exit_status, status}} ->
      #     IO.puts("FluidSynth exited with status: #{status}")
      # after
      #   5000 ->
      #     IO.puts("Timeout waiting for response")
      # end

      # IO.puts("after fluidsynth run command")
      # Process.sleep(500)
      # initial_state(seq, trys + 1)
    else
      fluid = Midiex.open(List.first(out_ports))

      %{
        :tpqn => seq.ticks_per_quarter_note,
        :synth => fluid,
        :bpm => Midifile.Sequence.bpm(seq)
      }
    end
  end

  @spec process_messages(list, map) :: :ok
  def process_messages(list_of_message_lists, state) do
    stream =
      Task.async_stream(
        list_of_message_lists,
        fn ml -> message_worker(ml, state) end,
        [{:timeout, :infinity}]
      )

    Stream.run(stream)
  end


  def message_worker([%Midifile.Event{symbol: symbol, delta_time: delta, bytes: b} | rest], state) do
    wait(delta, state)
    # Logger.info("symbol #{symbol}")
    case symbol do
      :seq_name ->
        message_worker(rest, state)
      # :track_end ->
        # Logger.info("End of track")
      _ ->
        Midiex.send_msg(state.synth, IO.iodata_to_binary(b))
        # Logger.info("message sent: #{Enum.join(Enum.map(b, fn x -> to_string(x) end), ",")}}")
        message_worker(rest, state)

    end
  end

  @spec wait(number, map) :: :ok
  def wait(delta, state) do
    if delta > 0 do
      bps = state.bpm / 60
      ms_to_sleep = round(delta / bps * 1000 / state.tpqn)

      # Logger.info(
      #   "delta = #{delta} state.bpm = #{state.bpm} ms_to_sleep = #{ms_to_sleep}"
      # )

      Process.sleep(ms_to_sleep)
    end
  end

 end
