defmodule MidiPlayer do
  require Logger


  @spec play(binary() | STrack.t() | Midifile.Sequence.t(), keyword()) :: pid()

  def play(d, opts \\ [])

  def play(name, _opts) when is_binary(name) do
    seq = Midifile.read(name)
    play(seq)
  end

  def play(stm, opts) when is_map(stm) do
    bpm = Keyword.get(opts, :bpm, 100)
    tpqn = Keyword.get(opts, :tpqn, 960)
    seq = MusicBuild.Util.build_sequence(stm, "dork", bpm, tpqn)
    play(seq)
  end

  def play(%Midifile.Sequence{} = seq, _opts) do
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

        PreciseTimer.start_delay(next_event_ticks, self(), :tick)

        %{state |
          channel: channel,
          events: remaining_events,
        }
    end
  end
  @miilliseconds_per_minute 60_000

  def delta_to_ticks(delta_time, bpm, tpqn) do
    if delta_time == 0 do
      0
    else
      quarter_notes = delta_time / tpqn
      # Logger.info("#{quarter_notes * ticks_per_quarter} #{round(quarter_notes * ticks_per_quarter)}")
      quarter_notes *  @miilliseconds_per_minute / bpm
    end
  end

  def ticks_to_delta(ticks, bpm, tpqn) do
    if ticks == 0 do
      0
    else
      tpqn / (@miilliseconds_per_minute / ticks / bpm)
    end
  end

end

defmodule PreciseTimer do
  @doc"""
  The problem this module is solving is that music playback requires a very high resolution in time.
  E.G. at 70 beats per minute given a ticks per quarter note of 960, for an eight note the number
  of milliseconds between note on and note off is 428.57142857, but since there are no timers in
  erlang or elixir that allow for better resolution than milliseconds, we would either have to
  delay for 428 or 429 milliseconds. After compounding errors like that over a full song,
  we start to get drift between tracks. This module gives microsecond timing capability.
  """
  require Logger
  def start_delay(total_milliseconds, target_pid, message \\ :timer_complete) do
    if total_milliseconds <= 0 do
      send(target_pid, :tick)
    else
      start_time = :erlang.monotonic_time(:microsecond)
      target_time = start_time + total_milliseconds * 1000

      milliseconds = max(floor(total_milliseconds) - 5, 0)
      #Logger.info("milliseconds to sleep #{milliseconds} #{total_milliseconds}")
      #microsecond_remainder = (total_milliseconds - milliseconds) * 1000

      # Logger.info("total: #{total_milliseconds} milli: #{milliseconds} micro: #{microsecond_remainder}")
      # The total_milliseconds is almost always a floating number e.g. 123.456.
      # for really precise timing that doesn't suck up all the cpu, we compute
      # the target time then ideally we  would sleep for the floor(total_milliseconds)
      # but in practice that appears to overshoot the mark which causes timing to get
      # off, so we subtract 5 milliseconds from that. This is entirely experimentally
      # derived, so on a different machine or OS, the values might have to be different.
      # So, we sleep for the this value of milliseconds and finish with a brute
      # force delay until we've reached the target time. For a value that is typical
      # this results in huge cpu savings.
      Process.sleep(milliseconds)
      #Logger.info("after sleep target: #{target_time} current: #{:erlang.monotonic_time(:microsecond)} ")
      spawn(fn ->
        wait_until(target_time)
        send(target_pid, message)
      end)
    end
  end

  defp wait_until(target_time) do
    if :erlang.monotonic_time(:microsecond) < target_time do
      wait_until(target_time)
    end
  end
end
