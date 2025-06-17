defmodule MidiPlayer do
  require Logger

  def test() do
    c_scale = Scale.major_scale(:C, 4)
    delayed_scale = [Rest.new(0.5, 1) | c_scale] |> Enum.map(fn note -> Sonority.copy(note, channel: 1, octave: 2) end)
    stm = %{
       0 => STrack.new("c_scale", c_scale, 960, :instrument, 73, 100),
       1 => STrack.new("delayed_scale", delayed_scale, 960, :instrument, 32, 100),
     }
    play_strack_map(stm)
  end


  @spec play_file(String.t()) :: pid()
  def play_file(name) do
    seq = Midifile.read(name)
    play_seq(seq)
  end

  def play_strack_map(stm, bpm \\ 100, tpqn \\ 960) do
    seq = MusicBuild.Util.build_sequence(stm, "dork", bpm, tpqn)
    play_seq(seq)
  end

  def play_seq(seq) do
    state = initial_state(seq)
    {:ok, metronome_pid} = MetronomeServer.start_link(seq, state)
    MetronomeServer.start_playback(metronome_pid)
    metronome_pid
  end

  def stop(metronome_pid) do
    MetronomeServer.stop_playback(metronome_pid)
  end

  @spec initial_state(map) :: map
  def initial_state(seq, _trys \\ 0) do
    out_ports = Midiex.ports(~r/FluidSynth/, :output)
    if length(out_ports) < 1 do
      exit("fluid synth isn't running")
    else
      fluid = Midiex.open(List.first(out_ports))

      %{
        :tpqn => seq.ticks_per_quarter_note,
        :synth => fluid,
        :bpm => Midifile.Sequence.bpm(seq),
        :metronome_ticks_per_quarter_note => 120
      }
    end
  end
end

defmodule MetronomeServer do
  use GenServer
  require Logger

  def start_link(seq, state) do
    GenServer.start_link(__MODULE__, {seq, state})
  end

  def start_playback(pid) do
    GenServer.call(pid, :start_playback)
  end

  def stop_playback(pid) do
    GenServer.call(pid, :stop_playback)
  end

  @impl true
  def init({seq, state}) do
    track_events = Enum.map(seq.tracks, fn track -> track.events end)

    {:ok, %{
      seq: seq,
      state: state,
      track_events: track_events,
      track_pids: [],
      playing: false,
      tick_count: 0,
      timer_ref: nil
    }}
  end

  @impl true
  def handle_call(:start_playback, _from, state) do
    if not state.playing do
      track_pids = start_track_servers(state.track_events, state.state)

      new_state = %{state |
        track_pids: track_pids,
        playing: true,
      }
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :already_playing}, state}
    end
  end

  @impl true
  def handle_call(:stop_playback, _from, state) do
    if state.playing do
      Enum.each(state.track_pids, fn pid -> TrackServer.stop(pid) end)
      new_state = %{state | playing: false, track_pids: [], timer_ref: nil}
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :not_playing}, state}
    end
  end

  defp start_track_servers(track_events_list, state) do
    Enum.map(track_events_list, fn events ->
      {:ok, pid} = TrackServer.start_link(events, state)
      pid
    end)
  end
end

defmodule TrackServer do
  use GenServer
  require Logger

  def start_link(events, state) do
    GenServer.start_link(__MODULE__, {events, state})
  end

  def stop(pid) do
    GenServer.call(pid, :stop)
  end

  def tick(pid) do
    GenServer.cast(pid, :tick)
  end

  @impl true
  def init({events, state}) do
    {:ok, process_next_event(%{
      channel: 0,
      events: events,
      state: state,
    })}
  end

  @impl true
  def handle_call(:stop, _from, state) do
    bytes = [176 + state.channel, 123, 0]
    Midiex.send_msg(state.state.synth, IO.iodata_to_binary(bytes))
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    {:noreply, process_next_event(state)}
  end

  defp process_next_event(%{events: []} = state) do
    state
  end

  defp process_next_event(%{events: [event | remaining_events]} = state) do
    #Logger.debug(event)
    case event do


      %Midifile.Event{symbol: symbol, delta_time: _delta, bytes: bytes} ->
        unless symbol == :track_end or symbol == :seq_name do
          Midiex.send_msg(state.state.synth, IO.iodata_to_binary(bytes))
        end

        next_event_ticks = if length(remaining_events) > 0 do
          next_event = List.first(remaining_events)
          delta_to_ticks(next_event.delta_time, state.state.bpm, state.state.tpqn)
        else
          0
        end

        channel = if symbol == :program do
          Midifile.Event.channel(event)
        else
          state.channel
        end

        pid = self()
        spawn(fn ->
          busy_wait_microseconds(next_event_ticks)
          send(pid, :tick)
        end)

        %{state |
          channel: channel,
          events: remaining_events,
        }
    end
  end



  def busy_wait_microseconds(microseconds) do
    start_time = :erlang.monotonic_time(:microsecond)
    target_time = start_time + microseconds

    wait_until(target_time)
  end

  defp wait_until(target_time) do
    if :erlang.monotonic_time(:microsecond) < target_time do
      wait_until(target_time)
    end
  end


  @microseconds_per_minute 60_000_000

  def delta_to_ticks(delta_time, bpm, tpqn) do
    if delta_time == 0 do
      0
    else
      quarter_notes = delta_time / tpqn
      # Logger.info("#{quarter_notes * ticks_per_quarter} #{round(quarter_notes * ticks_per_quarter)}")
      round(quarter_notes *  @microseconds_per_minute / bpm)
    end
  end

end
