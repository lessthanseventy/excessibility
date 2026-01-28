defmodule Excessibility.TelemetryCapture.Analyzers.PerformanceTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Analyzers.Performance

  describe "name/0" do
    test "returns :performance" do
      assert Performance.name() == :performance
    end
  end

  describe "default_enabled?/0" do
    test "returns true" do
      assert Performance.default_enabled?() == true
    end
  end

  describe "requires_enrichers/0" do
    test "declares duration enricher dependency" do
      assert Performance.requires_enrichers() == [:duration]
    end
  end

  describe "analyze/2" do
    test "returns map with findings and stats" do
      timeline = %{timeline: []}

      result = Performance.analyze(timeline, [])

      assert is_map(result)
      assert Map.has_key?(result, :findings)
      assert Map.has_key?(result, :stats)
    end

    test "detects no issues with consistent performance" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", event_duration_ms: 10},
          %{sequence: 2, event: "handle_event", event_duration_ms: 12},
          %{sequence: 3, event: "handle_event", event_duration_ms: 11}
        ]
      }

      result = Performance.analyze(timeline, [])

      assert result.findings == []
    end

    test "detects slow event using adaptive threshold" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", event_duration_ms: 10},
          %{sequence: 2, event: "handle_event", event_duration_ms: 12},
          %{sequence: 3, event: "handle_event", event_duration_ms: 200}
        ]
      }

      result = Performance.analyze(timeline, [])

      assert length(result.findings) > 0
      slow_finding = List.first(result.findings)
      assert slow_finding.severity in [:warning, :critical]
      # May be detected as "slow" or "bottleneck" depending on thresholds
      assert slow_finding.message =~ ~r/(slow|bottleneck)/
      assert slow_finding.events == [3]
    end

    test "detects bottleneck (event taking >50% of total time)" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", event_duration_ms: 10},
          %{sequence: 2, event: "handle_event", event_duration_ms: 500},
          %{sequence: 3, event: "handle_event", event_duration_ms: 10}
        ]
      }

      result = Performance.analyze(timeline, [])

      bottleneck_finding? =
        Enum.any?(result.findings, fn f ->
          f.severity == :critical and f.message =~ "bottleneck"
        end)

      assert bottleneck_finding?
    end

    test "calculates performance statistics" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", event_duration_ms: 10},
          %{sequence: 2, event: "handle_event", event_duration_ms: 20},
          %{sequence: 3, event: "handle_event", event_duration_ms: 30}
        ]
      }

      result = Performance.analyze(timeline, [])

      assert result.stats.min_duration == 10
      assert result.stats.max_duration == 30
      assert result.stats.avg_duration == 20
      assert result.stats.total_duration == 60
    end

    test "handles empty timeline" do
      timeline = %{timeline: []}

      result = Performance.analyze(timeline, [])

      assert result.findings == []
      assert result.stats == %{}
    end

    test "handles timeline without duration data" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount"},
          %{sequence: 2, event: "handle_event"}
        ]
      }

      result = Performance.analyze(timeline, [])

      # Should not crash, treat as no duration data
      assert result.findings == []
    end

    test "handles nil duration values" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", event_duration_ms: nil},
          %{sequence: 2, event: "handle_event", event_duration_ms: 50}
        ]
      }

      result = Performance.analyze(timeline, [])

      # Should skip nil values
      assert is_list(result.findings)
    end

    test "marks very slow events as critical" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", event_duration_ms: 10},
          %{sequence: 2, event: "handle_event", event_duration_ms: 5000}
        ]
      }

      result = Performance.analyze(timeline, [])

      critical_finding? =
        Enum.any?(result.findings, fn f ->
          f.severity == :critical and f.events == [2]
        end)

      assert critical_finding?
    end

    test "includes duration in metadata" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", event_duration_ms: 10},
          %{sequence: 2, event: "handle_event", event_duration_ms: 500}
        ]
      }

      result = Performance.analyze(timeline, [])

      assert length(result.findings) > 0
      finding = List.first(result.findings)
      assert Map.has_key?(finding.metadata, :duration_ms)
      assert finding.metadata.duration_ms == 500
    end

    test "detects multiple slow events" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", event_duration_ms: 10},
          %{sequence: 2, event: "handle_event", event_duration_ms: 10},
          %{sequence: 3, event: "handle_event", event_duration_ms: 1500},
          %{sequence: 4, event: "handle_event", event_duration_ms: 2000}
        ]
      }

      result = Performance.analyze(timeline, [])

      # Should detect events 3 and 4 as critical (>1000ms)
      slow_events = Enum.flat_map(result.findings, & &1.events)
      assert 3 in slow_events
      assert 4 in slow_events
      assert length(result.findings) >= 2
    end

    test "handles zero duration without FunctionClauseError" do
      # Reproduces GitHub issue #60
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", event_duration_ms: 0},
          %{sequence: 2, event: "handle_event", event_duration_ms: 0},
          %{sequence: 3, event: "handle_event", event_duration_ms: 10}
        ]
      }

      # Should not crash with FunctionClauseError from Float.round/2
      result = Performance.analyze(timeline, [])

      # Stats should still be calculated
      assert is_map(result.stats)
      assert result.stats.min_duration == 0
      assert result.stats.max_duration == 10
    end

    test "handles all zero durations without FunctionClauseError" do
      # Edge case: all events have 0ms duration (very fast)
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", event_duration_ms: 0},
          %{sequence: 2, event: "handle_event", event_duration_ms: 0},
          %{sequence: 3, event: "handle_event", event_duration_ms: 0}
        ]
      }

      # Should not crash
      result = Performance.analyze(timeline, [])

      # No slow events should be detected
      assert result.findings == []
      assert result.stats.avg_duration == 0
    end

    test "handles slow event when avg_duration is zero" do
      # Reproduces actual issue: slow event detected when average is 0
      # This causes multiplier to be integer 0, triggering Float.round/2 error
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", event_duration_ms: 0},
          %{sequence: 2, event: "handle_event", event_duration_ms: 0},
          %{sequence: 3, event: "handle_event", event_duration_ms: 2000}
        ]
      }

      # Should not crash with FunctionClauseError
      result = Performance.analyze(timeline, [])

      # Event 3 should be detected as critical (>1000ms)
      assert length(result.findings) > 0
      critical = Enum.find(result.findings, &(&1.severity == :critical))
      assert critical
      assert 3 in critical.events

      # Multiplier should be present in metadata and should be a number
      assert Map.has_key?(critical.metadata, :multiplier)
      assert is_number(critical.metadata.multiplier)
    end
  end
end
