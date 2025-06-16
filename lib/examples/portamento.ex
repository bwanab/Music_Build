defmodule MusicBuild.Examples.Portamento do

  alias Chord
  alias MusicBuild.Util

  def build_portamento() do
    n1 = Note.new(:C, octave: 3, duration: 1)
    midi_note_val = MidiNote.to_midi(n1)
    notes = [
      Controller.new(5, 127, 0),
      n1,
      Controller.new(65, 127, 0),
      #Controller.new(84, <<127::size(8), midi_note_val::size(8)>>, 0),
      Note.new(:C, octave: 4, duration: 1)
    ]
    %{
     0 => STrack.new("notes", notes, 960, :instrument, 73, 100),
    }
  end

  def play_portamento() do
    Util.write_midi_file(build_portamento(), "midi/portamento.mid")
  end

end
