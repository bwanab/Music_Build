defmodule ControllerMap do
  use Agent

  def start_link() do
    case Agent.start_link(fn -> build_map() end, name: __MODULE__) do
      {:ok, pid}  -> pid
      {:error, {_, pid}} -> pid
    end
  end

  def get_controller(num) do
    Agent.get(__MODULE__, & Map.get(&1, num, "error"))
  end


  def build_map() do
    case File.exists?("controller_map.csv") do
      true ->
        File.stream!("controller_map.csv")
        |> CSV.decode(headers: true)
        |> Enum.reduce(%{}, fn
          {:ok, %{"Num" => num, "Name" => name}}, acc ->
            case Integer.parse(num) do
              {num, ""} -> Map.put(acc, num, name)
              _ -> acc
            end
          _, acc -> acc
        end)
      false ->
        %{}  # Return empty map if file doesn't exist
    end
  end
end
