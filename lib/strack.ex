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

  def new(sonorities, opts \\ []) do
    name = Keyword.get(opts, :name, "UnNamed")
    tpqn = Keyword.get(opts, :tpqn, 960)
    type = Keyword.get(opts, :type, :instrument)
    program_number = Keyword.get(opts, :program_number, 0)
    bpm = Keyword.get(opts, :bpm, 100)
    
    %__MODULE__{name: name, type: type, ticks_per_quarter_note: tpqn, program_number: program_number, bpm: bpm, sonorities: sonorities}
  end

end
