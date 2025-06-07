defmodule STrack do
  @type stype :: :instrument | :percussion

  @type t :: %__MODULE__{
    name: String.t(),
    type: stype(),
    ticks_per_quarter_note: Integer,
    program_number: Integer,
    sonorities: [Sonority.t()]
  }


  defstruct [:name, :type, :ticks_per_quarter_note, :program_number, :sonorities]

  def new(name, sonorities, tpqn, type \\ :instrument, program_number \\ 0) do
    %__MODULE__{name: name, type: type, ticks_per_quarter_note: tpqn, program_number: program_number, sonorities: sonorities}
  end

end
