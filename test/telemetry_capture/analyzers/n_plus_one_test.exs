defmodule Excessibility.TelemetryCapture.Analyzers.NPlusOneTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Analyzers.NPlusOne

  describe "name/0" do
    test "returns :n_plus_one" do
      assert NPlusOne.name() == :n_plus_one
    end
  end

  describe "default_enabled?/0" do
    test "returns true" do
      assert NPlusOne.default_enabled?() == true
    end
  end

  describe "analyze/2" do
    test "returns map with findings and stats" do
      timeline = %{timeline: []}

      result = NPlusOne.analyze(timeline, [])

      assert is_map(result)
      assert Map.has_key?(result, :findings)
      assert Map.has_key?(result, :stats)
      assert is_list(result.findings)
      assert is_map(result.stats)
    end

    test "detects no issues when no NotLoaded associations" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", query_not_loaded_count: 0},
          %{sequence: 2, event: "handle_event", query_not_loaded_count: 0},
          %{sequence: 3, event: "handle_event", query_not_loaded_count: 0}
        ]
      }

      result = NPlusOne.analyze(timeline, [])

      assert result.findings == []
    end

    test "detects single event with NotLoaded associations" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", query_not_loaded_count: 5}
        ]
      }

      result = NPlusOne.analyze(timeline, [])

      assert length(result.findings) == 1
      finding = List.first(result.findings)
      assert finding.severity == :warning
      assert finding.message =~ "5 NotLoaded associations"
      assert finding.message =~ "event 1"
    end

    test "detects multiple events with NotLoaded associations" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", query_not_loaded_count: 3},
          %{sequence: 2, event: "handle_event", query_not_loaded_count: 5},
          %{sequence: 3, event: "handle_event", query_not_loaded_count: 2}
        ]
      }

      result = NPlusOne.analyze(timeline, [])

      assert length(result.findings) == 3
      assert Enum.all?(result.findings, &(&1.severity == :warning))
    end

    test "marks high NotLoaded count as critical" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", query_not_loaded_count: 15}
        ]
      }

      result = NPlusOne.analyze(timeline, [])

      assert length(result.findings) == 1
      finding = List.first(result.findings)
      assert finding.severity == :critical
      assert finding.message =~ "15 NotLoaded associations"
    end

    test "includes event sequences in findings" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", query_not_loaded_count: 0},
          %{sequence: 2, event: "handle_event", query_not_loaded_count: 3},
          %{sequence: 3, event: "handle_event", query_not_loaded_count: 0}
        ]
      }

      result = NPlusOne.analyze(timeline, [])

      assert length(result.findings) == 1
      finding = List.first(result.findings)
      assert finding.events == [2]
    end

    test "calculates statistics" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", query_not_loaded_count: 3},
          %{sequence: 2, event: "handle_event", query_not_loaded_count: 7},
          %{sequence: 3, event: "handle_event", query_not_loaded_count: 5}
        ]
      }

      result = NPlusOne.analyze(timeline, [])

      assert result.stats.total_not_loaded == 15
      assert result.stats.max_not_loaded == 7
      assert result.stats.avg_not_loaded == 5
    end

    test "handles empty timeline" do
      timeline = %{timeline: []}

      result = NPlusOne.analyze(timeline, [])

      assert result.findings == []
      assert result.stats == %{}
    end

    test "handles timeline without query enrichment data" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount"},
          %{sequence: 2, event: "handle_event"}
        ]
      }

      result = NPlusOne.analyze(timeline, [])

      # Should not crash, treat as 0 NotLoaded
      assert result.findings == []
    end
  end
end
