defmodule AE30Player do
  alias Midiex.Listener


  def init() do
# Get the first MIDI input port
    input_port = open_port("AE-30", :input)
    fluid = open_port("FluidSynth", :output) |> Midiex.open()

    {:ok, listener} = Listener.start_link(port: input_port)

    EventKeeper.start_link()
    DeltaTimeKeeper.start_link(0)
    my_msg_hander = fn msg ->
      Midiex.send_msg(fluid, IO.iodata_to_binary(msg.data))
      data = if length(msg.data) > 2, do: msg.data, else: msg.data ++ [0]
      #IO.inspect("#{Enum.join(msg.data, ",")}")
      last_ts = DeltaTimeKeeper.value()
      DeltaTimeKeeper.set(msg.timestamp)
      delta_time = round(TrackServer.ticks_to_delta((if last_ts == 0, do: 0, else: msg.timestamp - last_ts), 100, 960) / 1000)
      {event, _, _} = Midifile.Reader.parse_event(delta_time, IO.iodata_to_binary(data))
      IO.inspect(event)
      EventKeeper.put(event)
      #IO.inspect(delta_time, label: "delta_time")
      #IO.inspect(msg.timestamp, label: "msg.timestamp")
      #IO.inspect(:erlang.monotonic_time(:microsecond), label: "monotonic_time")
    end

    Listener.add_handler(listener, my_msg_hander)
    {listener, input_port}
  end

  @spec open_port(binary(), :input | nil | :output) :: Midiex.MidiPort
  def open_port(regex_string, type) do
    case Regex.compile(regex_string) do
    {:ok, regex} ->
      ports = Midiex.ports(regex, type)
      if length(ports) < 1 do
          exit("#{regex_string} isn't running")
      else
          List.first(ports)
      end
    _ -> exit("regex invalid: #{regex_string}")
    end
  end

  def close({listener, input_port}) do
    Listener.unsubscribe(listener, input_port)
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
    Agent.update(__MODULE__, &(&1 = timestamp))
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
end
