#!/usr/bin/env elixir

# Debug script to analyze timing of significant events in MIDI file
# This helps understand channel delay calculations and timing bugs
# Run with: mix run debug_timing_events.exs

# Read the MIDI file
midi_file_path = "midi/Diana_Krall_-_The_Look_Of_Love.mid"
sequence = Midifile.read(midi_file_path)

IO.puts("=== MIDI File Analysis: #{midi_file_path} ===")
IO.puts("Tracks: #{length(sequence.tracks)}")
IO.puts("TPQN: #{sequence.ticks_per_quarter_note}")
IO.puts("BPM: #{Midifile.Sequence.bpm(sequence)}")
IO.puts("")

# Analyze significant events for the main track (track 0 since there's only 1 track)
track_number = 0
if length(sequence.tracks) > track_number do
  IO.puts("=== Analyzing Track #{track_number} ===")
  
  # Get significant events using MapEvents.read_significant_events
  significant_events = MapEvents.read_significant_events(sequence, track_number)
  
  IO.puts("Total significant events: #{length(significant_events)}")
  IO.puts("")
  
  # Show first 20 events with cumulative timing
  IO.puts("=== First 20 Significant Events ===")
  IO.puts("Channel | Delta | Symbol     | Cumulative Ticks | Cumulative Beats")
  IO.puts("--------|-------|------------|------------------|------------------")
  
  {_final_cumulative, channel_first_appearances} = 
    significant_events
    |> Enum.take(20)
    |> Enum.with_index()
    |> Enum.reduce({0, %{}}, fn {{channel, delta, symbol}, index}, {cumulative_ticks, first_appearances} ->
      new_cumulative = cumulative_ticks + delta
      cumulative_beats = new_cumulative / sequence.ticks_per_quarter_note
      
      # Track first appearance of each channel
      updated_appearances = if not Map.has_key?(first_appearances, channel) and symbol == :on do
        Map.put(first_appearances, channel, {index + 1, new_cumulative, cumulative_beats})
      else
        first_appearances
      end
      
      # Display event info
      symbol_str = case symbol do
        :on -> "Note ON"
        :off -> "Note OFF"
        :controller -> "Controller"
        other -> to_string(other)
      end
      
      IO.puts("   #{String.pad_leading(to_string(channel), 2)} " <>
              "   | #{String.pad_leading(to_string(delta), 5)} " <>
              "| #{String.pad_trailing(symbol_str, 10)} " <>
              "| #{String.pad_leading(to_string(new_cumulative), 16)} " <>
              "| #{String.pad_leading(:erlang.float_to_binary(cumulative_beats, [decimals: 3]), 16)}")
      
      {new_cumulative, updated_appearances}
    end)
  
  IO.puts("")
  IO.puts("=== Channel First Appearances ===")
  IO.puts("Channel | Event # | Cumulative Ticks | Cumulative Beats | Delay from Start")
  IO.puts("--------|---------|------------------|------------------|------------------")
  
  channel_first_appearances
  |> Enum.sort()
  |> Enum.each(fn {channel, {event_num, ticks, beats}} ->
    IO.puts("   #{String.pad_leading(to_string(channel), 2)} " <>
            "   |    #{String.pad_leading(to_string(event_num), 2)} " <>
            "   | #{String.pad_leading(to_string(ticks), 16)} " <>
            "| #{String.pad_leading(:erlang.float_to_binary(beats, [decimals: 3]), 16)} " <>
            "| #{String.pad_leading(:erlang.float_to_binary(beats, [decimals: 3]), 16)}")
  end)
  
  IO.puts("")
  IO.puts("=== Timing Analysis Summary ===")
  
  # Calculate delays using the same method as MapEvents
  tpqn = sequence.ticks_per_quarter_note
  channel_delays = MapEvents.read_significant_events(sequence, track_number)
  |> Enum.reduce({%{}, 0, MapSet.new()}, fn {channel, delta, symbol}, {delays_acc, cumulative_time, seen_channels} ->
    new_cumulative_time = cumulative_time + delta
    
    if symbol == :on and not MapSet.member?(seen_channels, channel) do
      delay_quarter_notes = cumulative_time / tpqn
      new_delays = Map.put(delays_acc, channel, delay_quarter_notes)
      new_seen = MapSet.put(seen_channels, channel)
      {new_delays, new_cumulative_time, new_seen}
    else
      {delays_acc, new_cumulative_time, seen_channels}
    end
  end)
  |> elem(0)  # Extract just the delays map
  
  IO.puts("Channel delays calculated by MapEvents:")
  channel_delays
  |> Enum.sort()
  |> Enum.each(fn {channel, delay} ->
    IO.puts("  Channel #{channel}: #{:erlang.float_to_binary(delay, [decimals: 3])} quarter notes")
  end)
  
  # Show all events up to first occurrence of each channel
  if length(significant_events) > 20 do
    IO.puts("")
    IO.puts("=== Extended Analysis: All Events Until All Channels Appear ===")
    
    max_channels = channel_delays |> Map.keys() |> Enum.max()
    IO.puts("Tracking up to channel #{max_channels}...")
    
    {_final_time, seen_count} = 
      try do
        significant_events
        |> Enum.reduce({0, MapSet.new()}, fn {channel, delta, symbol}, {cumulative_ticks, seen_channels} ->
          new_cumulative = cumulative_ticks + delta
          
          if symbol == :on and not MapSet.member?(seen_channels, channel) do
            cumulative_beats = new_cumulative / sequence.ticks_per_quarter_note
            delay_beats = cumulative_ticks / sequence.ticks_per_quarter_note
            
            IO.puts("Channel #{channel} first appears at tick #{new_cumulative} " <>
                    "(#{:erlang.float_to_binary(cumulative_beats, [decimals: 3])} beats) " <>
                    "with delay #{:erlang.float_to_binary(delay_beats, [decimals: 3])} beats")
            
            new_seen = MapSet.put(seen_channels, channel)
            
            # Stop if we've seen all channels that have delays
            if MapSet.size(new_seen) >= map_size(channel_delays) do
              throw({:done, {new_cumulative, new_seen}})
            else
              {new_cumulative, new_seen}
            end
          else
            {new_cumulative, seen_channels}
          end
        end)
      catch
        {:done, result} -> result
      end
    
    IO.puts("Analyzed #{MapSet.size(seen_count)} unique channels")
  end
  
else
  IO.puts("Error: Track #{track_number} does not exist. Available tracks: 0-#{length(sequence.tracks) - 1}")
end

IO.puts("")
IO.puts("=== Script Complete ===")