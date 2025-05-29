defmodule MusicBuild.Examples.PatternEvaluator do
  def merge_maps_with_lists(maps) do
    Enum.reduce(maps, %{}, fn map, acc ->
      Map.merge(acc, map, fn _key, list1, list2 ->
        list1 ++ list2
      end)
    end)
  end

  def chunk_line(line, num_per_measure, pattern) do
    measures = Enum.chunk_every(line, num_per_measure)
    Enum.reduce(Enum.zip(pattern, measures), %{}, fn {p, notes}, acc ->
      Map.put(acc, p, Map.get(acc, p, []) ++ [notes])
    end)
  end

end
