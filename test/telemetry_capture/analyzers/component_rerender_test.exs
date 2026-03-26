defmodule Excessibility.TelemetryCapture.Analyzers.ComponentRerenderTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Analyzers.ComponentRerender

  describe "name/0" do
    test "returns :component_rerender" do
      assert ComponentRerender.name() == :component_rerender
    end
  end

  describe "default_enabled?/0" do
    test "returns false" do
      assert ComponentRerender.default_enabled?() == false
    end
  end

  describe "requires_enrichers/0" do
    test "declares component_tree enricher dependency" do
      assert ComponentRerender.requires_enrichers() == [:component_tree]
    end
  end

  describe "analyze/2" do
    test "returns correct structure" do
      result = ComponentRerender.analyze(%{timeline: []}, [])
      assert Map.has_key?(result, :findings)
      assert Map.has_key?(result, :stats)
    end

    test "detects wasted component re-renders" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", component_count: 4, component_ids: [1, 2, 3, 4], changes: %{items: [1]}},
          %{sequence: 2, event: "render", component_count: 4, component_ids: [1, 2, 3, 4], changes: %{page_title: "new"}},
          %{sequence: 3, event: "render", component_count: 4, component_ids: [1, 2, 3, 4], changes: %{}},
          %{sequence: 4, event: "render", component_count: 4, component_ids: [1, 2, 3, 4], changes: %{}},
          %{
            sequence: 5,
            event: "render",
            component_count: 4,
            component_ids: [1, 2, 3, 4],
            changes: %{page_title: "newer"}
          },
          %{sequence: 6, event: "render", component_count: 4, component_ids: [1, 2, 3, 4], changes: %{}},
          %{sequence: 7, event: "render", component_count: 4, component_ids: [1, 2, 3, 4], changes: %{}},
          %{sequence: 8, event: "render", component_count: 4, component_ids: [1, 2, 3, 4], changes: %{}}
        ]
      }

      result = ComponentRerender.analyze(timeline, [])

      assert length(result.findings) > 0
      finding = List.first(result.findings)
      assert finding.severity in [:warning, :critical]
      assert finding.message =~ "render"
    end

    test "no findings when all renders have changes" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", component_count: 2, component_ids: [1, 2], changes: %{items: [1]}},
          %{sequence: 2, event: "render", component_count: 2, component_ids: [1, 2], changes: %{items: [1, 2]}},
          %{sequence: 3, event: "render", component_count: 2, component_ids: [1, 2], changes: %{filter: "active"}}
        ]
      }

      result = ComponentRerender.analyze(timeline, [])
      assert result.findings == []
    end

    test "no findings when no components present" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", component_count: 0, component_ids: [], changes: %{}},
          %{sequence: 2, event: "render", component_count: 0, component_ids: [], changes: %{}},
          %{sequence: 3, event: "render", component_count: 0, component_ids: [], changes: %{}}
        ]
      }

      result = ComponentRerender.analyze(timeline, [])
      assert result.findings == []
    end

    test "handles empty timeline" do
      result = ComponentRerender.analyze(%{timeline: []}, [])
      assert result.findings == []
      assert result.stats == %{}
    end

    test "handles timeline without component data" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", changes: %{}},
          %{sequence: 2, event: "render", changes: %{}}
        ]
      }

      result = ComponentRerender.analyze(timeline, [])
      assert result.findings == []
    end
  end
end
