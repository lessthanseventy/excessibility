defmodule Excessibility.TelemetryCapture.Analyzers.SummaryTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Analyzers.Summary

  describe "name/0" do
    test "returns :summary" do
      assert Summary.name() == :summary
    end
  end

  describe "default_enabled?/0" do
    test "returns true" do
      assert Summary.default_enabled?() == true
    end
  end

  describe "analyze/2" do
    test "generates summary for simple timeline" do
      timeline = %{
        test: "test/my_test.exs",
        duration_ms: 500,
        timeline: [
          %{event: "mount", sequence: 1},
          %{event: "handle_event:click", sequence: 2},
          %{event: "render", sequence: 3}
        ]
      }

      result = Summary.analyze(timeline, [])

      assert is_binary(result.stats.summary)
      assert String.contains?(result.stats.summary, "3 events")
      assert String.contains?(result.stats.summary, "500ms")
    end

    test "includes event breakdown" do
      timeline = %{
        test: "test.exs",
        duration_ms: 100,
        timeline: [
          %{event: "mount", sequence: 1},
          %{event: "render", sequence: 2},
          %{event: "render", sequence: 3},
          %{event: "handle_event:click", sequence: 4}
        ]
      }

      result = Summary.analyze(timeline, [])

      assert String.contains?(result.stats.summary, "render")
      assert result.stats.event_breakdown["render"] == 2
    end

    test "notes memory trend when growing" do
      timeline = %{
        test: "test.exs",
        duration_ms: 100,
        timeline: [
          %{event: "mount", sequence: 1, memory_size: 1000},
          %{event: "render", sequence: 2, memory_size: 2000},
          %{event: "render", sequence: 3, memory_size: 3000}
        ]
      }

      result = Summary.analyze(timeline, [])

      assert String.contains?(result.stats.summary, "memory") or
               String.contains?(result.stats.summary, "grew") or
               result.stats.memory_trend == :growing
    end

    test "handles empty timeline" do
      timeline = %{test: "test.exs", duration_ms: 0, timeline: []}
      result = Summary.analyze(timeline, [])

      assert is_binary(result.stats.summary)

      assert String.contains?(result.stats.summary, "Empty") or
               String.contains?(result.stats.summary, "0 events")
    end

    test "includes test name in summary" do
      timeline = %{
        test: "test/my_feature_test.exs:42",
        duration_ms: 100,
        timeline: [%{event: "mount", sequence: 1}]
      }

      result = Summary.analyze(timeline, [])

      assert String.contains?(result.stats.summary, "my_feature_test")
    end

    test "ranks top events by frequency" do
      timeline = %{
        test: "test.exs",
        duration_ms: 100,
        timeline: [
          %{event: "render", sequence: 1},
          %{event: "render", sequence: 2},
          %{event: "render", sequence: 3},
          %{event: "mount", sequence: 4},
          %{event: "handle_event:click", sequence: 5}
        ]
      }

      result = Summary.analyze(timeline, [])

      # render should appear first as most frequent
      assert String.contains?(result.stats.summary, "render (3x)")
    end
  end
end
