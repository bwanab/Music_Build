defmodule MultiTrackSyncTest do
  use ExUnit.Case

  describe "multi-track synchronization" do
    test "calculate_track_starting_offsets identifies track timing differences" do
      # Load the multi-track MIDI file from the bug report
      seq = Midifile.read("midi/01Duet_1.mid")
      
      # Calculate track starting offsets
      offsets = MapEvents.calculate_track_starting_offsets(seq)
      
      # Based on the bug report script, we expect:
      # Track 0: program event at delta_time 0
      # Track 1: program event at delta_time 128
      assert Map.get(offsets, 0) == 0
      assert Map.get(offsets, 1) == 128
    end

    test "one_track_to_sonorities applies track_offset correctly" do
      seq = Midifile.read("midi/01Duet_1.mid")
      
      # Process track 1 without offset (old behavior)
      track_1_no_offset = MapEvents.one_track_to_sonorities(seq, 1)
      
      # Process track 1 with offset (new behavior)
      track_1_with_offset = MapEvents.one_track_to_sonorities(seq, 1, track_offset: 128)
      
      # The track with offset should have a Rest sonority at the beginning
      # Get the first channel's first sonority
      first_channel = Map.keys(track_1_with_offset) |> Enum.at(0)
      first_sonority_with_offset = track_1_with_offset[first_channel].sonorities |> Enum.at(0)
      first_sonority_no_offset = track_1_no_offset[first_channel].sonorities |> Enum.at(0)
      
      # With offset, the first sonority should be a Rest
      assert Sonority.type(first_sonority_with_offset) == :rest
      
      # Without offset, first sonority might be a controller (since MIDI tracks often start with setup)
      # What matters is that the offset version has a Rest first, and the non-offset doesn't
      refute Sonority.type(first_sonority_no_offset) == :rest
      
      # The rest duration should match the offset (128 ticks divided by ticks per quarter note)
      expected_rest_duration = 128 / seq.ticks_per_quarter_note
      assert Sonority.duration(first_sonority_with_offset) == expected_rest_duration
    end

    test "all_tracks_to_sonorities synchronizes all tracks" do
      seq = Midifile.read("midi/01Duet_1.mid")
      
      # Process all tracks with synchronization
      synchronized_tracks = MapEvents.all_tracks_to_sonorities(seq)
      
      # Process tracks individually without synchronization  
      track_0_unsync = MapEvents.one_track_to_sonorities(seq, 0)
      track_1_unsync = MapEvents.one_track_to_sonorities(seq, 1)
      
      # All tracks should be present in synchronized result
      # Note: channels from different tracks don't overlap in this test file
      track_0_channels = Map.keys(track_0_unsync)
      track_1_channels = Map.keys(track_1_unsync)
      
      # All channels should be present in synchronized result
      Enum.each(track_0_channels, fn channel ->
        assert Map.has_key?(synchronized_tracks, channel)
      end)
      
      Enum.each(track_1_channels, fn channel ->
        assert Map.has_key?(synchronized_tracks, channel)
      end)
      
      # Track 0 should have the same timing (no offset)
      track_0_sync_channel = Enum.at(track_0_channels, 0)
      track_0_first_sonority_sync = synchronized_tracks[track_0_sync_channel].sonorities |> Enum.at(0)
      track_0_first_sonority_unsync = track_0_unsync[track_0_sync_channel].sonorities |> Enum.at(0)
      
      # Should be the same since track 0 has no offset
      assert Sonority.type(track_0_first_sonority_sync) == Sonority.type(track_0_first_sonority_unsync)
      
      # Track 1 should have a rest at the beginning (offset applied)
      track_1_sync_channel = Enum.at(track_1_channels, 0)
      track_1_first_sonority_sync = synchronized_tracks[track_1_sync_channel].sonorities |> Enum.at(0)
      
      # Should be a rest due to the 128-tick offset
      assert Sonority.type(track_1_first_sonority_sync) == :rest
    end

    test "backwards compatibility - single track processing unchanged" do
      seq = Midifile.read("midi/01Duet_1.mid")
      
      # Process single track the old way
      track_0_old = MapEvents.one_track_to_sonorities(seq, 0)
      
      # Process single track with explicit 0 offset
      track_0_new = MapEvents.one_track_to_sonorities(seq, 0, track_offset: 0)
      
      # Should be identical
      assert track_0_old == track_0_new
    end
  end
end