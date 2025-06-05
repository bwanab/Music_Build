defmodule MusicBuild.Examples.CleanUpMidiFile do
  alias MusicBuild.TrackBuilder
  alias Midifile.Sequence

  @doc """
  removes all notes that have a duration of less than a 16th note

  Note that this currently assumes a file with one track!
  """
  def filter_bad_notes(pathname) do
    seq = Midifile.Reader.read(pathname)
    filtered_seq = Filter.process_notes(seq, 0, fn note -> note.duration < 0.1 end, :remove)
    outpath = Path.join(Path.dirname(pathname), "filtered_" <> Path.basename(pathname))
    IO.inspect(outpath)
    Midifile.Writer.write(filtered_seq, outpath)
  end

  @doc """
  bumps a midi files notes up one octave.

  NOTE: this only works for tracks that contain no Arpeggios or Chords at present!
  """
  def bump_octave(pathname) do
    seq = Midifile.Reader.read(pathname)
    strack = MapEvents.track_to_sonorities(seq, 0)
    new_sonorities = Enum.map(strack.sonorities, fn s ->
      case Sonority.type(s) do
        :note -> Note.bump_octave(s, :up)
      _ -> s
      end
    end)
    outpath = Path.join(Path.dirname(pathname), "bumped_octave_" <> Path.basename(pathname))
    write_midi_file([new_sonorities], outpath, ticks_per_quarter_note: seq.ticks_per_quarter_note, bpm: Sequence.bpm(seq))
  end

  def write_midi_file(notes, outpath, opts \\ []) do
    tpqn = Keyword.get(opts, :ticks_per_quarter_note, 960)
    bpm = Keyword.get(opts, :bpm, 110)
    name = Path.basename(outpath, Path.extname(outpath))
    tracks = Enum.map(notes, fn track -> TrackBuilder.new(name, track, 960) end)
    sfs = Sequence.new(name, bpm, tracks, tpqn)
    Midifile.write(sfs, outpath)
  end

end
