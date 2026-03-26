defmodule Excessibility.TelemetryCapture.Analyzers.AssignDiffTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Analyzers.AssignDiff

  describe "name/0" do
    test "returns :assign_diff" do
      assert AssignDiff.name() == :assign_diff
    end
  end

  describe "default_enabled?/0" do
    test "returns true" do
      assert AssignDiff.default_enabled?() == true
    end
  end

  describe "requires_enrichers/0" do
    test "declares assign_sizes enricher dependency" do
      assert AssignDiff.requires_enrichers() == [:assign_sizes]
    end
  end

  describe "analyze/2" do
    test "returns correct structure" do
      timeline = %{timeline: []}
      result = AssignDiff.analyze(timeline, [])

      assert is_map(result)
      assert Map.has_key?(result, :findings)
      assert Map.has_key?(result, :stats)
    end

    test "detects large assign re-diffed frequently" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", assign_sizes: %{current_user: 6000, filter: 100}, changes: %{}},
          %{sequence: 2, event: "handle_event:click", assign_sizes: %{current_user: 6000, filter: 100}, changes: %{current_user: %{}, filter: :new}},
          %{sequence: 3, event: "handle_event:click", assign_sizes: %{current_user: 6000, filter: 100}, changes: %{current_user: %{}, toggled: true}},
          %{sequence: 4, event: "handle_event:click", assign_sizes: %{current_user: 6000, filter: 100}, changes: %{current_user: %{}}},
          %{sequence: 5, event: "render", assign_sizes: %{current_user: 6000, filter: 100}, changes: %{current_user: %{}}}
        ]
      }

      result = AssignDiff.analyze(timeline, [])

      assert length(result.findings) > 0
      finding = List.first(result.findings)
      assert finding.severity in [:warning, :critical]
      assert finding.message =~ "current_user"
      assert finding.metadata.assign_name == :current_user
    end

    test "does not flag small assigns even if frequently diffed" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", assign_sizes: %{filter: 100}, changes: %{}},
          %{sequence: 2, event: "handle_event:click", assign_sizes: %{filter: 100}, changes: %{filter: :new}},
          %{sequence: 3, event: "handle_event:click", assign_sizes: %{filter: 100}, changes: %{filter: :updated}}
        ]
      }

      result = AssignDiff.analyze(timeline, [])
      assert result.findings == []
    end

    test "critical severity for very large assigns (>20KB)" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", assign_sizes: %{big: 25_000}, changes: %{}},
          %{sequence: 2, event: "render", assign_sizes: %{big: 25_000}, changes: %{big: %{}}},
          %{sequence: 3, event: "render", assign_sizes: %{big: 25_000}, changes: %{big: %{}}}
        ]
      }

      result = AssignDiff.analyze(timeline, [])

      assert length(result.findings) > 0
      assert List.first(result.findings).severity == :critical
    end

    test "handles empty timeline" do
      result = AssignDiff.analyze(%{timeline: []}, [])
      assert result.findings == []
      assert result.stats == %{}
    end

    test "handles timeline without assign_sizes data" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", changes: %{}},
          %{sequence: 2, event: "render", changes: %{}}
        ]
      }

      result = AssignDiff.analyze(timeline, [])
      assert result.findings == []
    end

    test "includes diff ratio in stats" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", assign_sizes: %{user: 6000}, changes: %{}},
          %{sequence: 2, event: "render", assign_sizes: %{user: 6000}, changes: %{user: %{}}},
          %{sequence: 3, event: "render", assign_sizes: %{user: 6000}, changes: %{}}
        ]
      }

      result = AssignDiff.analyze(timeline, [])
      assert Map.has_key?(result.stats, :assign_diff_ratios)
    end
  end
end
