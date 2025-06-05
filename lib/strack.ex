defmodule STrack do
  @type stype :: :instrument | :percussion

  @type t :: %__MODULE__{
    name: String.t(),
    type: stype(),
    ticks_per_quarter_note: Integer,
    sonorities: [Sonority.t()]
  }


  defstruct [:name, :type, :ticks_per_quarter_note, :sonorities]

  def new(name, sonorities, tpqn, type \\ :instrument) do
    %__MODULE__{name: name, type: type, ticks_per_quarter_note: tpqn, sonorities: sonorities}
  end

end
