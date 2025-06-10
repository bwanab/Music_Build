#!/usr/bin/env elixir

# Enhanced debug script to identify the specific timing bug in channel delay calculation
# Run with: mix run debug_timing_bug.exs

# Read the MIDI file
midi_file_path = "midi/Diana_Krall_-_The_Look_Of_Love.mid"
sequence = Midifile.read(midi_file_path)

IO.puts("=== TIMING BUG ANALYSIS ===")
IO.puts("File: #{midi_file_path}")
IO.puts("TPQN: #{sequence.ticks_per_quarter_note}")
IO.puts("")

track_number = 0
significant_events = MapEvents.read_significant_events(sequence, track_number)

IO.puts("=== DETAILED EVENT ANALYSIS (First 30 events) ===")
IO.puts("Idx | Channel | Delta | Symbol     | Cumul.Ticks | Cumul.Beats | Notes")
IO.puts("----|---------|-------|------------|-------------|-------------|-------")

# Track the actual first note-on events
first_note_ons = %{}
cumulative_time = 0

significant_events
|> Enum.take(30)
|> Enum.with_index()
|> Enum.each(fn {{channel, delta, symbol}, index} ->
  cumulative_time = cumulative_time + delta
  cumulative_beats = cumulative_time / sequence.ticks_per_quarter_note
  
  # Track first note-on appearances
  first_note_ons = if symbol == :on and not Map.has_key?(first_note_ons, channel) do
    Map.put(first_note_ons, channel, cumulative_time)
  else
    first_note_ons
  end
  
  notes = cond do
    symbol == :on and not Map.has_key?(first_note_ons, channel) -> " <- FIRST NOTE-ON"
    symbol == :on -> " (note-on)"
    symbol == :controller and delta > 0 -> " (time advances)"
    symbol == :controller -> " (setup)"
    true -> ""
  end
  
  symbol_str = case symbol do
    :on -> "Note ON"
    :off -> "Note OFF"  
    :controller -> "Controller"
    other -> to_string(other)
  end
  
  IO.puts("#{String.pad_leading(to_string(index + 1), 3)} | " <>
          "   #{String.pad_leading(to_string(channel), 2)} " <>
          "   | #{String.pad_leading(to_string(delta), 5)} " <>
          "| #{String.pad_trailing(symbol_str, 10)} " <>
          "| #{String.pad_leading(to_string(cumulative_time), 11)} " <>
          "| #{String.pad_leading(:erlang.float_to_binary(cumulative_beats, [decimals: 3]), 11)}" <>
          notes)
end)

IO.puts("")
IO.puts("=== COMPARING METHODS ===")

# Method 1: Using MapEvents.calculate_channel_delays_from_significant_events (internal method)
tpqn = sequence.ticks_per_quarter_note
{channel_delays_mapevents, _, _} = 
  significant_events
  |> Enum.reduce({%{}, 0, MapSet.new()}, fn {channel, delta, symbol}, {delays_acc, cumulative_time, seen_channels} ->
    new_cumulative_time = cumulative_time + delta
    
    if symbol == :on and not MapSet.member?(seen_channels, channel) do
      delay_quarter_notes = cumulative_time / tpqn  # This is the potential bug!
      new_delays = Map.put(delays_acc, channel, delay_quarter_notes)
      new_seen = MapSet.put(seen_channels, channel)
      {new_delays, new_cumulative_time, new_seen}
    else
      {delays_acc, new_cumulative_time, seen_channels}
    end
  end)

# Method 2: Calculate delays by looking at actual first note-on timing
{channel_delays_corrected, _} = 
  significant_events
  |> Enum.reduce({%{}, 0}, fn {channel, delta, symbol}, {delays_acc, cumulative_time} ->
    new_cumulative_time = cumulative_time + delta
    
    if symbol == :on and not Map.has_key?(delays_acc, channel) do
      delay_quarter_notes = new_cumulative_time / tpqn  # Use the time WHEN the note occurs
      new_delays = Map.put(delays_acc, channel, delay_quarter_notes)
      {new_delays, new_cumulative_time}
    else
      {delays_acc, new_cumulative_time}
    end
  end)

IO.puts("MapEvents method (potentially buggy):")
channel_delays_mapevents
|> Enum.sort()
|> Enum.each(fn {channel, delay} ->
  IO.puts("  Channel #{channel}: #{:erlang.float_to_binary(delay, [decimals: 3])} quarter notes")
end)

IO.puts("")
IO.puts("Corrected method (using note occurrence time):")
channel_delays_corrected
|> Enum.sort()
|> Enum.each(fn {channel, delay} ->
  IO.puts("  Channel #{channel}: #{:erlang.float_to_binary(delay, [decimals: 3])} quarter notes")
end)

IO.puts("")
IO.puts("=== BUG ANALYSIS ===")
IO.puts("The bug appears to be in the delay calculation.")
IO.puts("Current MapEvents uses 'cumulative_time' (time BEFORE the note)")
IO.puts("It should use 'new_cumulative_time' (time WHEN the note occurs)")
IO.puts("")

# Show the difference for a few channels
IO.puts("Differences:")
channel_delays_mapevents
|> Enum.sort()
|> Enum.take(5)
|> Enum.each(fn {channel, old_delay} ->
  new_delay = Map.get(channel_delays_corrected, channel, 0)
  diff = new_delay - old_delay
  IO.puts("  Channel #{channel}: Current=#{:erlang.float_to_binary(old_delay, [decimals: 3])}, " <>
          "Corrected=#{:erlang.float_to_binary(new_delay, [decimals: 3])}, " <>
          "Diff=#{:erlang.float_to_binary(diff, [decimals: 3])}")
end)

IO.puts("")
IO.puts("=== CONCLUSION ===")
IO.puts("The timing bug is in MapEvents.calculate_channel_delays_from_significant_events/2")
IO.puts("Line ~772: delay_quarter_notes = cumulative_time / tpqn")
IO.puts("Should be: delay_quarter_notes = new_cumulative_time / tpqn")