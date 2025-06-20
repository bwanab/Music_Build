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

  def start(opts \\ []) do
    input_device = Keyword.get(opts, :input, "AE-30")
    output_synth = Keyword.get(opts, :output, "FluidSynth")
    instrument = Keyword.get(opts, :inst, :flute)
    record = Keyword.get(opts, :record, true)

    input_port = case open_port(input_device, :input) do
      {:ok, port} -> port
      {:error, nil} -> exit("midi device #{input_device} isn't attached")
    end
    fluid = case open_port(output_synth, :output) do
      {:ok, port} ->  Midiex.open(port)
      {:error, nil} -> exit("#{output_synth} isn't running")
    end
    {:ok, listener} = Listener.start_link(port: input_port)
    if record do
      EventKeeper.start_link()
    end
    DeltaTimeKeeper.start_link(0)

    set_program(instrument, fluid)

    my_msg_hander = fn msg ->
      Midiex.send_msg(fluid, IO.iodata_to_binary(msg.data))
      data = if length(msg.data) > 2, do: msg.data, else: msg.data ++ [0]
      #IO.inspect("#{Enum.join(msg.data, ",")}")
      last_ts = DeltaTimeKeeper.set(msg.timestamp)
      delta_time = if last_ts == 0 do
          0
        else
          d = (msg.timestamp - last_ts) |> TrackServer.ticks_to_delta(100, 960)
          d / 1000 |> round()
      end

      if record do
        {event, _, _} = Midifile.Reader.parse_event(delta_time, IO.iodata_to_binary(data))
        EventKeeper.put(event)
      end
      #IO.inspect(event)
      #IO.inspect(delta_time, label: "delta_time")
      #IO.inspect(msg.timestamp, label: "msg.timestamp")
      #IO.inspect(:erlang.monotonic_time(:microsecond), label: "monotonic_time")
    end

    Listener.add_handler(listener, my_msg_hander)
    {listener, input_port}
  end

  def set_program(instrument, fluid) do
    InstrumentMap.start_link()
    channel_number = 0
    program_data = [192 + channel_number, InstrumentMap.get_program(instrument)]
    program_event = %Midifile.Event{symbol: :program, delta_time: 0, bytes: program_data}
    EventKeeper.put(program_event)
    Midiex.send_msg(fluid, IO.iodata_to_binary(program_data))
  end

  @spec open_port(binary(), :input | :output) :: {:ok | :error, %Midiex.MidiPort{} | nil}
  def open_port(regex_string, type) do
    case Regex.compile(regex_string) do
    {:ok, regex} ->
      ports = Midiex.ports(regex, type)
      if length(ports) < 1 do
          {:error, nil}
      else
          {:ok, List.first(ports)}
      end
    _ -> {:error, nil}
    end
  end

  @doc"""
  save your masterpiece for enjoying later
  """
  def save(name \\ "UnNamed") do
    Midifile.write(events_to_sequence(name), "#{name}.mid")
  end

  def events_to_sequence(name \\ "UnNamed") do
    e1 = [%Midifile.Event{symbol: :seq_name, delta_time: 0, bytes: name}]
    e_last = [%Midifile.Event{symbol: :track_end, delta_time: 0, bytes: []}]
    events = e1 ++ EventKeeper.value() ++ e_last
    track = %Midifile.Track{name: name, events: events}
    Midifile.Sequence.new("dork", 100, [track], 960)
  end

  def close({listener, input_port}) do
    Listener.unsubscribe(listener, input_port)
  end

  def clear() do
    EventKeeper.clear()
    DeltaTimeKeeper.set(0)
  end


end

defmodule DeltaTimeKeeper do
  use Agent

  def start_link(initial_value) do
    Agent.start_link(fn -> initial_value end, name: __MODULE__)
  end

  def value() do
    Agent.get(__MODULE__, & &1)
  end

  def set(timestamp) do
    Agent.get_and_update(__MODULE__, &({&1, &1 = timestamp}))
  end
end

defmodule EventKeeper do
  use Agent

  def start_link() do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  def value() do
    Agent.get(__MODULE__, & Enum.reverse(&1))
  end

  def put(event) do
    Agent.update(__MODULE__, &([event | &1]))
  end

  def clear() do
    Agent.update(__MODULE__, &(&1 = []))
  end
end
