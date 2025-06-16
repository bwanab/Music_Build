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
    state = initial_state(seq)
    {:ok, metronome_pid} = MetronomeServer.start_link(seq, state)
    MetronomeServer.start_playback(metronome_pid)
    :ok
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
        :bpm => Midifile.Sequence.bpm(seq)
      }
    end
  end
end

defmodule MetronomeServer do
  use GenServer
  require Logger

  @ticks_per_quarter_note 24

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
      
      tick_interval_ms = calculate_tick_interval(state.state.bpm)
      {:ok, timer_ref} = :timer.send_interval(tick_interval_ms, self(), :tick)
      
      new_state = %{state | 
        track_pids: track_pids, 
        playing: true, 
        timer_ref: timer_ref
      }
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :already_playing}, state}
    end
  end

  @impl true
  def handle_call(:stop_playback, _from, state) do
    if state.playing do
      :timer.cancel(state.timer_ref)
      Enum.each(state.track_pids, fn pid -> TrackServer.stop(pid) end)
      new_state = %{state | playing: false, track_pids: [], timer_ref: nil}
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :not_playing}, state}
    end
  end

  @impl true
  def handle_info(:tick, state) do
    Enum.each(state.track_pids, fn pid -> TrackServer.tick(pid) end)
    {:noreply, %{state | tick_count: state.tick_count + 1}}
  end

  defp start_track_servers(track_events_list, state) do
    Enum.map(track_events_list, fn events ->
      {:ok, pid} = TrackServer.start_link(events, state)
      pid
    end)
  end

  defp calculate_tick_interval(bpm) do
    quarter_note_ms = 60_000 / bpm
    round(quarter_note_ms / @ticks_per_quarter_note)
  end
end

defmodule TrackServer do
  use GenServer
  require Logger

  def start_link(events, state) do
    GenServer.start_link(__MODULE__, {events, state})
  end

  def tick(pid) do
    GenServer.cast(pid, :tick)
  end

  def stop(pid) do
    GenServer.call(pid, :stop)
  end

  @impl true
  def init({events, state}) do
    {:ok, %{
      events: events,
      state: state,
      current_event_ticks_remaining: 0,
      tick_count: 0
    }}
  end

  @impl true
  def handle_cast(:tick, state) do
    new_state = process_tick(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  defp process_tick(state) do
    new_tick_count = state.tick_count + 1
    
    if state.current_event_ticks_remaining <= 1 do
      process_next_event(%{state | tick_count: new_tick_count})
    else
      %{state | 
        current_event_ticks_remaining: state.current_event_ticks_remaining - 1,
        tick_count: new_tick_count
      }
    end
  end

  defp process_next_event(%{events: []} = state) do
    state
  end

  defp process_next_event(%{events: [event | remaining_events]} = state) do
    case event do
      %Midifile.Event{symbol: :seq_name} ->
        process_next_event(%{state | events: remaining_events})
      
      %Midifile.Event{symbol: symbol, delta_time: _delta, bytes: bytes} ->
        unless symbol == :track_end do
          Midiex.send_msg(state.state.synth, IO.iodata_to_binary(bytes))
        end
        
        next_event_ticks = if length(remaining_events) > 0 do
          next_event = List.first(remaining_events)
          delta_to_ticks(next_event.delta_time, state.state.bpm, state.state.tpqn)
        else
          0
        end
        
        %{state | 
          events: remaining_events,
          current_event_ticks_remaining: next_event_ticks
        }
    end
  end

  defp delta_to_ticks(delta_time, _bpm, tpqn) do
    if delta_time == 0 do
      0
    else
      ticks_per_quarter = 24
      quarter_notes = delta_time / tpqn
      round(quarter_notes * ticks_per_quarter)
    end
  end
end