defmodule Excessibility.TelemetryCapture.AnalyzerTest do
  use ExUnit.Case, async: true

  # Test implementation of analyzer
  defmodule TestAnalyzer do
    @moduledoc false
    @behaviour Excessibility.TelemetryCapture.Analyzer

    def name, do: :test
    def default_enabled?, do: true

    def analyze(timeline, _opts) do
      event_count = length(timeline.timeline)

      %{
        findings:
          if(event_count > 5,
            do: [
              %{
                severity: :warning,
                message: "Many events detected",
                events: [1, 2, 3],
                metadata: %{count: event_count}
              }
            ],
            else: []
          ),
        stats: %{event_count: event_count}
      }
    end
  end

  describe "analyzer behaviour" do
    test "implements required callbacks" do
      assert function_exported?(TestAnalyzer, :name, 0)
      assert function_exported?(TestAnalyzer, :default_enabled?, 0)
      assert function_exported?(TestAnalyzer, :analyze, 2)
    end

    test "analyze returns correct structure" do
      timeline = %{timeline: [1, 2, 3]}
      result = TestAnalyzer.analyze(timeline, [])

      assert is_map(result)
      assert Map.has_key?(result, :findings)
      assert Map.has_key?(result, :stats)
      assert is_list(result.findings)
      assert is_map(result.stats)
    end

    test "findings have required fields" do
      timeline = %{timeline: [1, 2, 3, 4, 5, 6]}
      result = TestAnalyzer.analyze(timeline, [])

      [finding | _] = result.findings
      assert finding.severity in [:info, :warning, :critical]
      assert is_binary(finding.message)
      assert is_list(finding.events)
      assert is_map(finding.metadata)
    end
  end
end
