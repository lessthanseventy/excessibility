defmodule Excessibility.TelemetryCapture.Analyzers.EventPatternTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Analyzers.EventPattern

  describe "name/0" do
    test "returns :event_pattern" do
      assert EventPattern.name() == :event_pattern
    end
  end

  describe "default_enabled?/0" do
    test "returns true" do
      assert EventPattern.default_enabled?() == true
    end
  end

  describe "analyze/2" do
    test "returns map with findings and stats" do
      timeline = %{timeline: []}

      result = EventPattern.analyze(timeline, [])

      assert is_map(result)
      assert Map.has_key?(result, :findings)
      assert Map.has_key?(result, :stats)
    end

    test "detects duplicate consecutive events" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount"},
          %{sequence: 2, event: "handle_event:filter"},
          %{sequence: 3, event: "handle_event:filter"},
          %{sequence: 4, event: "handle_event:filter"}
        ]
      }

      result = EventPattern.analyze(timeline, [])

      duplicate_finding? =
        Enum.any?(result.findings, fn f ->
          f.severity == :warning and f.message =~ "consecutive"
        end)

      assert duplicate_finding?
    end

    test "detects common patterns" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount"},
          %{sequence: 2, event: "handle_event:filter"},
          %{sequence: 3, event: "handle_event:sort"},
          %{sequence: 4, event: "mount"},
          %{sequence: 5, event: "handle_event:filter"},
          %{sequence: 6, event: "handle_event:sort"}
        ]
      }

      result = EventPattern.analyze(timeline, [])

      # Should detect the repeated pattern
      assert Map.has_key?(result.stats, :common_sequences)
    end

    test "detects excessive events" do
      timeline = %{
        timeline:
          Enum.map(1..20, fn i ->
            %{sequence: i, event: "handle_event:update"}
          end)
      }

      result = EventPattern.analyze(timeline, [])

      excessive_finding? =
        Enum.any?(result.findings, fn f ->
          f.severity in [:warning, :info] and f.message =~ ~r/(excessive|many)/i
        end)

      assert excessive_finding?
    end

    test "suggests optimizations for repeated patterns" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount"},
          %{sequence: 2, event: "handle_event:keyup"},
          %{sequence: 3, event: "handle_event:keyup"},
          %{sequence: 4, event: "handle_event:keyup"},
          %{sequence: 5, event: "handle_event:keyup"}
        ]
      }

      result = EventPattern.analyze(timeline, [])

      optimization_suggestion? =
        Enum.any?(result.findings, fn f ->
          f.message =~ ~r/(debounce|debouncing|throttle|throttling)/i
        end)

      assert optimization_suggestion?
    end

    test "calculates event frequency" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount"},
          %{sequence: 2, event: "handle_event:filter"},
          %{sequence: 3, event: "handle_event:filter"},
          %{sequence: 4, event: "handle_event:sort"}
        ]
      }

      result = EventPattern.analyze(timeline, [])

      assert Map.has_key?(result.stats, :event_counts)
      assert result.stats.event_counts["handle_event:filter"] == 2
    end

    test "handles empty timeline" do
      timeline = %{timeline: []}

      result = EventPattern.analyze(timeline, [])

      assert result.findings == []
      assert result.stats == %{}
    end

    test "handles single event timeline" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount"}
        ]
      }

      result = EventPattern.analyze(timeline, [])

      # Should not crash or produce false positives
      assert is_list(result.findings)
    end

    test "identifies most common event" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount"},
          %{sequence: 2, event: "handle_event:click"},
          %{sequence: 3, event: "handle_event:click"},
          %{sequence: 4, event: "handle_event:click"},
          %{sequence: 5, event: "handle_event:hover"}
        ]
      }

      result = EventPattern.analyze(timeline, [])

      assert Map.has_key?(result.stats, :most_common_event)
      assert result.stats.most_common_event == "handle_event:click"
    end

    test "detects mount without follow-up events" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount"}
        ]
      }

      result = EventPattern.analyze(timeline, [])

      # Single mount is normal, shouldn't be flagged
      assert Enum.all?(result.findings, fn f -> f.severity != :warning end)
    end

    test "includes event sequences in findings" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount"},
          %{sequence: 2, event: "handle_event:same"},
          %{sequence: 3, event: "handle_event:same"},
          %{sequence: 4, event: "handle_event:same"}
        ]
      }

      result = EventPattern.analyze(timeline, [])

      if length(result.findings) > 0 do
        finding = List.first(result.findings)
        assert is_list(finding.events)
        assert length(finding.events) > 0
      end
    end
  end
end
