defmodule Excessibility.TelemetryCapture.Analyzers.HypothesisTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Analyzers.Hypothesis

  describe "name/0" do
    test "returns :hypothesis" do
      assert Hypothesis.name() == :hypothesis
    end
  end

  describe "default_enabled?/0" do
    test "returns false" do
      # Only runs when explicitly requested
      assert Hypothesis.default_enabled?() == false
    end
  end

  describe "analyze/2" do
    test "generates hypothesis for memory growth" do
      timeline = %{
        timeline: [
          %{event: "mount", sequence: 1, memory_size: 1000, list_sizes: %{}},
          %{event: "render", sequence: 2, memory_size: 5000, list_sizes: %{items: 50}},
          %{event: "render", sequence: 3, memory_size: 10_000, list_sizes: %{items: 100}}
        ]
      }

      result = Hypothesis.analyze(timeline, [])

      assert length(result.findings) > 0
      finding = List.first(result.findings)
      assert finding.severity == :info

      assert String.contains?(finding.message, "list") or String.contains?(finding.message, "items") or
               String.contains?(finding.message, "Memory")
    end

    test "suggests preload when query counts increase" do
      timeline = %{
        timeline: [
          %{event: "mount", sequence: 1, query_records_loaded: 1},
          %{event: "render", sequence: 2, query_records_loaded: 10},
          %{event: "render", sequence: 3, query_records_loaded: 50}
        ]
      }

      result = Hypothesis.analyze(timeline, [])

      assert Enum.any?(result.findings, &String.contains?(&1.message, "preload"))
    end

    test "no hypotheses for healthy timeline" do
      timeline = %{
        timeline: [
          %{event: "mount", sequence: 1, memory_size: 1000},
          %{event: "render", sequence: 2, memory_size: 1100},
          %{event: "render", sequence: 3, memory_size: 1050}
        ]
      }

      result = Hypothesis.analyze(timeline, [])

      assert Enum.empty?(result.findings)
    end

    test "includes investigation steps" do
      timeline = %{
        timeline: [
          %{event: "mount", sequence: 1, memory_size: 1000},
          %{event: "render", sequence: 2, memory_size: 50_000}
        ]
      }

      result = Hypothesis.analyze(timeline, [])

      finding = List.first(result.findings)
      assert Map.has_key?(finding.metadata, :investigation_steps)
      assert is_list(finding.metadata.investigation_steps)
    end

    test "handles empty timeline" do
      result = Hypothesis.analyze(%{timeline: []}, [])

      assert result.findings == []
      assert result.stats.hypothesis_count == 0
    end

    test "handles missing enrichment data gracefully" do
      timeline = %{
        timeline: [
          %{event: "mount", sequence: 1},
          %{event: "render", sequence: 2}
        ]
      }

      result = Hypothesis.analyze(timeline, [])

      # Should not crash, may have no findings
      assert is_list(result.findings)
    end
  end
end
