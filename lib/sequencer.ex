defmodule Sequencer do

  @type t :: %__MODULE__{
    repeats: integer(),
    seq: [Sequencer.t()] | [Sonority.t()] | Sonority.t()
  }

  defstruct [:repeats, :seq]

  def build(%Sequencer{repeats: repeats, seq: seq}) when is_list(seq) do
    cond do
      seq == [] -> []
      is_struct(List.first(seq)) -> List.duplicate(Enum.flat_map(seq, fn s -> build(s) end), repeats) |> List.flatten()
      true -> List.duplicate(seq, repeats) |> List.flatten
    end

  end

  def build(%Sequencer{repeats: repeats, seq: sonority}) do
    List.duplicate(sonority, repeats)
  end


end
