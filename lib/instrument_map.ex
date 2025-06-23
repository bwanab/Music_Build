defmodule InstrumentMap do
  use Agent

  def start_link() do
    case Agent.start_link(fn -> build_map() end, name: __MODULE__) do
      {:ok, pid}  -> pid
      {:error, {_, pid}} -> pid
    end
  end

  def get_program(inst) do
    Agent.get(__MODULE__, & Map.get(&1, inst, :error))
  end

  def get_instrument(program_number) do
    original = Agent.get(__MODULE__, & &1)
    inverted = Map.new(original, fn {k, v} -> {v, k} end)
    Map.get(inverted, program_number, :invalid_program_number)
  end

  def search(search_string, num_to_return \\ 20) do
    table = Agent.get(__MODULE__, & &1)
    contains_group = Map.keys(table)
    |> Enum.filter(fn a -> String.contains?(Atom.to_string(a), search_string) end)

    len_cg = length(contains_group)
    if len_cg >= num_to_return do
      contains_group
    else
      contains_group ++ (Map.keys(table)
      |> Enum.map(fn a ->
        {String.jaro_distance(Atom.to_string(a), search_string), a}
      end)
      |> Enum.sort(:desc)
      |> Enum.take(num_to_return - len_cg)
      |> Enum.map(fn {_, a} -> a end))
    end
  end

  def build_map() do
    case File.exists?("midi_instrument_map.csv") do
      true ->
        File.stream!("midi_instrument_map.csv")
        |> CSV.decode(headers: true)
        |> Enum.reduce(%{}, fn
          {:ok, %{"PC" => pc_str, "Instrument" => instrument}}, acc ->
            inst_atom = String.replace(instrument, " ", "_")
                        |> String.to_atom()
            case Integer.parse(pc_str) do
              {pc, ""} -> Map.put(acc, inst_atom, pc)
              _ -> acc
            end
          _, acc -> acc
        end)
      false ->
        %{}  # Return empty map if file doesn't exist
    end
  end
end
