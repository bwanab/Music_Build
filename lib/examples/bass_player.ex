defmodule MusicBuild.Examples.BassPlayer do

# Run as: iex --dot-iex path/to/notebook.exs

# Title: Pattern_Eval


alias MusicBuild.Examples.PatternEvaluator
alias WeightedRandom

# First, we'll read the midi file with our bass lines and split them into individual lines. We're defining a 'line' as one 12-bar segment.

@test_dir Path.expand("./test")
@pattern [:I, :IV, :I, :I, :IV, :IV, :I, :I, :V, :IV, :I, :V]

def compute_probability_table() do
  seq = Midifile.read(Path.join(@test_dir, "quantized_blues_bass.mid"))
  sonorities = MapEvents.track_to_sonorities(seq, 0)
  chunks = Enum.chunk_every(sonorities, 12*8)

  # Now, we use the 12-bar chord pattern to break down the lines into chord groupings. That is, we are gathering all the notes as they were played for each of the 3 chords in the progression in the order that they were played. This means in each of the individual lists, we've got 8 notes that are the notes played in their respective positions of each run. This grouping allows us to understand the most likely note to be played in each note position. My prior belief is that the first note is most likely to be the root of the chord and the note is a 'connecting' note from one chord to the next. I have no prior about positions 2-7 (one based).


  mapped = Enum.map(chunks, fn line -> PatternEvaluator.chunk_line(line, 8, @pattern) end)
              |> PatternEvaluator.merge_maps_with_lists()


  root_map = Map.new(Enum.map(Map.keys(mapped), fn k ->
    note = Chord.note_from_roman_numeral(k, :A, 2, :major)
    {k, [note, MidiNote.to_midi(note)]}
  end))

  # Now, we compute the intervals of the notes from the chord roots.

  interval_map = Map.new(Enum.map(mapped, fn {k, v} ->
    [_n, root_note_number] = Map.get(root_map, k)
    {k, Enum.map(v, fn note_list ->
      Enum.map(note_list, fn note ->
        note_number = MidiNote.to_midi(note)
        note_number - root_note_number
      end)
    end)}
    end)
  )

  # Here, we get the raw numerical frequency of each note at each position. Eyeballing the numbers, it looks obvious that the first note is overwhelmingly the root of the chord. The 2nd note is mostly the 4th

  raw_frequency_table = Map.new(Enum.map(interval_map, fn {k, im} ->
    {k, Enum.map(0..7, fn i ->
      Enum.reduce(im, %{}, fn row, acc ->
        value = Enum.at(row, i)
        Map.put(acc, value, Map.get(acc, value, 0) + 1) end)
      end)}
    end)
  )

  # Let's convert the frequency table to probabilities.

  table = Map.new(Enum.map(raw_frequency_table, fn {k, im} ->
      {k, Map.new(Enum.map(Enum.with_index(im), fn {row, ind} ->
        row_count = Enum.sum(Map.values(row))
        {ind, Enum.map(row, fn {interval, count} ->
          {interval, count / row_count}
          end)}
        end))}
    end)
  )

  {root_map, table}
end

# Let's see what we can do:
def build_bass_line(probabilities_table, root_map, num_cycles) do
  base_lines = Enum.flat_map(0..num_cycles, fn _ ->
  Enum.flat_map(@pattern, fn rn ->
    Enum.map(0..7, fn i ->
      [_, root_number] = Map.get(root_map, rn)
      interval = WeightedRandom.take_one(get_in(probabilities_table, [rn, i]))
      MidiNote.midi_to_note(root_number + interval, 0.5, 127)
    end)
    end)
  end)
  MusicBuild.Examples.CleanUpMidiFile.write_midi_file([base_lines],
    Path.join(@test_dir, "generated_blues_bass.mid"))
end


# ── Build the pattern/position probabilities table ──

# ── Next steps ──

# Interesting. I loaded this midi file into the same project that the original bass line had come from. It didn't sound awful - kind of like the bass player equivalent of Ginger Baker playing drums for Cream - it works, but it's really weird. There are two more angles I want to attack this problem with. Let's take stock:

# 1. The approach so far which is figuring out for the given pattern and note position a note that represents the probability weighted best note based on frequencies for that pattern and position.
# 2. Modify the previous with a notion of most likely next note given the position. This could also be a bit of lookahead to determine the most likely next note and make it an internal pattern connecting note as opposed to 3 below.
# 3. Determine the best 'connecting' note. That is, the note that is the last note in a given pattern. This would involve looking behind to the last note played and looking ahead to the next note to be played to determine what should come in between.

# ── Determine the most likely next note ──
end
