defmodule MusicBuild.Examples.MidiFromScratch do
  import Scale
  alias Rest
  alias Arpeggio
  import MusicBuild.Util

  # creates a C major scale where each note has a duration of 1 quarter note and writes it to a midifile.
  def midifile_from_scratch(out_type \\ :midi) do
    c_major = major_scale(:C, 4)
    write_file([c_major], "c_major_scale", out_type)
  end

  # this is only for testing. The only case it can add a rest assumes all the notes are 1 quarter note and
  # it only adds at the beginning of the qn. More advanced uses must be "by hand" or are use cases for
  # a later date.
  def midifile_with_rest(out_type \\ :midi) do
    c_major = major_scale(:C, 4)
    {c_major, _td} = add_rest_at_keeping_total_duration(c_major, 0, 0.5)
    write_file([c_major], "c_major_scale_with_rest", out_type)
  end

  # this is an example of building a chord sequence mixed with a rest and a two note melody line.
  # don't expect it do sound good :)
  # BTW: Dialyzer complains about this function, but it compiles and works correctly.
  @spec midi_file_mixed_chords_notes_rests(atom()) :: :ok
  def midi_file_mixed_chords_notes_rests(out_type \\ :midi) do
    sonorities = [
      Note.new(:C, octave: 4, duration: 1),
      Rest.new(1),
      Chord.new(:A, :major, octave: 4, duration: 1),
      Note.new(:E, octave: 4, duration: 1),
      Note.new(:F, octave: 4, duration: 1),
      Note.new(:G, octave: 4, duration: 1.5),     # dotted quarternote
      Note.new(:Gb, octave: 4, duration: 3)     # dotted halfnote
    ]
    write_file([sonorities], "with chords", out_type)
  end

  def midi_file_from_arpeggio(out_type \\ :midi) do
    arpeggio = Arpeggio.new(Chord.new(:C, :major, octave: 4, duration: 4), :up, 1)
    write_file([Sonority.to_notes(arpeggio)], "arpeggio", out_type)
  end

  # this is an example of building a sequence of arpeggios that are repeated.
  # it is actually somewhat musical.
  def midi_file_from_arpeggio_repeated(out_type \\ :midi) do
    dur = 0.5
    arpeggio1 = Arpeggio.repeat(Arpeggio.new(Chord.new(:C, :minor, octave: 4, duration: dur), :up, dur), 4)
    arpeggio2 = Arpeggio.repeat(Arpeggio.new(Chord.new(:F, :minor, octave: 4, duration: dur), :up, dur), 4)
    arpeggio3 = Arpeggio.repeat(Arpeggio.new(Chord.new(:Ab, :major, octave: 3, duration: dur), :up, dur), 4)
    arpeggio4 = Arpeggio.repeat(Arpeggio.new(Chord.new(:G, :minor, octave: 3, duration: dur), :up, dur), 4)
    sonorities = [arpeggio1, arpeggio2, arpeggio3, arpeggio4]
    sonorities = List.duplicate(sonorities, 4) |> List.flatten()
    write_file([sonorities], "multiple_arpeggios_repeated", out_type)
  end

  # this creates a chord sequence with 10 measures. There is randomness in the computation of the series,
  # but it is built on a foundation of logical chord sequences so add this to a midi player with an
  # appropriate string/organ/brass like instrument and it should sound pleasing albeit possibly incipid.
  @spec midi_file_from_chord_progression(atom(), number()) :: :ok
  def midi_file_from_chord_progression(out_type \\ :midi, dur \\ 4) do
    # Get chord symbols (Roman numerals) from ChordPrims
    roman_numerals = ChordPrims.random_progression(10, 1)

    # Use the enhanced Chord API to create chords directly from Roman numerals
    chords = Enum.map(roman_numerals, fn roman_numeral ->
      # Create chord using the new from_roman_numeral function
      Chord.from_roman_numeral(roman_numeral, :C, octave: 4, duration: dur)
    end)

    write_file([chords], "random_progression", out_type)
  end



  def file_two_tracks(out_type \\ :lily) do
    # Get chord symbols (Roman numerals) from ChordPrims
    roman_numerals = ChordPrims.random_progression(20, 1)

    # Use the enhanced Chord API to create chords directly from Roman numerals
    track1 = Enum.map(roman_numerals, fn roman_numeral ->
      # Create chord using the new from_roman_numeral function
      Chord.from_roman_numeral(roman_numeral, :C, octave: 4, duration: 1)
    end)

    # here we take every 4th roman numeral and get the root
    # note of each chord as our bass line
    root_numerals = Enum.take_every(roman_numerals, 4)
    chords = Enum.map(root_numerals, fn roman_numeral ->
        Chord.from_roman_numeral(roman_numeral, :C, octave: 2, duration: 4)
    end)
    track2 = Enum.map(chords, fn c -> Enum.at(Sonority.to_notes(c), 0) end)

    write_file([track1, track2], "two tracks", out_type)
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
    ms = List.replace_at(ms, pos, Sonority.copy(note, duration: duration))
    total_dur = Enum.reduce(ms, 0,  &(&1.duration + &2))
    {ms, total_dur}
  end
end
