defmodule AE30Player do
  alias Midiex.Listener

  @moduledoc """
  A simple real time midi player. You need an input device like a midi keyboard connected and a midi GM synth. These both need to be
  connected to your computer. The details of that are very OS and device dependent.

  Possibly the simplest output synth is the default fluidsynth which can be downloaded free on Windows, MacOS, and Linux.
  It can be run as a service, or on MacOS run with:

  fluidsynth -a coreaudio -m coremidi

  The fluidsynth web site has command lines for other OSs.

  Instruments are listed in midi_instrument_map.csv. The instrument names to use are the name in the file prefixed with a colon to make
  it an elixir atom. Thus, for "flute" use :flute, etc. There is a simple search function in InstrumentMap

  InstrumentMap.search("vio") -> [:violin, :viola, :viola, :violin, :voice_oohs, :piccolo, :clavinet, :vibraphone, :taiko_drum, :helicopter]

  Once you get it set up, start it with AE30Player.start(input: the device name of your midi, output: name of your synth, inst: inst atom)

  Use AE30Player.save(file name) to save your creation to a midi file for later playback.
  """

  use GenServer
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def change_program(pid, prog_str) do
    GenServer.call(pid, {:set_program, prog_str})
  end

  def handle_message(pid, msg) do
    GenServer.call(pid, {:input_message, msg})
  end

  def clear(pid) do
    GenServer.call(pid, :clear)
  end

  def get_sequence(pid, name) do
    GenServer.call(pid, {:get_sequence, name})
  end

    @doc"""
  save your masterpiece for enjoying later
  """
  def save(pid, name \\ "UnNamed", path \\ nil) do
    path = if is_nil(path) do
       "midi/#{name}.mid"
    else
      path
    end
    Midifile.write(get_sequence(pid, name), path)
  end


  @impl true
  def init(opts \\ []) do
    input_device_name = Keyword.get(opts, :input, "AE-30")
    instrument = Keyword.get(opts, :inst, :flute)
    record = Keyword.get(opts, :record, true)
    ticks_per_quarter_note = Keyword.get(opts, :ticks_per_quarter_note, 960)
    bpm = Keyword.get(opts, :bpm, 100)

    input_port = case MidiPlayer.get_port(input_device_name, :input) do
      {:ok, port} -> port
      {:error, nil} -> exit("midi device #{input_device_name} isn't attached")
    end
    output_synth_name = Keyword.get(opts, :output, "FluidSynth")
    output_synth = case Keyword.get(opts, :synth) do
      nil ->
        case MidiPlayer.get_port(output_synth_name, :output) do
          {:ok, port} ->  Midiex.open(port)
          {:error, nil} -> exit("#{output_synth_name} isn't running")
        end
      synth -> synth
    end
    {:ok, listener} = Listener.start_link(port: input_port)

    pid = self()
    prog_event = set_program(instrument, output_synth)
    my_msg_hander = fn msg -> handle_message(pid, msg) end

    Listener.add_handler(listener, my_msg_hander)
    {:ok, %{
      playing: false,
      input_device_name: input_device_name,
      output_synth_name: output_synth_name,
      output_synth: output_synth,
      instrument: instrument,
      recording: record,
      listener: listener,
      input_port: input_port,
      event_keeper: [prog_event],
      last_ts: 0,
      ticks_per_quarter_note: ticks_per_quarter_note,
      bpm: bpm
    }}
  end

  @impl true
  def handle_call({:input_message, msg}, _from, %{output_synth: output_synth,
                                                  last_ts: last_ts,
                                                  event_keeper: event_keeper,
                                                  recording: record,
                                                  ticks_per_quarter_note: tpqn,
                                                  bpm: bpm} = state) do
      Midiex.send_msg(output_synth, IO.iodata_to_binary(msg.data))
      #IO.inspect("#{Enum.join(msg.data, ",")}")
      delta_time = if last_ts == 0 do
          0
        else
          d = (msg.timestamp - last_ts) |> TrackServer.ticks_to_delta(bpm, tpqn)
          d / 1000 |> round()
      end

      new_event_keeper = if record do
        data = if length(msg.data) > 2, do: msg.data, else: msg.data ++ [0]
        {event, _, _} = Midifile.Reader.parse_event(delta_time, IO.iodata_to_binary(data))
        [event | event_keeper]
      else
        event_keeper
      end
      #IO.inspect(event)
      #IO.inspect(delta_time, label: "delta_time")
      #IO.inspect(msg.timestamp, label: "msg.timestamp")
      #IO.inspect(:erlang.monotonic_time(:microsecond), label: "monotonic_time")
      {:reply, :ok, %{state | last_ts: msg.timestamp, event_keeper: new_event_keeper}}
  end

  @impl true
  def handle_call({:set_program, instrument}, _from, %{output_synth: output_synth, event_keeper: events} = state) do
    case set_program(instrument, output_synth) do
      :error -> {:reply, :error, state}
      event -> {:reply, :ok, %{state | instrument: instrument, event_keeper: [event | events]}}
    end
  end

  @impl true
  def handle_call(:clear, _from, state) do
    {:reply, :ok, %{state | last_ts: 0, event_keeper: []}}
  end

  @impl true
  def handle_call({:get_sequence, name}, _from, %{event_keeper: events} = state) do
    {:reply, events_to_sequence(name, Enum.reverse(events)), state}
  end

  defp set_program(instrument, fluid) do
    InstrumentMap.start_link()
    channel_number = 0
    case InstrumentMap.get_program(instrument) do
      :error -> :error
      inst_num ->
        program_data = [192 + channel_number, inst_num]
        Midiex.send_msg(fluid, IO.iodata_to_binary(program_data))
        %Midifile.Event{symbol: :program, delta_time: 0, bytes: program_data}
    end
  end

  def events_to_sequence(name \\ "UnNamed", events) do
    e1 = [%Midifile.Event{symbol: :seq_name, delta_time: 0, bytes: name}]
    e_last = [%Midifile.Event{symbol: :track_end, delta_time: 0, bytes: []}]
    track = %Midifile.Track{name: name, events: e1 ++ events ++ e_last}
    Midifile.Sequence.new("dork", 100, [track], 960)
  end

  def close({listener, input_port}) do
    Listener.unsubscribe(listener, input_port)
  end



end
