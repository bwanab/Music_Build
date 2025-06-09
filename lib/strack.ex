defmodule STrack do
  @type stype :: :instrument | :percussion

  @type t :: %__MODULE__{
    name: String.t(),
    type: stype(),
    ticks_per_quarter_note: integer(),
    program_number: integer(),
    bpm: integer(),
    sonorities: [Sonority.t()]
  }


  defstruct [:name, :type, :ticks_per_quarter_note, :program_number, :bpm, :sonorities]

  def new(name, sonorities, tpqn, type \\ :instrument, program_number \\ 0, bpm \\ 100) do
    %__MODULE__{name: name, type: type, ticks_per_quarter_note: tpqn, program_number: program_number, bpm: bpm, sonorities: sonorities}
  end

end
