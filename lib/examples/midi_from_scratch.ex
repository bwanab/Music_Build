defmodule MusicBuild.Examples.MidiFromScratch do
  alias Midifile.Sequence
  alias Midifile.Writer
  alias MusicBuild.TrackBuilder
  import Scale
  alias Rest
  alias Arpeggio

  # creates a C major scale where each note has a duration of 1 quarter note and writes it to a midifile.
  def midifile_from_scratch() do
    c_major = major_scale(:C, 4)
    write_midi_file(c_major, "c_major_scale")
  end

  # this is only for testing. The only case it can add a rest assumes all the notes are 1 quarter note and
  # it only adds at the beginning of the qn. More advanced uses must be "by hand" or are use cases for
  # a later date.
  def midifile_with_rest() do
    c_major = major_scale(:C, 4)
    {c_major, _td} = add_rest_at_keeping_total_duration(c_major, 0, 0.5)
    write_midi_file(c_major, "c_major_scale_with_rest")
  end

  # this is an example of building a chord sequence mixed with a rest and a two note melody line.
  # don't expect it do sound good :)
  # BTW: Dialyzer complains about this function, but it compiles and works correctly.
  @spec midi_file_mixed_chords_notes_rests() :: :ok
  def midi_file_mixed_chords_notes_rests() do
    sonorities = create_sonorities()
    write_midi_file(sonorities, "with chords")
  end

  def midi_file_from_arpeggio() do
    arpeggio = Arpeggio.new(Chord.new_from_root(:C, :major, 4, 1.0), :up, 4)
    write_midi_file(Arpeggio.to_notes(arpeggio), "arpeggio")
  end

  # this is an example of building a sequence of arpeggios that are repeated.
  # it is actually somewhat musical.
  def midi_file_from_arpeggio_repeated() do
    arpeggio1 = Arpeggio.repeat(Arpeggio.new(Chord.new_from_root(:C, :minor, 4, 1.0), :up, 1), 4)
    arpeggio2 = Arpeggio.repeat(Arpeggio.new(Chord.new_from_root(:F, :minor, 4, 1.0), :up, 1), 4)
    arpeggio3 = Arpeggio.repeat(Arpeggio.new(Chord.new_from_root(:Ab, :major, 3, 1.0), :up, 1), 4)
    arpeggio4 = Arpeggio.repeat(Arpeggio.new(Chord.new_from_root(:G, :minor, 3, 1.0), :up, 1), 4)
    sonorities = [arpeggio1, arpeggio2, arpeggio3, arpeggio4]
    sonorities = List.duplicate(sonorities, 4) |> List.flatten()
    write_midi_file(sonorities, "multiple_arpeggios_repeated")
  end

  @spec create_sonorities() :: [Sonority.t()]
  def create_sonorities() do
    [
      Note.new({:C, 4}, duration: 1.0),
      Rest.new(1.0),
      Chord.new_from_root(:A, :major, 4, 1.0),
      Note.new({:E, 4}, duration: 1.0),
      Note.new({:F, 4}, duration: 1.0)
    ]
  end

  # this creates a chord sequence with 10 measures. There is randomness in the computation of the series,
  # but it is built on a foundation of logical chord sequences so add this to a midi player with an
  # appropriate string/organ/brass like instrument and it should sound pleasing albeit possibly incipid.
  @spec midi_file_from_chord_progression() :: :ok
  def midi_file_from_chord_progression() do
    # Get chord symbols (Roman numerals) from ChordPrims
    roman_numerals = ChordPrims.random_progression(10, 1)

    # Use the enhanced Chord API to create chords directly from Roman numerals
    chords = Enum.map(roman_numerals, fn roman_numeral ->
      # Create chord using the new from_roman_numeral function
      Chord.from_roman_numeral(roman_numeral, :C, 4, 4.0)
    end)

    write_midi_file(chords, "random_progression")
  end

  @spec write_midi_file([Sonority.t()], binary()) :: :ok
  def write_midi_file(notes, name) do
    track = TrackBuilder.new(name, notes, 960)
    sfs = Sequence.new(name, 110, [track], 960)
    Writer.write(sfs, "test/#{name}.mid")
  end

  @spec add_rest_at_keeping_total_duration([Sonority.t()], integer(), number()) :: {[Sonority.t()], float()}
  def add_rest_at_keeping_total_duration(ms, pos, duration) do
    note = Enum.at(ms, pos)

    {ms, _td} = change_dur_at(ms, pos, note.duration - duration)
    add_rest_at(ms, pos + 1, duration)
  end

  @spec add_rest_at([Sonority.t()], integer(), any()) :: {Sonority.t(), float()}
  def add_rest_at(ms, pos, duration) do
    ms = List.insert_at(ms, pos, Rest.new(duration))
    total_dur = Enum.reduce(ms, 0,  &(&1.duration + &2))
    {ms, total_dur}
  end

  @spec change_dur_at([Sonority.t()], integer(), any()) :: {[Sonority.t()], float()}
  def change_dur_at(ms, pos, duration) do
    note = Enum.at(ms, pos)
    ms = List.replace_at(ms, pos, Note.new(note.note, duration: duration, velocity: note.velocity))
    total_dur = Enum.reduce(ms, 0,  &(&1.duration + &2))
    {ms, total_dur}
  end
end
